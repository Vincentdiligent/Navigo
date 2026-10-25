allprojects {
    repositories {
        // Local mirror first: a slim repack of org.maplibre.gl:android-sdk-opengl
        // 13.5.0 (arm64 .so only, no prefab headers) — same coordinates, same
        // artifacts the plugin needs, ~150 MB less extraction per build.
        maven { url = uri("/home/z/local-maven") }
        google()
        mavenCentral()
    }
    // play-services-location 21.4.0 ships Kotlin 2.3 metadata, unreadable by
    // the Kotlin 2.1 toolchain of this project; 21.3.0 is compatible.
    configurations.all {
        resolutionStrategy {
            force("com.google.android.gms:play-services-location:21.3.0")
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
