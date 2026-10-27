plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.yureru.yureru"
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
        // Stable, globally unique application id for Yureru installations.
        applicationId = "dev.yureru.yureru"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val releaseStoreFile = providers.gradleProperty("yureruReleaseStoreFile").orNull
        ?: System.getenv("YURERU_ANDROID_KEYSTORE")
    val releaseStorePassword = providers.gradleProperty("yureruReleaseStorePassword").orNull
        ?: System.getenv("YURERU_ANDROID_STORE_PASSWORD")
    val releaseKeyAlias = providers.gradleProperty("yureruReleaseKeyAlias").orNull
        ?: System.getenv("YURERU_ANDROID_KEY_ALIAS")
    val releaseKeyPassword = providers.gradleProperty("yureruReleaseKeyPassword").orNull
        ?: System.getenv("YURERU_ANDROID_KEY_PASSWORD")
    val hasReleaseSigning = listOf(
        releaseStoreFile,
        releaseStorePassword,
        releaseKeyAlias,
        releaseKeyPassword,
    ).all { !it.isNullOrBlank() }

    if (hasReleaseSigning) {
        signingConfigs.create("release") {
            storeFile = file(releaseStoreFile!!)
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    } else {
        logger.warn(
            "Android release signing is not configured; release builds use the debug key. " +
                "Set YURERU_ANDROID_KEYSTORE, YURERU_ANDROID_STORE_PASSWORD, " +
                "YURERU_ANDROID_KEY_ALIAS and YURERU_ANDROID_KEY_PASSWORD for distribution.",
        )
    }

    buildTypes {
        release {
            // Keep `flutter run --release` usable locally, but use a private
            // upload key whenever distribution credentials are configured.
            signingConfig = signingConfigs.getByName(
                if (hasReleaseSigning) "release" else "debug",
            )
        }
    }
}

flutter {
    source = "../.."
}
