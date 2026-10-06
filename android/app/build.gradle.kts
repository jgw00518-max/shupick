import java.util.Base64

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Native app keys are supplied through the same local dart-define file as Dart.
val socialDartDefines = (project.findProperty("dart-defines") as? String)
    ?.split(",")
    ?.mapNotNull { encoded ->
        runCatching { String(Base64.getDecoder().decode(encoded), Charsets.UTF_8) }.getOrNull()
    }
    ?.associate { definition -> definition.substringBefore("=") to definition.substringAfter("=", "") }
    ?: emptyMap()
val kakaoNativeAppKey = socialDartDefines["KAKAO_NATIVE_APP_KEY"].orEmpty()
require(kakaoNativeAppKey.isEmpty() || kakaoNativeAppKey.matches(Regex("[A-Fa-f0-9]{32}"))) {
    "KAKAO_NATIVE_APP_KEY must be a native app key (32 hexadecimal characters)."
}

android {
    namespace = "com.example.shupick"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.shupick"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["kakaoScheme"] = "kakao" + kakaoNativeAppKey.ifEmpty { "unconfigured" }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
