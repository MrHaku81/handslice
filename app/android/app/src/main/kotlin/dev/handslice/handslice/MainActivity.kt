package dev.handslice.handslice

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Platform-Channel-Methoden fuer das Engine-Backend:
//   nativeLibraryDir -> Pfad, in dem der Package-Installer libhandslice_cli.so
//                       abgelegt hat (Datei ist read-only + PROT_EXEC;
//                       execve() ist dort unter Android 10+ erlaubt,
//                       in getFilesDir() dagegen nicht; W^X-Policy).
//
// Siehe docs/engine-integration.md "Native-Library-Ablage" und
// developer.android.com/about/versions/10/behavior-changes-10 Abschnitt
// "Execution of files from the writable app home directory is a W^X
// violation".
class MainActivity : FlutterActivity() {
    private val channel = "dev.handslice.handslice/engine"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "nativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
                else -> result.notImplemented()
            }
        }
    }
}
