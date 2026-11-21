import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.example.pixel"
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.openflix.client"
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                val storeFilePath = keystoreProperties.getProperty("storeFile")?.trim()
                    ?.takeIf { it.isNotEmpty() }
                    ?: throw GradleException("Missing 'storeFile' in android/key.properties")
                storeFile = file(storeFilePath)
                storePassword = keystoreProperties.getProperty("storePassword")?.trim()
                    ?.takeIf { it.isNotEmpty() }
                    ?: throw GradleException("Missing 'storePassword' in android/key.properties")
                keyAlias = keystoreProperties.getProperty("keyAlias")?.trim()
                    ?.takeIf { it.isNotEmpty() }
                    ?: throw GradleException("Missing 'keyAlias' in android/key.properties")
                keyPassword = keystoreProperties.getProperty("keyPassword")?.trim()
                    ?.takeIf { it.isNotEmpty() }
                    ?: throw GradleException("Missing 'keyPassword' in android/key.properties")
            }
        }
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/INDEX.LIST",
                "META-INF/io.netty.versions.properties",
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
                "META-INF/*.kotlin_module",
            )
        }
    }

    buildTypes {
        release {
            // Wire android/key.properties into signingConfigs.release and assign it to
            // buildTypes.release (never silently falling back to debug signing when key.properties is present).
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Dynamically loaded CloudStream 3 (.cs3) DEX plugins resolve host Kotlin stdlib,
            // coroutines, NiceHttp, Jackson, Jsoup, Rhino, and CloudStream library symbols via
            // PathClassLoader at runtime. Keep full JVM/Kotlin bytecode unstripped so plugins
            // never hit NoClassDefFoundError (e.g., Lkotlin/jvm/functions/Function0;).
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("com.github.recloudstream.cloudstream:library:4.9.1")
    implementation("com.github.Blatzar:NiceHttp:0.4.18")
    implementation("com.fasterxml.jackson.module:jackson-module-kotlin:2.13.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.preference:preference-ktx:1.2.1")
    // Host runtime libraries referenced by official CloudStream 3 (.cs3) plugins
    implementation("com.google.android.material:material:1.12.0")
    implementation("com.google.code.gson:gson:2.11.0")
    implementation("androidx.compose.foundation:foundation:1.8.0")
    implementation("androidx.compose.material3:material3:1.3.2")
    implementation("androidx.activity:activity-compose:1.10.1")
}

flutter {
    source = "../.."
}
