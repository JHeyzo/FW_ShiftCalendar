#!/usr/bin/env python3
"""Verify the JNI-facing Kotlin declarations in a release APK's actual DEX.

Requires only Python's standard library and Android SDK's ``apkanalyzer``.
The checker intentionally verifies DEX output (not just R8 configuration or a
mapping file), because JNI performs lookups by literal class/member names and
JVM descriptors at runtime.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass


REGISTRAR = "io.flutter.plugins.sharedpreferences.SharedPreferencesApiRegistrar"
API_INTERFACE = "io.flutter.plugins.sharedpreferences.SharedPreferencesApi"
CONTINUATION = "kotlin.coroutines.Continuation"
OBJECT = "java.lang.Object"
STRING = "java.lang.String"
LIST = "java.util.List"
THROWABLE = "java.lang.Throwable"

# These are the literal methods looked up by messages.g.jni.dart for
# SharedPreferencesApiRegistrar (including every generated suspend bridge).
REGISTRAR_METHODS: dict[str, str] = {
    "<init>": "()V",
    "register": "(Lio/flutter/plugins/sharedpreferences/SharedPreferencesApi;Ljava/lang/String;)Lio/flutter/plugins/sharedpreferences/SharedPreferencesApiRegistrar;",
    "getInstance": "(Ljava/lang/String;)Lio/flutter/plugins/sharedpreferences/SharedPreferencesApiRegistrar;",
    "remove": "(Ljava/lang/String;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;",
    "setBool": "(Ljava/lang/String;ZLkotlin/coroutines/Continuation;)Ljava/lang/Object;",
    "setString": "(Ljava/lang/String;Ljava/lang/String;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;",
    "setInt": "(Ljava/lang/String;JLkotlin/coroutines/Continuation;)Ljava/lang/Object;",
    "setDouble": "(Ljava/lang/String;DLkotlin/coroutines/Continuation;)Ljava/lang/Object;",
    "setEncodedStringList": "(Ljava/lang/String;Ljava/lang/String;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;",
    "setDeprecatedStringList": "(Ljava/lang/String;Ljava/util/List;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;",
    "clear": "(Ljava/lang/String;Ljava/util/List;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;",
    "getAll": "(Ljava/lang/String;Ljava/util/List;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;",
}

# Additional direct lookups in package:jni/src/kotlin.dart. IntrinsicsKt's
# implementation may live on a superclass, so that lookup follows .super.
DIRECT_CLASSES = (
    API_INTERFACE,
    CONTINUATION,
    "kotlin.coroutines.intrinsics.CoroutineSingletons",
    "kotlin.coroutines.intrinsics.IntrinsicsKt",
    "kotlin.Result",
    "kotlin.Result$Failure",
    "kotlin.Unit",
)

CLASS_RE = re.compile(r"^\.class\s+.*?L([^;]+);\s*$", re.MULTILINE)
SUPER_RE = re.compile(r"^\.super\s+L([^;]+);\s*$", re.MULTILINE)
METHOD_RE = re.compile(r"^\.method\s+.*?([^\s(]+)(\([^\r\n]*\)\S+)\s*$", re.MULTILINE)
FIELD_RE = re.compile(r"^\.field\s+.*?([^\s:]+):(\S+)\s*$", re.MULTILINE)


@dataclass
class DexClass:
    name: str
    text: str
    methods: dict[str, set[str]]
    fields: set[tuple[str, str]]
    superclass: str | None


class VerificationError(Exception):
    pass


def parse_mapping(path: Path | None) -> dict[str, str]:
    """Return original binary class name -> obfuscated binary class name."""
    if path is None:
        return {}
    mapping: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as exc:
        raise VerificationError(f"cannot read mapping file {path}: {exc}") from exc
    for line in lines:
        # Member mappings are indented; only class-level lines end in a colon.
        if line.startswith((" ", "\t")) or not line.endswith(":") or " -> " not in line:
            continue
        original, obfuscated = line[:-1].split(" -> ", 1)
        if original and obfuscated and " " not in original and " " not in obfuscated:
            mapping[original] = obfuscated
    return mapping


def _resolve_class(name: str, mapping: dict[str, str]) -> str:
    return mapping.get(name, name)


def _parse_class(text: str, requested_name: str) -> DexClass | None:
    class_match = CLASS_RE.search(text)
    if not class_match:
        return None
    actual = class_match.group(1).replace("/", ".")
    methods: dict[str, set[str]] = {}
    for match in METHOD_RE.finditer(text):
        methods.setdefault(match.group(1), set()).add(match.group(2))
    fields = {(match.group(1), match.group(2)) for match in FIELD_RE.finditer(text)}
    super_match = SUPER_RE.search(text)
    superclass = super_match.group(1).replace("/", ".") if super_match else None
    return DexClass(actual, text, methods, fields, superclass)


def _run_class(apkanalyzer: str, apk: Path, class_name: str) -> DexClass | None:
    command = [apkanalyzer, "dex", "code", "--class", class_name, str(apk)]
    try:
        proc = subprocess.run(command, capture_output=True, text=True, check=False)
    except OSError as exc:
        raise VerificationError(f"could not execute apkanalyzer: {exc}") from exc
    parsed = _parse_class(proc.stdout or "", class_name)
    # Missing/renamed classes are expected validation failures, not tool
    # failures: keep checking the other lookups to produce a useful report.
    return parsed


def verify_apk(apk: Path, apkanalyzer: str, mapping_path: Path | None = None) -> list[str]:
    """Raise VerificationError on any missing or altered DEX bridge symbol."""
    if not apk.is_file():
        raise VerificationError(f"APK does not exist or is not a file: {apk}")
    mapping = parse_mapping(mapping_path)
    errors: list[str] = []
    cache: dict[str, DexClass | None] = {}

    def get_class(name: str) -> DexClass | None:
        actual_name = _resolve_class(name, mapping)
        if actual_name not in cache:
            cache[actual_name] = _run_class(apkanalyzer, apk, actual_name)
        return cache[actual_name]

    # Inspect the registrar in the DEX, resolve each real class name using the
    # optional mapping, and compare the bytecode descriptors against the exact
    # descriptors the generated Dart binding looks up.
    registrar = get_class(REGISTRAR)
    if registrar is None:
        errors.append(f"DEX class missing: {REGISTRAR}")
    else:
        if registrar.name != REGISTRAR:
            errors.append(f"registrar DEX class is renamed: expected {REGISTRAR}, found {registrar.name}")
        for method, descriptor in REGISTRAR_METHODS.items():
            actual = registrar.methods.get(method, set())
            if descriptor not in actual:
                found = ", ".join(sorted(actual)) if actual else "<missing>"
                errors.append(f"{REGISTRAR}.{method}: expected descriptor {descriptor}; found {found}")

    # Class literals in JNI are also ABI: verify that each directly looked-up
    # dependency exists under its literal name in DEX. API interface is already
    # checked as a descriptor above, but checking its class catches a missing
    # definition as well.
    for class_name in DIRECT_CLASSES:
        dex_class = get_class(class_name)
        if dex_class is None:
            errors.append(f"DEX class missing: {class_name}")
        elif dex_class.name != class_name:
            errors.append(f"JNI class name is renamed: expected {class_name}, found {dex_class.name}")

    continuation = get_class(CONTINUATION)
    if continuation is not None and "(Ljava/lang/Object;)V" not in continuation.methods.get("resumeWith", set()):
        errors.append("kotlin.coroutines.Continuation.resumeWith: expected (Ljava/lang/Object;)V")

    result = get_class("kotlin.Result")
    if result is not None and ("value", "Ljava/lang/Object;") not in result.fields:
        errors.append("kotlin.Result.value: expected field descriptor Ljava/lang/Object;")

    failure = get_class("kotlin.Result$Failure")
    if failure is not None:
        if ("exception", "Ljava/lang/Throwable;") not in failure.fields:
            errors.append("kotlin.Result$Failure.exception: expected field descriptor Ljava/lang/Throwable;")
        if "(Ljava/lang/Throwable;)V" not in failure.methods.get("<init>", set()):
            errors.append("kotlin.Result$Failure.<init>: expected (Ljava/lang/Throwable;)V")

    unit = get_class("kotlin.Unit")
    if unit is not None and ("INSTANCE", "Lkotlin/Unit;") not in unit.fields:
        errors.append("kotlin.Unit.INSTANCE: expected field descriptor Lkotlin/Unit;")

    # IntrinsicsKt may inherit the static implementation from a generated
    # superclass. Follow the actual DEX superclass chain and require its exact
    # JNI method descriptor wherever it is declared.
    intrinsics_name = "kotlin.coroutines.intrinsics.IntrinsicsKt"
    current = get_class(intrinsics_name)
    seen: set[str] = set()
    found_suspended = False
    while current is not None and current.name not in seen:
        seen.add(current.name)
        if "()Ljava/lang/Object;" in current.methods.get("getCOROUTINE_SUSPENDED", set()):
            found_suspended = True
            break
        if not current.superclass:
            break
        current = get_class(current.superclass)
    if not found_suspended:
        errors.append("kotlin.coroutines.intrinsics.IntrinsicsKt.getCOROUTINE_SUSPENDED: expected ()Ljava/lang/Object; on class or superclass")

    if errors:
        raise VerificationError("release JNI bridge verification failed:\n  - " + "\n  - ".join(errors))

    return [
        f"Verified actual DEX bridge methods: {len(REGISTRAR_METHODS)} SharedPreferencesApiRegistrar JNI bindings",
        "Verified actual DEX JNI dependencies/lookups: SharedPreferencesApi, Continuation.resumeWith, CoroutineSingletons, IntrinsicsKt.getCOROUTINE_SUSPENDED, Result, Result$Failure, Unit",
    ]


def find_apkanalyzer(explicit: str | None) -> str | None:
    if explicit:
        if os.path.isfile(explicit) and os.access(explicit, os.X_OK):
            return explicit
        return shutil.which(explicit)
    found = shutil.which("apkanalyzer")
    if found:
        return found
    sdk_roots = [os.environ.get("ANDROID_HOME"), os.environ.get("ANDROID_SDK_ROOT")]
    for root in filter(None, sdk_roots):
        candidates = (
            Path(root) / "cmdline-tools/latest/bin/apkanalyzer",
            Path(root) / "cmdline-tools/bin/apkanalyzer",
            Path(root) / "tools/bin/apkanalyzer",
        )
        for candidate in candidates:
            if candidate.is_file() and os.access(candidate, os.X_OK):
                return str(candidate)
    return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path, help="release APK to inspect")
    parser.add_argument("--apkanalyzer", help="apkanalyzer executable (defaults to PATH or ANDROID_HOME/ANDROID_SDK_ROOT)")
    parser.add_argument("--mapping", type=Path, help="optional R8 mapping.txt used to locate renamed DEX classes; DEX remains authoritative")
    args = parser.parse_args(argv)

    tool = find_apkanalyzer(args.apkanalyzer)
    if not tool:
        print("error: apkanalyzer not found; set --apkanalyzer or ANDROID_HOME/ANDROID_SDK_ROOT", file=sys.stderr)
        return 2
    mapping = args.mapping
    if mapping is None:
        repo_mapping = Path(__file__).resolve().parents[1] / "build/app/outputs/mapping/release/mapping.txt"
        if repo_mapping.is_file():
            mapping = repo_mapping
    try:
        for message in verify_apk(args.apk, tool, mapping):
            print(message)
        print(f"APK: {args.apk}")
        if mapping:
            print(f"Mapping used only to locate DEX classes: {mapping}")
        return 0
    except VerificationError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
