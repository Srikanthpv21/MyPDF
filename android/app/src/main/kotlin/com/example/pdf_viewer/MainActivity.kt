package com.example.pdf_viewer

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.pdf_viewer/intent"
    private var initialPdfPath: String? = null
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
        initialPdfPath?.let { path ->
            methodChannel?.invokeMethod("onPdfOpened", path)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                if (call.method == "getInitialPdf") {
                    result.success(initialPdfPath)
                    initialPdfPath = null
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.action == Intent.ACTION_VIEW) {
            val uri: Uri? = intent.data
            if (uri != null) {
                initialPdfPath = copyUriToInternalFile(uri)
            }
        }
    }

    private fun copyUriToInternalFile(uri: Uri): String? {
        return try {
            if (uri.scheme == "file") {
                val filePath = uri.path ?: return null
                val file = File(filePath)
                return if (file.exists()) file.canonicalPath else null
            }

            var fileName = "opened_document.pdf"
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val nameIndex = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (nameIndex != -1 && cursor.moveToFirst()) {
                    val name = cursor.getString(nameIndex)
                    if (!name.isNullOrBlank()) {
                        fileName = name
                    }
                }
            }

            // Security Hardening: Strip directory paths & sanitize characters to prevent path traversal (CWE-22)
            val cleanBaseName = File(fileName).name.replace(Regex("[^a-zA-Z0-9._-]"), "_")
            val sanitizedFileName = if (cleanBaseName.lowercase().endsWith(".pdf")) {
                cleanBaseName
            } else {
                "$cleanBaseName.pdf"
            }

            val pdfCacheDir = File(cacheDir, "opened_pdfs").apply { mkdirs() }
            val cacheFile = File(pdfCacheDir, "${System.currentTimeMillis()}_$sanitizedFileName")

            // Verify canonical path stays strictly inside pdfCacheDir
            if (!cacheFile.canonicalPath.startsWith(pdfCacheDir.canonicalPath)) {
                throw SecurityException("Path traversal attempt in filename: $fileName")
            }

            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(cacheFile).use { output ->
                    input.copyTo(output)
                }
            }

            // Prune old cached PDF files (keep last 15 files)
            pruneCacheDirectory(pdfCacheDir, maxFiles = 15)

            cacheFile.canonicalPath
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun pruneCacheDirectory(dir: File, maxFiles: Int) {
        try {
            val files = dir.listFiles() ?: return
            if (files.size > maxFiles) {
                files.sortBy { it.lastModified() }
                for (i in 0 until (files.size - maxFiles)) {
                    files[i].delete()
                }
            }
        } catch (_: Exception) {}
    }
}
