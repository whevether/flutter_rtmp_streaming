plugins {
    id("com.android.library")
}

group = "com.app.rtmp_streaming"
version = "2.1.0"

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:9.4.0")
    }
}

rootProject.allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
}

android {
    namespace = "com.app.rtmp_streaming"
    compileSdk = 37
    buildToolsVersion = "37.0.0"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        minSdk = 21
    }

    lint {
        disable += "InvalidPackage"
    }
}



dependencies {
    implementation("androidx.annotation:annotation:1.10.0")
    implementation("org.jetbrains.kotlin:kotlin-stdlib:2.4.10")
    implementation("com.github.pedroSG94.RootEncoder:library:2.8.1")
    implementation("com.github.pedroSG94.RootEncoder:extra-sources:2.8.1")
}
