import org.gradle.api.Project

allprojects {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        google()
        mavenCentral()
    }
}

subprojects {
    configurations.all {
        resolutionStrategy {
            force("androidx.core:core:1.13.1")
            force("androidx.appcompat:appcompat:1.7.0")
            force("androidx.activity:activity:1.9.0")
            force("androidx.fragment:fragment:1.8.0")
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
    pluginManager.withPlugin("com.android.application") {
        extensions.configure<com.android.build.api.dsl.ApplicationExtension>("android") {
            compileSdk = 36
        }
    }

    pluginManager.withPlugin("com.android.library") {
        extensions.configure<com.android.build.api.dsl.LibraryExtension>("android") {
            compileSdk = 36
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    val project = this
    val fixNamespaceAction = Action<Project> {
        if (project.hasProperty("android")) {
            val android = project.extensions.getByName("android")
            try {
                // 使用反射尝试获取并设置 namespace
                val getNamespace = android.javaClass.getMethod("getNamespace")
                if (getNamespace.invoke(android) == null) {
                    val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
                    setNamespace.invoke(android, project.group.toString())
                }
            } catch (e: Exception) {
                // 忽略不支持 namespace 属性的旧版或非 Android 插件
            }
        }
    }

    // 核心修复：如果项目已经执行完评估，则直接运行逻辑；否则才放入回调
    if (project.state.executed) {
        fixNamespaceAction.execute(project)
    } else {
        project.afterEvaluate(fixNamespaceAction)
    }
}

subprojects {
    afterEvaluate {
        if (name.contains("isar")) {
            tasks.matching { it.name.contains("verifyReleaseResources") }.configureEach {
                enabled = false
            }
        }
    }
}
