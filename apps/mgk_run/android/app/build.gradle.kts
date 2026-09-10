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
//
// Identical to apps/mgk_lift's block, deliberately. The two apps ship from one
// `codemagic.yaml` and a difference between them here would be a difference in
// what a green build means — which is the failure this whole file exists to
// prevent. If one changes, change the other.
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
    namespace = "com.mgkcodes.fitness.run"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // The suite's id, naming the structure rather than the product — see
        // docs/decisions/0018-bundle-identifiers-name-the-structure.md. It is
        // also what Play's listing and the RevenueCat Google app are keyed on,
        // so it cannot change after the first upload.
        applicationId = "com.mgkcodes.fitness.run"
        // 26, not Flutter's default 24, because the `health` plugin declares
        // 26 and the manifest merger refuses the mismatch outright — the
        // Android build simply stops.
        //
        // Cheap here in a way it would not be for an Android-first app: this
        // repo is iOS-first (ADR-0001) and Android is the surface the preview
        // harness is reviewed on, so the devices this excludes are ones the
        // app was never shipping to. API 26 is Android 8.0, from 2017.
        minSdk = 26
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
