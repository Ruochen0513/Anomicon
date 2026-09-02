plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.suixin.anomicon"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.suixin.anomicon"
        minSdk = 26
        targetSdk = 35
        versionCode = 1000000
        versionName = "1.0.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    sourceSets {
        getByName("main") {
            assets.srcDirs(
                "src/main/assets",
                "../../products/phone/src/main/resources/rawfile"
            )
        }
    }

    buildTypes {
        debug {
            isDebuggable = true
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-android-debug"
        }
        release {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    buildFeatures {
        compose = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.10.00"))
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.6")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.6")
    implementation("androidx.navigation:navigation-compose:2.8.3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jsoup:jsoup:1.18.1")

    debugImplementation("androidx.compose.ui:ui-tooling")
}
