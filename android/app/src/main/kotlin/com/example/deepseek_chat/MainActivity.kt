package com.example.deepseek_chat

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.Activity
import android.content.Intent
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private val keyAlias = "deepseek_api_key_v1"
    private var exportResult: MethodChannel.Result? = null
    private var exportText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "deepseek_chat/platform")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "compressImage" -> {
                            val input = call.argument<String>("path") ?: error("Missing path")
                            val output = call.argument<String>("output") ?: error("Missing output")
                            Thread {
                                try {
                                    val bitmap = android.graphics.BitmapFactory.decodeFile(input) ?: error("Invalid image")
                                    try {
                                        var bytes: ByteArray
                                        var quality = 92
                                        do {
                                            val stream = java.io.ByteArrayOutputStream()
                                            check(bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, quality, stream))
                                            bytes = stream.toByteArray()
                                            quality -= 10
                                        } while (bytes.size > 5 * 1024 * 1024 && quality >= 22)
                                        check(bytes.size <= 5 * 1024 * 1024)
                                        java.io.File(output).writeBytes(bytes)
                                        runOnUiThread { result.success(output) }
                                    } finally { bitmap.recycle() }
                                } catch (e: Exception) {
                                    runOnUiThread { result.error("IMAGE_FAILED", "Could not compress image", null) }
                                }
                            }.start()
                        }
                        "readKey" -> result.success(readKey())
                        "writeKey" -> { writeKey(call.arguments as String); result.success(null) }
                        "goToDesktop" -> { moveTaskToBack(true); result.success(null) }
                        "exportHistory", "exportChatText" -> {
                            if (exportResult != null) {
                                result.error("BUSY", "请先完成当前导出", null)
                            } else {
                                exportText = call.arguments as String
                                exportResult = result
                                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    val plainText = call.method == "exportChatText"
                                    type = if (plainText) "text/plain" else "application/json"
                                    val extension = if (plainText) "txt" else "json"
                                    val prefix = if (plainText) "Wanxiang-chat" else "Wanxiang-history"
                                    putExtra(Intent.EXTRA_TITLE, "$prefix-${System.currentTimeMillis()}.$extension")
                                }
                                startActivityForResult(intent, 117)
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    if (call.method == "exportHistory" || call.method == "exportChatText") { exportResult = null; exportText = null }
                    result.error("LOCAL_STORAGE", "本机安全存储或文件操作失败，请重试", null)
                }
            }
    }

    private fun secretKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(keyAlias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(keyAlias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
            generateKey()
        }
    }

    private fun writeKey(value: String) {
        val prefs = getSharedPreferences("ds_secure", MODE_PRIVATE)
        if (value.isEmpty()) {
            check(prefs.edit().clear().commit())
            return
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        check(prefs.edit()
            .putString("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .putString("ciphertext", Base64.encodeToString(encrypted, Base64.NO_WRAP)).commit())
    }

    private fun readKey(): String? {
        val prefs = getSharedPreferences("ds_secure", MODE_PRIVATE)
        val data = prefs.getString("ciphertext", null) ?: return null
        val iv = prefs.getString("iv", null) ?: error("Missing IV")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP)))
        return String(cipher.doFinal(Base64.decode(data, Base64.NO_WRAP)), Charsets.UTF_8)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 117) return
        val result = exportResult ?: return
        val text = exportText
        exportResult = null
        exportText = null
        if (resultCode != Activity.RESULT_OK || data?.data == null || text == null) {
            result.success(false)
            return
        }
        val uri = data.data!!
        Thread {
            try {
                val output = contentResolver.openOutputStream(uri) ?: error("Cannot open destination")
                output.use { it.write(text.toByteArray(Charsets.UTF_8)) }
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                runOnUiThread { result.error("EXPORT_FAILED", "未能保存文件，请重新选择位置", null) }
            }
        }.start()
    }
}
