import com.android.build.api.dsl.CommonExtension

allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
        maven { url  = uri("https://maven.aliyun.com/repository/public") }
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    afterEvaluate {
        if (plugins.hasPlugin("com.android.application") || plugins.hasPlugin("com.android.library")) {
            extensions.configure<CommonExtension> {
                compileSdk { version = release(37) }
                buildToolsVersion = "37.0.0"
                // Pin to an NDK present on the machine; avoid auto-download of flutter.ndkVersion.
                ndkVersion = "30.0.16248370"
                if (namespace == null) {
                    namespace = project.group.toString()
                }
            }
        }
    }
    layout.buildDirectory.set(rootProject.layout.buildDirectory.dir(project.name))
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
