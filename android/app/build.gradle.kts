import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials are loaded from android/key.properties, which is
// git-ignored and created locally (and in CI) at release time. When the file is
// absent — every developer machine by default — the release build falls back to
// the debug keystore so `flutter build apk --release` still works.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}
val hasReleaseKeystore = keystorePropertiesFile.exists()

android {
    namespace = "com.sidrahayat.docuai"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Permanent Play Store identity — this can never be changed after the
        // first upload.
        applicationId = "com.sidrahayat.docuai"
        // ML Kit requires API 21+; Flutter's current default (24) already
        // satisfies this, so we track the SDK value rather than pinning.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
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
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // A release build signed with the debug key cannot be uploaded
                // to Play. The build is still allowed so the release path can be
                // exercised locally, but it must never do that quietly — see
                // the warning emitted below.
                signingConfigs.getByName("debug")
            }

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// Fails loudly at configuration time rather than at submission time. The debug
// keystore is a working signature, so without this the only symptom is Play
// rejecting the upload days later.
if (!hasReleaseKeystore) {
    logger.warn(
        "\n" +
            "┌───────────────────────────────────────────────────────────────┐\n" +
            "│ WARNING: android/key.properties is missing.                   │\n" +
            "│ Release builds are being signed with the DEBUG keystore and   │\n" +
            "│ CANNOT be uploaded to Google Play.                            │\n" +
            "│ See android/key.properties.example.                           │\n" +
            "└───────────────────────────────────────────────────────────────┘\n",
    )
}

flutter {
    source = "../.."
}

dependencies {
    // Declared explicitly rather than relied on transitively through
    // play-services-mlkit-document-scanner: MainActivity calls
    // GoogleApiAvailability directly, and a transitive dependency that the
    // scanner plugin later drops would break the build for a non-obvious
    // reason.
    implementation("com.google.android.gms:play-services-base:18.5.0")

    // Declared for the same reason as the line above: ExternalOpener calls
    // androidx.core.content.FileProvider directly. It arrives transitively
    // through the Flutter embedding today, and a transitive dependency that
    // something later drops would break the build for a non-obvious reason.
    implementation("androidx.core:core:1.13.1")
}
