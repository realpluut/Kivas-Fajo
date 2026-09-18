allprojects {
    repositories {
        google()
        mavenCentral()
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

// Some plugin modules (e.g. file_picker) still hardcode an older compileSdk
// in their own build.gradle, which now trails what their own transitive
// deps (flutter_plugin_android_lifecycle) require. Force every Android
// module to compile against a current SDK rather than chasing compatible
// package-version combinations across the whole dependency graph. Must be
// registered before the evaluationDependsOn block below, which forces
// early evaluation of :app -- afterEvaluate throws once a project's already
// evaluated, so this has to be queued first.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.withGroovyBuilder {
            setProperty("compileSdkVersion", 36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
