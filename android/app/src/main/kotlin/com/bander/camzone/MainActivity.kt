package com.bander.camzone

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// ملحوظة: لازم FlutterFragmentActivity مش FlutterActivity العادية —
// مكتبة local_auth بتحتاج الـ Activity تكون FragmentActivity عشان
// تقدر تعرض بروبمت البصمة/Face ID أو قفل الشاشة (PIN/Pattern/Password).
// من غيرها بترجع خطأ uiUnavailable (أو no_fragment_activity في
// النسخ الأقدم) وما تقدرش تفتح أي بروبمت مصادقة خالص.
class MainActivity: FlutterFragmentActivity() {

    private val CHANNEL = "camzone/encryption"
    private val SECURITY_CHANNEL = "camzone/security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // بيتحكم في FLAG_SECURE (منع screenshot/screen recording) وقت
        // فتح شاشة الخزنة — عملناها هنا مباشرة بدل ما نعتمد على مكتبة
        // خارجية (flutter_windowmanager) عشان دي مكتبة قديمة مش متحدثة
        // وبتكسر الـ Gradle build مع AGP الحديث (مفيش namespace محدد في
        // build.gradle بتاعها).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURITY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableSecureFlag" -> {
                        runOnUiThread {
                            window.setFlags(
                                WindowManager.LayoutParams.FLAG_SECURE,
                                WindowManager.LayoutParams.FLAG_SECURE
                            )
                        }
                        result.success(true)
                    }
                    "disableSecureFlag" -> {
                        runOnUiThread {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->

                when (call.method) {

                    "encryptFileNative" -> {
                        val input = call.argument<String>("inputPath")
                        val output = call.argument<String>("outputPath")
                        val key = call.argument<String>("publicKeyPath")

                        if (input == null || output == null || key == null) {
                            result.error("INVALID_ARGUMENTS", "Missing encryption arguments", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val success = CryptoBridge.encryptFileNative(input, output, key)
                            result.success(success)
                        } catch (e: Exception) {
                            result.error("ENCRYPT_ERROR", e.message, null)
                        }
                    }

                    // --- Streaming / real-time video encryption ---

                    "startStreamEncryption" -> {
                        val output = call.argument<String>("outputPath")
                        val key = call.argument<String>("publicKeyPath")

                        if (output == null || key == null) {
                            result.error("INVALID_ARGUMENTS", "Missing stream-start arguments", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val handle = CryptoBridge.startStreamEncryptionNative(output, key)
                            if (handle == 0L) {
                                result.error("STREAM_START_FAILED", "Native stream init failed", null)
                            } else {
                                result.success(handle)
                            }
                        } catch (e: Exception) {
                            result.error("STREAM_START_ERROR", e.message, null)
                        }
                    }

                    "feedStreamEncryption" -> {
                        val handle = call.argument<Number>("handle")?.toLong()
                        val data = call.argument<ByteArray>("data")

                        if (handle == null || data == null) {
                            result.error("INVALID_ARGUMENTS", "Missing stream-feed arguments", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val ok = CryptoBridge.feedStreamEncryptionNative(handle, data)
                            result.success(ok)
                        } catch (e: Exception) {
                            result.error("STREAM_FEED_ERROR", e.message, null)
                        }
                    }

                    "finishStreamEncryption" -> {
                        val handle = call.argument<Number>("handle")?.toLong()

                        if (handle == null) {
                            result.error("INVALID_ARGUMENTS", "Missing handle", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val ok = CryptoBridge.finishStreamEncryptionNative(handle)
                            result.success(ok)
                        } catch (e: Exception) {
                            result.error("STREAM_FINISH_ERROR", e.message, null)
                        }
                    }

                    "abortStreamEncryption" -> {
                        val handle = call.argument<Number>("handle")?.toLong()
                        if (handle != null) {
                            try {
                                CryptoBridge.abortStreamEncryptionNative(handle)
                            } catch (_: Exception) { }
                        }
                        result.success(null)
                    }

                    // --- Post-recording integrity check ---
                    // Structural verification only (header + size sanity) -
                    // see CryptoBridge.verifyEncryptedFileNative for why full
                    // cryptographic (GCM tag) verification can't happen on
                    // the device.
                    "verifyEncryptedVideo" -> {
                        val path = call.argument<String>("path")

                        if (path == null) {
                            result.error("INVALID_ARGUMENTS", "Missing path", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val valid = CryptoBridge.verifyEncryptedFileNative(path)
                            result.success(valid)
                        } catch (e: Exception) {
                            result.error("VERIFY_ERROR", e.message, null)
                        }
                    }

                    // --- Decryption (device holds the RSA private key) ---

                    "decryptFileToBytes" -> {
                        val input = call.argument<String>("inputPath")
                        val privateKeyPem = call.argument<String>("privateKeyPem")

                        if (input == null || privateKeyPem == null) {
                            result.error("INVALID_ARGUMENTS", "Missing decryption arguments", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val plaintext = CryptoBridge.decryptFileToBytesNative(input, privateKeyPem)
                            if (plaintext == null) {
                                result.error(
                                    "DECRYPT_FAILED",
                                    "Decryption failed - file may be corrupted, tampered, or the wrong private key was used",
                                    null
                                )
                            } else {
                                result.success(plaintext)
                            }
                        } catch (e: Exception) {
                            result.error("DECRYPT_ERROR", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}