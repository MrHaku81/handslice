package dev.handslice.handslice

import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

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
                "saveVideoToGallery" -> saveVideoToGallery(call, result)
                "saveGcodeToDownloads" -> saveGcodeToDownloads(call, result)
                "openUri" -> openUri(call, result)
                else -> result.notImplemented()
            }
        }
    }

    // Kopiert eine G-Code-Datei via MediaStore nach Download/Handslice.
    // Ziel: fuer Nutzer im Datei-Manager sichtbar (Scoped Storage,
    // kein WRITE_EXTERNAL_STORAGE noetig). MediaStore.Downloads
    // existiert erst ab API 29; wir unterstuetzen nichts darunter
    // (minSdk=29 fuer handslice).
    //
    // Aufruf: args = { "srcPath": String, "displayName": String,
    //                   "mime": String? ("application/octet-stream") }
    // Rueckgabe: Content-URI als String; der Caller nutzt das fuer
    // Share + Open-Intent, so dass der Nutzer die Datei ohne Weg
    // ueber die interne App-Sandbox oeffnen kann.
    // Startet ACTION_VIEW auf einer content:// URI – damit kann der
    // Nutzer eine gerade in MediaStore gespeicherte Datei direkt im
    // Datei-Manager / passenden Viewer oeffnen, ohne dass die App
    // eine READ_EXTERNAL_STORAGE-Permission braucht.
    //
    // Aufruf: args = { "uri": String, "mime": String? }
    // Rueckgabe: true = Intent gestartet, false = kein Handler gefunden.
    private fun openUri(call: io.flutter.plugin.common.MethodCall,
                        result: MethodChannel.Result) {
        val uriStr = call.argument<String>("uri")
            ?: return result.error("INVALID", "uri missing", null)
        val mime = call.argument<String>("mime")
        val uri = try { Uri.parse(uriStr) }
            catch (e: Exception) {
                return result.error("INVALID", "bad uri", null)
            }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            if (mime != null) setDataAndType(uri, mime) else setData(uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            startActivity(intent)
            result.success(true)
        } catch (_: ActivityNotFoundException) {
            result.success(false)
        }
    }

    private fun saveGcodeToDownloads(call: io.flutter.plugin.common.MethodCall,
                                     result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 29) {
            return result.error(
                "UNSUPPORTED",
                "MediaStore.Downloads requires API 29+",
                null,
            )
        }
        val src = call.argument<String>("srcPath")
            ?: return result.error("INVALID", "srcPath missing", null)
        val name = call.argument<String>("displayName")
            ?: return result.error("INVALID", "displayName missing", null)
        val mime = call.argument<String>("mime") ?: "application/octet-stream"
        val file = File(src)
        if (!file.exists()) {
            return result.error("NOT_FOUND", "src not found: $src", null)
        }
        val relative = "${Environment.DIRECTORY_DOWNLOADS}/Handslice"
        val resolver = applicationContext.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: return result.error(
                "INSERT_FAILED", "resolver.insert returned null", null)
        try {
            resolver.openOutputStream(uri).use { out ->
                if (out == null) {
                    throw IllegalStateException("openOutputStream returned null")
                }
                FileInputStream(file).use { input ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n <= 0) break
                        out.write(buf, 0, n)
                    }
                }
            }
            val finish = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            resolver.update(uri, finish, null, null)
            result.success(uri.toString())
        } catch (e: Exception) {
            try { resolver.delete(uri, null, null) } catch (_: Exception) {}
            result.error("WRITE_FAILED", e.message ?: e.toString(), null)
        }
    }

    // Kopiert eine Datei (bytes-identisch) in die Galerie via
    // MediaStore. Zielalbum: `Movies/Handslice/`. Kein
    // WRITE_EXTERNAL_STORAGE noetig (ab API 29 scoped storage),
    // Datei ueberlebt die App-Deinstallation und ist in der
    // Galerie sichtbar.
    //
    // Aufruf: args = { "srcPath": String, "displayName": String,
    //                   "mime": String? ("video/mp4") }
    // Rueckgabe: der Content-URI als String (z. B. content://media/.../12345)
    private fun saveVideoToGallery(call: io.flutter.plugin.common.MethodCall,
                                   result: MethodChannel.Result) {
        val src = call.argument<String>("srcPath")
            ?: return result.error("INVALID", "srcPath missing", null)
        val name = call.argument<String>("displayName")
            ?: return result.error("INVALID", "displayName missing", null)
        val mime = call.argument<String>("mime") ?: "video/mp4"
        val file = File(src)
        if (!file.exists()) {
            return result.error("NOT_FOUND", "src not found: $src", null)
        }
        val relative = "${Environment.DIRECTORY_MOVIES}/Handslice"
        val resolver = applicationContext.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            if (Build.VERSION.SDK_INT >= 29) {
                put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }
        val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
            ?: return result.error("INSERT_FAILED", "resolver.insert returned null", null)
        try {
            resolver.openOutputStream(uri).use { out ->
                if (out == null) {
                    throw IllegalStateException("openOutputStream returned null")
                }
                FileInputStream(file).use { input ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n <= 0) break
                        out.write(buf, 0, n)
                    }
                }
            }
            if (Build.VERSION.SDK_INT >= 29) {
                val finish = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                resolver.update(uri, finish, null, null)
            }
            result.success(uri.toString())
        } catch (e: Exception) {
            try { resolver.delete(uri, null, null) } catch (_: Exception) {}
            result.error("WRITE_FAILED", e.message ?: e.toString(), null)
        }
    }
}
