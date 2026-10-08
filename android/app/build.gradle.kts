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
        // Só processadores ARM (todos os tablets reais): o motor de voz no
        // aparelho traz bibliotecas grandes, e x86 só existe em emulador.
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }

    // Bibliotecas nativas comprimidas no APK (o motor de voz é grande): o
    // download da atualização fica bem menor.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
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
            // Regras para o otimizador não quebrar o motor de voz e o "Hey Jarvis".
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
    // Voz no aparelho (grátis, sem conta): motor sherpa-onnx (Apache 2.0) com
    // as vozes Supertonic 3 e Piper pt-BR, baixadas pelo próprio app.
    implementation(files("libs/sherpa-onnx-1.13.8.aar"))
    // Descompactar os pacotes de voz (.tar.bz2).
    implementation("org.apache.commons:commons-compress:1.28.0")
}
