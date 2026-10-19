# shared_preferences_android 2.5 uses JNI lookups from generated Dart code.
# R8 cannot see these class/member names or their JVM descriptors in libapp.so.
# Keep descriptor types too: preserving getAll alone still lets Continuation be
# renamed, causing NoSuchMethodError when reading existing preferences at startup.
-keep,includedescriptorclasses class io.flutter.plugins.sharedpreferences.** { *; }

# JNI coroutine helpers also look up these classes, fields and methods by name.
# Keep the small coroutine ABI, not all Kotlin / kotlinx.coroutines libraries.
-keep,includedescriptorclasses class kotlin.coroutines.** { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$* { *; }
-keep class kotlin.Unit { *; }
-keep,includedescriptorclasses class com.github.dart_lang.jni.** { *; }
