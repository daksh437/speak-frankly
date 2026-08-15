import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing config from android/key.properties (gitignored). Absent on
// machines without the keystore → release falls back to debug signing.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystore = keystorePropertiesFile.exists()
if (hasKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Firebase: only activate the google-services plugin once the config file is in
// place, so the app still builds before Firebase is wired. Register the Android
// app in the Firebase console with the applicationId below, download
// google-services.json into android/app/, and this turns on automatically.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.speakfrankly"
    compileSdk = flutter.compileSdkVersion
    // Highest NDK required across Firebase/plugin deps (backward compatible).
    // Bumped to 28.x because speech_to_text (core voice-first feature) requires
    // it; NDK is backward-compatible so other plugins are unaffected.
    ndkVersion = "28.2.13676358"

    compileOptions {
        // Required by flutter_local_notifications (java.time backport on minSdk 24).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.speakfrankly"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // firebase_auth needs minSdk 23; flutter_tts needs 24 → use 24.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Use the upload keystore when present; else fall back to debug signing.
            // A debug-signed release CANNOT be uploaded to Play — shout about it
            // rather than handing back a bundle that fails at upload time.
            if (!hasKeystore) {
                logger.warn("⚠️  android/key.properties not found — this release build is DEBUG-SIGNED and cannot be uploaded to Play.")
            }
            signingConfig = if (hasKeystore) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            // R8: shrink + obfuscate. Keeps live in proguard-rules.pro.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Backports java.time for flutter_local_notifications scheduling on minSdk 24.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
