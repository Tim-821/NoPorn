import java.io.File

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val keyStoreFile = File("keystore/guard.jks")
val keyPassFile = File("keystore/guard-password.txt")
val guardPass = if (keyPassFile.exists()) keyPassFile.readText().trim() else ""

android {
    namespace = "com.bulldog.guard"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.bulldog.guard"
        minSdk = 26
        targetSdk = 34
        versionCode = 7
        versionName = "2.5"
    }

    signingConfigs {
        create("release") {
            storeFile = keyStoreFile
            storePassword = guardPass
            keyAlias = "guard"
            keyPassword = guardPass
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
}
