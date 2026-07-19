package com.bander.camzone

import io.flutter.embedding.android.FlutterFragmentActivity
import android.os.Bundle
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import kotlin.concurrent.thread

class MainActivity : FlutterFragmentActivity() {

    private var sharedFilePath: String? = null
    private val FILE_CHANNEL = "app.launch/file"
    private val DECRYPT_CHANNEL = "native.decrypt"
    private val ENCRYPT_CHANNEL = "native.encrypt"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.action == Intent.ACTION_VIEW) {
            val uri = intent.data ?: return
            val name = uri.lastPathSegment ?: "shared_${System.currentTimeMillis()}.enc"
            val tempFile = File(cacheDir, name)

            try {
                contentResolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(tempFile).use { output ->
                        input.copyTo(output)
                    }
                }
                sharedFilePath = tempFile.absolutePath
            } catch (e: Exception) {
                e.printStackTrace()
                sharedFilePath = null
            }
        }
    }

    // --- الربط مع مكتبة C++ ---
    companion object {
        init {
            System.loadLibrary("native-lib")
        }
    }

    // تعريف الدوال الخارجية (Native Methods)
    external fun decryptFileNative(
        inputPath: String,
        outputPath: String,
        privateKeyPath: String
    ): Boolean

    external fun encryptFileNative(
        inputPath: String,
        outputPath: String,
        publicKeyPath: String
    ): Boolean

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. قناة استلام الملفات المشاركة
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "getSharedFile") {
                    result.success(sharedFilePath)
                    sharedFilePath = null
                } else {
                    result.notImplemented()
                }
            }

        // 2. قناة فك التشفير (Native Decrypt)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DECRYPT_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "decrypt") {
                    val input = call.argument<String>("inputPath")
                    val output = call.argument<String>("outputPath")
                    val key = call.argument<String>("privateKeyPath")

                    if (input != null && output != null && key != null) {
                        thread {
                            try {
                                val isSuccess = decryptFileNative(input, output, key)
                                runOnUiThread { result.success(isSuccess) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("NATIVE_DECRYPT_ERROR", e.message, null) }
                            }
                        }
                    } else {
                        result.error("ARGUMENT_ERROR", "Paths cannot be null", null)
                    }
                } else {
                    result.notImplemented()
                }
            }

        // 3. قناة التشفير (Native Encrypt)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ENCRYPT_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "encrypt") {
                    val input = call.argument<String>("inputPath")
                    val output = call.argument<String>("outputPath")
                    val key = call.argument<String>("publicKeyPath")

                    if (input != null && output != null && key != null) {
                        thread {
                            try {
                                val isSuccess = encryptFileNative(input, output, key)
                                runOnUiThread { result.success(isSuccess) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("NATIVE_ENCRYPT_ERROR", e.message, null) }
                            }
                        }
                    } else {
                        result.error("ARGUMENT_ERROR", "Paths cannot be null", null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}