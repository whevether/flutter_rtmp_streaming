plugins {
    id("com.android.library")
}

group = "com.app.rtmp_streaming"
version = "3.0.0"

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:9.4.1")
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
    compileSdkMinor = 2
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
    implementation("androidx.annotation:annotation:1.11.0")
    implementation("org.jetbrains.kotlin:kotlin-stdlib:2.4.21")
    implementation("com.github.pedroSG94.RootEncoder:library:2.8.1")
    implementation("com.github.pedroSG94.RootEncoder:extra-sources:2.8.1")
    testImplementation("junit:junit:4.13.2")
    // CameraX comes transitively from extra-sources (runtime); no compile deps needed
    // for facing-only CameraXSource.switchCamera().
}
