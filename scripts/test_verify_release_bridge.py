from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verify_release_bridge as verifier  # noqa: E402


APK = Path("fake-release.apk")


def class_text(name: str, *, methods: list[tuple[str, str]] | None = None,
               fields: list[tuple[str, str]] | None = None,
               superclass: str = "java.lang.Object") -> str:
    lines = [f".class public L{name.replace('.', '/')};"]
    if superclass:
        lines.append(f".super L{superclass.replace('.', '/')};")
    for method, descriptor in methods or []:
        lines.append(f".method public {method}{descriptor}")
        lines.append("    .end method")
    for field, descriptor in fields or []:
        lines.append(f".field public static {field}:{descriptor}")
    return "\n".join(lines) + "\n"


def good_dex() -> dict[str, str]:
    registrar_methods = list(verifier.REGISTRAR_METHODS.items())
    return {
        verifier.REGISTRAR: class_text(verifier.REGISTRAR, methods=registrar_methods),
        verifier.API_INTERFACE: class_text(verifier.API_INTERFACE),
        "kotlin.coroutines.Continuation": class_text(
            "kotlin.coroutines.Continuation", methods=[("resumeWith", "(Ljava/lang/Object;)V")]
        ),
        "kotlin.coroutines.intrinsics.CoroutineSingletons": class_text(
            "kotlin.coroutines.intrinsics.CoroutineSingletons"
        ),
        "kotlin.coroutines.intrinsics.IntrinsicsKt": class_text(
            "kotlin.coroutines.intrinsics.IntrinsicsKt",
            methods=[("getCOROUTINE_SUSPENDED", "()Ljava/lang/Object;")],
        ),
        "kotlin.Result": class_text("kotlin.Result", fields=[("value", "Ljava/lang/Object;")]),
        "kotlin.Result$Failure": class_text(
            "kotlin.Result$Failure",
            methods=[("<init>", "(Ljava/lang/Throwable;)V")],
            fields=[("exception", "Ljava/lang/Throwable;")],
        ),
        "kotlin.Unit": class_text("kotlin.Unit", fields=[("INSTANCE", "Lkotlin/Unit;")]),
    }


class VerifyReleaseBridgeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.apk = Path(self.tempdir.name) / "app.apk"
        self.apk.write_bytes(b"test apk placeholder")
        self.dex = good_dex()

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def run_verifier(self, dex: dict[str, str] | None = None,
                     mapping: Path | None = None) -> None:
        dex = dex if dex is not None else self.dex

        def fake_run(command, **kwargs):
            class_name = command[command.index("--class") + 1]
            text = dex.get(class_name)
            if text is None:
                return SimpleNamespace(returncode=1, stdout="", stderr="class not found")
            return SimpleNamespace(returncode=0, stdout=text, stderr="")

        with patch.object(verifier.subprocess, "run", side_effect=fake_run):
            verifier.verify_apk(self.apk, "apkanalyzer", mapping)

    def test_clean_release_dex_passes_all_bridge_and_runtime_lookups(self) -> None:
        self.run_verifier()

    def test_obfuscated_continuation_descriptor_fails(self) -> None:
        dex = good_dex()
        descriptor = verifier.REGISTRAR_METHODS["getAll"].replace(
            "Lkotlin/coroutines/Continuation;", "Lj5;"
        )
        dex[verifier.REGISTRAR] = class_text(
            verifier.REGISTRAR,
            methods=[(name, descriptor if name == "getAll" else sig)
                     for name, sig in verifier.REGISTRAR_METHODS.items()],
        )
        dex.pop("kotlin.coroutines.Continuation")
        with self.assertRaisesRegex(verifier.VerificationError, "getAll.*Continuation"):
            self.run_verifier(dex)

    def test_missing_registrar_fails(self) -> None:
        dex = good_dex()
        dex.pop(verifier.REGISTRAR)
        with self.assertRaisesRegex(verifier.VerificationError, "DEX class missing: .*SharedPreferencesApiRegistrar"):
            self.run_verifier(dex)

    def test_missing_get_all_fails(self) -> None:
        dex = good_dex()
        dex[verifier.REGISTRAR] = class_text(
            verifier.REGISTRAR,
            methods=[(name, sig) for name, sig in verifier.REGISTRAR_METHODS.items()
                     if name != "getAll"],
        )
        with self.assertRaisesRegex(verifier.VerificationError, "getAll.*expected descriptor.*found <missing>"):
            self.run_verifier(dex)

    def test_wrong_get_all_descriptor_fails_even_if_method_exists(self) -> None:
        dex = good_dex()
        dex[verifier.REGISTRAR] = class_text(
            verifier.REGISTRAR,
            methods=[(name, "(Ljava/lang/String;Ljava/lang/String;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;"
                      if name == "getAll" else sig)
                     for name, sig in verifier.REGISTRAR_METHODS.items()],
        )
        with self.assertRaisesRegex(verifier.VerificationError, "getAll.*expected descriptor"):
            self.run_verifier(dex)

    def test_continuation_class_renamed_fails_even_if_mapping_points_to_it(self) -> None:
        dex = good_dex()
        dex.pop("kotlin.coroutines.Continuation")
        dex["j5"] = class_text("j5", methods=[("resumeWith", "(Ljava/lang/Object;)V")])
        mapping_file = Path(self.tempdir.name) / "mapping.txt"
        mapping_file.write_text("kotlin.coroutines.Continuation -> j5:\n", encoding="utf-8")
        with self.assertRaisesRegex(verifier.VerificationError, "JNI class name is renamed.*Continuation"):
            self.run_verifier(dex, mapping_file)

    def test_intrinsics_lookup_can_be_inherited(self) -> None:
        dex = good_dex()
        dex["kotlin.coroutines.intrinsics.IntrinsicsKt"] = class_text(
            "kotlin.coroutines.intrinsics.IntrinsicsKt",
            superclass="kotlin.coroutines.intrinsics.IntrinsicsKt__IntrinsicsKt",
        )
        dex["kotlin.coroutines.intrinsics.IntrinsicsKt__IntrinsicsKt"] = class_text(
            "kotlin.coroutines.intrinsics.IntrinsicsKt__IntrinsicsKt",
            methods=[("getCOROUTINE_SUSPENDED", "()Ljava/lang/Object;")],
        )
        self.run_verifier(dex)


if __name__ == "__main__":
    unittest.main()
