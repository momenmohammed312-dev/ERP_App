allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Fallback namespace injection for legacy Android plugins that do not
// declare a namespace in their own build.gradle (required by AGP 8+).
// This is a permanent, repo-tracked fix. It replaces manually editing files
// inside the global pub-cache, which is not reliable (gets wiped by
// `flutter pub cache repair`, a fresh machine, or CI).
//
// `plugins.withId` is used instead of `afterEvaluate` because this script
// contains `subprojects { evaluationDependsOn(":app") }` which evaluates
// subprojects early; registering `afterEvaluate` afterwards throws
// "Cannot run Project.afterEvaluate(Action) when the project is already
// evaluated".
subprojects {
    plugins.withId("com.android.library") {
        val androidExt = extensions.findByType<com.android.build.gradle.LibraryExtension>()
        if (androidExt != null && androidExt.namespace == null) {
            androidExt.namespace = "com.legacyfix.${project.name.replace("-", "_").replace(".", "_")}"
        }
    }
    plugins.withId("com.android.application") {
        val androidExt = extensions.findByType<com.android.build.gradle.AppExtension>()
        if (androidExt != null && androidExt.namespace == null) {
            androidExt.namespace = "com.legacyfix.${project.name.replace("-", "_").replace(".", "_")}"
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
