plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.handslice.handslice"
    // file_picker (bzw. seine Transitiv-Dep flutter_plugin_android_lifecycle)
    // verlangt compileSdk 36. Flutter 3.47.8 Default (34) reicht nicht.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.handslice.handslice"
        // Android 10+ (CC2-Protokoll-Grenze; Poco X3 Pro ist Android 12).
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signing mit Debug-Keys fuer `flutter run --release` – Release-
            // Signing wird spaeter konfiguriert, wenn Store-Release ansteht.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Pack `libhandslice_cli.so` als echte Datei nach `nativeLibraryDir`.
    // Begruendung: Android 10+ verbietet execve() auf Dateien im
    // beschreibbaren App-Home-Dir (W^X-Policy, siehe
    // developer.android.com/about/versions/10/behavior-changes-10 Abschnitt
    // "Execution of files from the writable app home directory is a W^X
    // violation"). Executable Binaries muessen daher als `lib*.so` im
    // nativeLibraryDir liegen; dort sind sie read-only aber PROT_EXEC.
    // Mit `useLegacyPackaging = true` extrahiert der Installer die .so
    // beim Setup aus dem APK statt sie nur im APK zu mappen – noetig,
    // damit `Process.run()` eine echte FS-Pfadangabe hat.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

// Pre-Build-Hook: Kopiert handslice-cli-arm64 aus engine/bin/ nach
// jniLibs/arm64-v8a/libhandslice_cli.so. Vermeidet, das 14-MB-Binary
// doppelt im Repo zu halten (engine/bin/ ist gitignored, jniLibs/ wird
// durch das globale *.so-ignore auch vom Checkin ausgeschlossen).
val cliBinary = file("${rootProject.projectDir}/../../engine/bin/handslice-cli-arm64")
val jniTarget = file("src/main/jniLibs/arm64-v8a/libhandslice_cli.so")

val syncNativeBinary = tasks.register<Copy>("syncHandsliceNativeBinary") {
    from(cliBinary)
    into(jniTarget.parentFile)
    rename { "libhandslice_cli.so" }
    doFirst {
        if (!cliBinary.exists()) {
            throw GradleException(
                "handslice-cli-arm64 fehlt unter ${cliBinary.absolutePath}. " +
                "Bitte zuerst 'bash engine/build-cli-arm64.sh' laufen lassen."
            )
        }
    }
}

tasks.matching { it.name.startsWith("merge") && it.name.endsWith("JniLibFolders") }.configureEach {
    dependsOn(syncNativeBinary)
}
tasks.matching { it.name.startsWith("package") && (it.name.endsWith("Debug") || it.name.endsWith("Release")) }.configureEach {
    dependsOn(syncNativeBinary)
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
