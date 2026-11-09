import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The merchant owns this ignored file and key. Missing config produces an
// unsigned compile artifact; a partial config fails instead of using debug keys.
val merchantSigningFile = rootProject.file("key.properties")
val merchantSigning = Properties()
if (merchantSigningFile.exists()) {
    merchantSigningFile.inputStream().use { merchantSigning.load(it) }
    require(listOf("storeFile", "storePassword", "keyAlias", "keyPassword").all {
        !merchantSigning.getProperty(it).isNullOrBlank()
    }) { "android/key.properties requires all four merchant signing fields" }
    require(rootProject.file(merchantSigning.getProperty("storeFile")).isFile) {
        "Merchant signing key file does not exist"
    }
}

android {
    namespace = "com.elpsy.elpsy_shop"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.elpsy.elpsy_shop"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (merchantSigningFile.exists()) {
            create("merchantRelease") {
                storeFile = rootProject.file(merchantSigning.getProperty("storeFile"))
                storePassword = merchantSigning.getProperty("storePassword")
                keyAlias = merchantSigning.getProperty("keyAlias")
                keyPassword = merchantSigning.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Release artifacts stay unsigned until a merchant-owned signing key is configured.
            if (merchantSigningFile.exists()) {
                signingConfig = signingConfigs.getByName("merchantRelease")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
