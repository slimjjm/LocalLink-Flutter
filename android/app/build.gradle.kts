import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")

    // Firebase
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties().apply {
    load(FileInputStream(rootProject.file("key.properties")))
}

android {

    namespace = "com.locallink.app"

    compileSdk = flutter.compileSdkVersion

    ndkVersion = flutter.ndkVersion

    // =====================================================
    // SIGNING CONFIGS
    // =====================================================

    signingConfigs {

        create("release") {

            storeFile =
                file(
                    keystoreProperties["storeFile"] as String
                )

            storePassword =
                keystoreProperties["storePassword"] as String

            keyAlias =
                keystoreProperties["keyAlias"] as String

            keyPassword =
                keystoreProperties["keyPassword"] as String
        }
    }

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

       applicationId = "com.locallink.app"

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
                    "release"
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