import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("app/key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.navigo.navigo"
    compileSdk = flutter.compileSdkVersion
    // No plugin in this project ships native C/C++ code, so no NDK pin is
    // needed; leaving the default avoids a mandatory NDK download.

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // Required by flutter_local_notifications (java.time on minSdk 24).
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    // play-services-location 21.4.0 ships Kotlin 2.3 metadata which the
    // project's Kotlin 2.1 compiler cannot read; 21.3.0 is metadata-compatible.
    configurations.all {
        resolutionStrategy {
            force("com.google.android.gms:play-services-location:21.3.0")
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.navigo.navigo"
        // v9: single-ABI is enforced by the build command
        // (`flutter build apk --target-platform android-arm64 --split-per-abi`);
        // a hard ndk abiFilters here CONFLICTS with the splits config
        // ("arm64-v8a in ndk abiFilters cannot be present when splits abi
        // filters are set") and fails the v9 build outright.
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    packaging {
        jniLibs {
            // Strip debug/symbol sections from every native library that
            // ships in the APK. The Flutter engine artifact (libflutter.so)
            // is ~156 MB per ABI with DWARF debug info; stripping it drops
            // it to ~11 MB. Without this the release APK is ~540 MB.
            keepDebugSymbols -= "**/*.so"
        }
    }

    buildTypes {
        release {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

// v6.4 SANDBOX NOTE: this container is rebuilt from scratch, so the NDK is
// a minimal stub — but with REAL binutils symlinked as llvm-strip /
// llvm-objcopy (see toolchain/setup.sh). The strip pipeline now RUNS FOR
// REAL. Do NOT disable it: an AGP-disabled strip task feeds an empty
// output to the packager and the APK ships WITHOUT any native library
// (a silent 2.1 MB APK — the v6.4 build lesson).

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
