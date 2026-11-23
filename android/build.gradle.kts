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

// gothermo: compileSdk override
subprojects {
    if (name != "app") {
        afterEvaluate {
            val android = extensions.findByName("android")
            if (android != null) {
                val m = android.javaClass.methods.firstOrNull { it.name == "setCompileSdk" && it.parameterCount == 1 }
                    ?: android.javaClass.methods.firstOrNull { it.name == "setCompileSdkVersion" && it.parameterTypes[0] == Int::class.javaPrimitiveType }
                m?.invoke(android, 36)
            }
        }
    }
}

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
