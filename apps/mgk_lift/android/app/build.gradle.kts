import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Release signing material, read from two places and invented from neither.
//
//   CI     — Codemagic exports CM_KEYSTORE_PATH, CM_KEYSTORE_PASSWORD,
//            CM_KEY_ALIAS and CM_KEY_PASSWORD whenever a workflow declares
//            `android_signing`. The keystore file is uploaded to Codemagic once
//            and never lands in this repository.
//   Local  — android/key.properties, gitignored alongside *.jks and *.keystore.
//
// **Nothing here generates a key.** An upload key Play has already seen cannot
// be swapped without Google's intervention, so creating one silently is worse
// than failing.
// ---------------------------------------------------------------------------
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun signingMaterial(envName: String, propertyName: String): String? =
    System.getenv(envName)?.takeIf { it.isNotBlank() }
        ?: keystoreProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }

val keystorePath: String? = signingMaterial("CM_KEYSTORE_PATH", "storeFile")
val hasReleaseSigning: Boolean = keystorePath != null

// A build machine with no keystore must not quietly produce a debug-signed
// artifact. Play rejects one — but only after an upload that looked like it
// worked. Locally the fallback stays, so `flutter run --release` still works on
// an emulator without handing every machine the upload key.
if (!hasReleaseSigning && System.getenv("CI")?.isNotBlank() == true) {
    throw GradleException(
        "No Android signing material on a CI machine. Declare `android_signing` " +
            "in the Codemagic workflow so CM_KEYSTORE_PATH and friends are set. " +
            "Refusing to fall back to the debug key: a debug-signed bundle is " +
            "rejected by Play only after an upload that appeared to succeed.",
    )
}

android {
    namespace = "com.mgkcodes.liftio"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications (the rest-over alert) needs Java 8+ time
        // APIs on Android versions that lack them, and says so as a build
        // failure rather than a runtime one if this is missing.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Liftio's id, not the suite's `com.mgkcodes.fitness.*` — this app
        // replaces the shipped Liftio rather than launching beside it, and on
        // iOS that means inheriting its bundle id. Android matches so the two
        // stores name the same product the same way, even though Play has no
        // existing listing to inherit. See
        // docs/decisions/0001-liftio-is-replaced-not-relaunched.md.
        applicationId = "com.mgkcodes.liftio"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = file(keystorePath!!)
                storePassword = signingMaterial("CM_KEYSTORE_PASSWORD", "storePassword")
                keyAlias = signingMaterial("CM_KEY_ALIAS", "keyAlias")
                keyPassword = signingMaterial("CM_KEY_PASSWORD", "keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                // Local convenience only — the CI guard above makes this
                // unreachable on a build machine.
                //
                // A banner rather than logger.warn, which Flutter's Gradle
                // output filtering swallows: the artifact this produces looks
                // exactly like a real one and is rejected by Play, so the only
                // signal that it is not shippable has to survive skim-reading.
                println("=".repeat(72))
                println("WARNING: signing the release build with the DEBUG key.")
                println("Fine for `flutter run --release` on an emulator. This")
                println("artifact CANNOT be uploaded to Play — it will be")
                println("rejected as debug-signed. Set up android/key.properties")
                println("(see key.properties.example) for a real release build.")
                println("=".repeat(72))
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // The version flutter_local_notifications documents; see compileOptions.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
