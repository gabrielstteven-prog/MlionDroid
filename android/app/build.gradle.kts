plugins {
    id("com.android.application")
    id("kotlin-android")

    // GOOGLE SERVICES
    id("com.google.gms.google-services")

    // FLUTTER
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flutter_application_1"

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
        applicationId = "com.example.flutter_application_1"
        minSdk = flutter.minSdkVersion   // Spotify SDK exige mínimo 21
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            
            // Ativa o arquivo de regras do ProGuard para não deletar o Spotify
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    // Repositório local para o .aar do Spotify
    repositories {
        flatDir {
            dirs("libs")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Spotify App Remote AAR — baixe em:
    // https://github.com/spotify/android-sdk/releases
    // e coloque em android/app/libs/spotify-app-remote-release-0.8.0.aar
    implementation(files("libs/spotify-app-remote-release-0.8.0.aar"))
}