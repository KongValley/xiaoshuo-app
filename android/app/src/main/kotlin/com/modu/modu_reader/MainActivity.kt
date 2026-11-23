package com.modu.modu_reader

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 墨读 has no third-party plugins. On Android the local TXT picker is provided
 * here with the Storage Access Framework: the user selects documents, they are
 * copied into the app cache, and Dart imports the copies into the library.
 */
class MainActivity : FlutterActivity() {
    private var pendingPicker: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickTxtFiles" -> openTxtPicker(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun openTxtPicker(result: MethodChannel.Result) {
        if (pendingPicker != null) {
            result.error("busy", "文件选择器已经打开", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf("text/plain", "text/*", "application/octet-stream"),
            )
        }
        pendingPicker = result
        try {
            startActivityForResult(intent, REQUEST_PICK_TXT)
        } catch (error: Exception) {
            pendingPicker = null
            result.error("picker", error.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK_TXT) return
        val result = pendingPicker ?: return
        pendingPicker = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<String>())
            return
        }

        try {
            val uris = mutableListOf<Uri>()
            data.clipData?.let { clip ->
                for (index in 0 until clip.itemCount) {
                    uris.add(clip.getItemAt(index).uri)
                }
            }
            if (uris.isEmpty()) {
                data.data?.let { uris.add(it) }
            }

            val rootDir = File(cacheDir, "novel_imports")
            rootDir.listFiles()?.forEach { it.deleteRecursively() }
            val targetDir = File(
                rootDir,
                System.currentTimeMillis().toString(),
            )
            targetDir.mkdirs()

            val paths = mutableListOf<String>()
            for (uri in uris) {
                val displayName = queryDisplayName(uri)
                    ?: "novel_${System.currentTimeMillis()}.txt"
                if (!displayName.lowercase().endsWith(".txt")) continue
                val safeName = displayName.replace(Regex("[\\\\/:*?\"<>|]"), "_")
                val target = uniqueFile(targetDir, safeName)
                contentResolver.openInputStream(uri)?.use { input ->
                    target.outputStream().use { output ->
                        input.copyTo(output, 256 * 1024)
                    }
                } ?: continue
                paths.add(target.absolutePath)
            }
            result.success(paths)
        } catch (error: Exception) {
            result.error("copy", error.message, null)
        }
    }

    /** Keeps the original document name so the reader can use it as the title. */
    private fun uniqueFile(directory: File, name: String): File {
        var candidate = File(directory, name)
        if (!candidate.exists()) return candidate
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val extension = if (dot > 0) name.substring(dot) else ""
        var index = 2
        while (candidate.exists()) {
            candidate = File(directory, "$base ($index)$extension")
            index++
        }
        return candidate
    }

    private fun queryDisplayName(uri: Uri): String? {
        return contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    }

    companion object {
        private const val CHANNEL = "modu/native"
        private const val REQUEST_PICK_TXT = 0x4D4F
    }
}
