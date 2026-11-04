import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.envanter.envanter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Bildirim eklentisinin zamanlanmış bildirimleri eski Android'lerde
        // java.time'a dayanıyor (flutter_local_notifications).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.envanter.envanter"
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

    // Yayın imzası android/key.properties ve android/keystore/ içinde; ilk
    // dağıtılan APK'ların anahtarının aynısı (bilgisayarın hata ayıklama
    // anahtarına bağlı kalmasın). Dosya yoksa (başka bir makinede) eskisi gibi
    // hata ayıklama anahtarı kullanılır; o APK kurulu uygulamanın üstüne kurulamaz.
    val keyProps = Properties().apply {
        val file = rootProject.file("key.properties")
        if (file.exists()) file.inputStream().use { load(it) }
    }
    signingConfigs {
        if (keyProps.containsKey("storeFile")) {
            create("release") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }

    // Yerel kütüphaneler APK içinde sıkıştırılır, kurulumda yalnızca telefonun mimarisininki açılır.
    // Uygulama elden (APK dosyasıyla) dağıtılıyor ve tek, üç mimarili ("evrensel") APK kullanılıyor:
    // sıkıştırmasız APK 87 MB, sıkıştırılmış 40 MB. Telefonda kaplanan yer de azalıyor (arm64'te
    // ~87 MB yerine ~69 MB: sıkıştırmasızda üç mimarinin kütüphaneleri açık halde APK'da durur);
    // kurulum biraz uzar.
    packaging {
        jniLibs {
            useLegacyPackaging = true
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Tarayıcının kod okuyucusu (QR ve ürün barkodları; PlatformCalls "readBarcodes"): zxing-cpp,
    // Apache-2.0. Önceki tarayıcının ML Kit'i kapalı kaynaktı: uygulama F-Droid'e giremiyordu,
    // Google'a kullanım ölçümü de gönderiyordu.
    implementation("io.github.zxing-cpp:android:3.1.1")
}
