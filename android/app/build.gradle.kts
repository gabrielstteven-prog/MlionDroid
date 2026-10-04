import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")

    // GOOGLE SERVICES
    id("com.google.gms.google-services")

    // FLUTTER
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Assinatura de release ────────────────────────────────────────────────────
// Lê android/key.properties (fora do git). Se o arquivo não existir, o build
// de release cai na chave de debug deste PC — que é a mesma usada até hoje,
// então as atualizações continuam instalando por cima nos tablets.
// Veja o README, seção "Chave de assinatura".
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val temChaveRelease = keystorePropertiesFile.exists()
if (temChaveRelease) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
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
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (temChaveRelease) {
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
            signingConfig = if (temChaveRelease) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Palavra de ativação "Hey Jarvis" (openWakeWord): os modelos ficam em
    // assets/wakeword e rodam no próprio tablet — sem conta nem chave.
    implementation("org.tensorflow:tensorflow-lite:2.17.0")
}
