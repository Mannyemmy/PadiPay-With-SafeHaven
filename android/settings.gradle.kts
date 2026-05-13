pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        maven {
            url = uri("https://sdk.sudo.africa/repository/maven-releases/")
            credentials {
                username = System.getenv("MAVEN_REPO_USERNAME") ?: ""
                password = System.getenv("MAVEN_REPO_PASSWORD") ?: ""
            }
        }
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
        maven { url = uri("https://repo.qoreid.com/repository/maven-releases/") }
        maven {
            url = uri("https://sdk.sudo.africa/repository/maven-releases/")
            credentials {
                username = providers.gradleProperty("maven.repo.username").orElse("allgood").get()
                password = providers.gradleProperty("maven.repo.password").orElse("H3\$yQ7@N5t").get()
            }
        }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.3.15") apply false
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
