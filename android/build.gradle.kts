// THÊM ĐOẠN NÀY VÀO DƯỚI CÙNG CỦA FILE ĐỂ KHAI BÁO PLUGIN FIREBASE
plugins {
    id("com.google.gms.google-services") version "4.4.1" apply false
}
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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
// ĐOẠN CODE VÁ LỖI NAMESPACE - ĐÃ FIX LỖI VÒNG ĐỜI GRADLE (CHẠY TRỰC TIẾP)
// =========================================================================
subprojects {
    // Định nghĩa một hàm xử lý cấu hình namespace độc lập
    val configureNamespace = Action<Project> {
        val androidExtension = extensions.findByName("android")
        if (androidExtension != null) {
            val manifestFile = file("${projectDir}/src/main/AndroidManifest.xml")
            var packageName: String? = null

            if (manifestFile.exists()) {
                try {
                    val content = manifestFile.readText()
                    val match = Regex("""package\s*=\s*"([^"]+)"""").find(content)
                    if (match != null) {
                        packageName = match.groupValues[1]
                    }
                } catch (e: Exception) {
                    // Bỏ qua lỗi đọc file
                }
            }

            if (project.plugins.hasPlugin("com.android.library")) {
                configure<com.android.build.gradle.LibraryExtension> {
                    if (namespace == null) {
                        namespace = packageName ?: "com.example.${project.name.replace("_", ".")}"
                    }
                }
            } else if (project.plugins.hasPlugin("com.android.application")) {
                configure<com.android.build.gradle.BaseExtension> {
                    if (namespace == null) {
                        namespace = packageName ?: "com.example.${project.name.replace("_", ".")}"
                    }
                }
            }
        }
    }

    // Kiểm tra: Nếu project chưa đánh giá thì đợi, nếu đã evaluated rồi thì thực thi ngay lập tức
    if (state.executed) {
        configureNamespace.execute(this)
    } else {
        afterEvaluate {
            configureNamespace.execute(this)
        }
    }
}
