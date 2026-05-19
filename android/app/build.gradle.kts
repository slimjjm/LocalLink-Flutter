plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")

    // Firebase
    id("com.google.gms.google-services")
}

android {

    namespace = "com.example.locallink_flutter"

    compileSdk = flutter.compileSdkVersion

    ndkVersion = flutter.ndkVersion

    // =====================================================
    // JAVA / DESUGARING
    // =====================================================

    compileOptions {

        sourceCompatibility =
            JavaVersion.VERSION_17

        targetCompatibility =
            JavaVersion.VERSION_17

        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {

        jvmTarget = "17"
    }

    // =====================================================
    // DEFAULT CONFIG
    // =====================================================

    defaultConfig {

        applicationId =
            "com.example.locallink_flutter"

        minSdk =
            flutter.minSdkVersion

        targetSdk =
            flutter.targetSdkVersion

        versionCode =
            flutter.versionCode

        versionName =
            flutter.versionName
    }

    // =====================================================
    // BUILD TYPES
    // =====================================================

    buildTypes {

        release {

            signingConfig =
                signingConfigs.getByName(
                    "debug"
                )
        }
    }
}

// =====================================================
// DESUGARING DEPENDENCY
// =====================================================

dependencies {

    coreLibraryDesugaring(
        "com.android.tools:desugar_jdk_libs:2.1.4"
    )
}

// =====================================================
// FLUTTER
// =====================================================

flutter {
    source = "../.."
}