plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.sportsdug.app"
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
        // Update with your unique Application ID
        applicationId = "com.sportsdug.app"
        minSdk = 21  // Minimum Android 5.0
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // Multi-dex support for larger apps
        multiDexEnabled = true
    }

    signingConfigs {
        // Create signing configs for release builds
        create("release") {
            // TODO: Configure your release signing
            // Store file, key alias, and passwords should be in local.properties
            // or use environment variables for CI/CD
            storeFile = file(System.getenv("KEYSTORE_FILE") ?: "../keystore.jks")
            keyAlias = System.getenv("KEYSTORE_ALIAS") ?: "sportsdug"
            storePassword = System.getenv("KEYSTORE_PASSWORD") ?: ""
            keyPassword = System.getenv("KEY_PASSWORD") ?: ""
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
    }
    
    // Enable view binding
    buildFeatures {
        viewBinding = true
    }
}

flutter {
    source = "../.."
}
