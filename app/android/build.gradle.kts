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

    // flutter_quill's quill_native_bridge_android ships Java 11; other plugins may
    // default Kotlin to 21. Force JVM 17 for both so release builds succeed.
    //
    // The Kotlin override must be registered inside afterEvaluate: plugins like
    // workmanager_android hard-set jvmTarget = "1.8" in their own build.gradle
    // during evaluation, and task configuration actions run in registration
    // order, so an action registered earlier than the plugin's would lose.
    afterEvaluate {
        extensions.findByName("android")?.let { androidExt ->
            val compileOptions = androidExt.javaClass.getMethod("getCompileOptions").invoke(androidExt)
            compileOptions.javaClass.getMethod(
                "setSourceCompatibility",
                JavaVersion::class.java,
            ).invoke(compileOptions, JavaVersion.VERSION_17)
            compileOptions.javaClass.getMethod(
                "setTargetCompatibility",
                JavaVersion::class.java,
            ).invoke(compileOptions, JavaVersion.VERSION_17)
        }

        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(
                org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17,
            )
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
