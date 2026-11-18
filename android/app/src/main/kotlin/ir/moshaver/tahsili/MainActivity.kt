package ir.moshaver.tahsili

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private var pendingBackupResult: MethodChannel.Result? = null
    private var pendingBackupContent: String? = null

    override fun provideFlutterEngine(context: android.content.Context): FlutterEngine? {
        return FlutterEngineCache.getInstance().get(ENGINE_ID)
            ?: super.provideFlutterEngine(context)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "encrypt" -> result.success(encryptLocalData(call.argument<String>("plaintext") ?: throw IllegalArgumentException("متن ارسال نشده است."), call.argument<String>("key") ?: throw IllegalArgumentException("کلید داده ارسال نشده است.")))
                        "decrypt" -> result.success(decryptLocalData(call.argument<String>("ciphertext") ?: throw IllegalArgumentException("داده رمزنگاری‌شده ارسال نشده است."), call.argument<String>("key") ?: throw IllegalArgumentException("کلید داده ارسال نشده است.")))
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("secure_storage", error.message ?: "عملیات رمزنگاری ناموفق بود.", null)
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKUP_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (pendingBackupResult != null) {
                    result.error("backup_busy", "یک عملیات فایل پشتیبان در حال اجراست.", null)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "saveBackup" -> {
                        val content = call.argument<String>("content")
                        val fileName = call.argument<String>("fileName") ?: DEFAULT_BACKUP_NAME
                        if (content == null || content.toByteArray(Charsets.UTF_8).size > MAX_BACKUP_BYTES) {
                            result.error("invalid_backup", "محتوای پشتیبان معتبر یا در محدوده مجاز نیست.", null)
                            return@setMethodCallHandler
                        }
                        pendingBackupResult = result
                        pendingBackupContent = content
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/json"
                            putExtra(Intent.EXTRA_TITLE, fileName)
                        }
                        launchBackupPicker(intent, REQUEST_SAVE)
                    }
                    "openBackup" -> {
                        pendingBackupResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/json"
                        }
                        launchBackupPicker(intent, REQUEST_OPEN)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun localEncryptionKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(LOCAL_DATA_KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(LOCAL_DATA_KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256).setRandomizedEncryptionRequired(true).build())
        return generator.generateKey()
    }

    private fun encryptLocalData(plaintext: String, storageKey: String): String {
        require(plaintext.toByteArray(Charsets.UTF_8).size <= MAX_LOCAL_VALUE_BYTES) { "اطلاعات بیش از اندازه مجاز است." }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, localEncryptionKey())
        require(storageKey.length <= 256) { "شناسه فضای ذخیره‌سازی معتبر نیست." }
        cipher.updateAAD(storageKey.toByteArray(Charsets.UTF_8))
        val encrypted = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        return ENCRYPTED_PREFIX + Base64.encodeToString(byteArrayOf(2) + cipher.iv + encrypted, Base64.NO_WRAP)
    }

    private fun decryptLocalData(value: String, storageKey: String): String {
        require(value.startsWith(ENCRYPTED_PREFIX)) { "نسخه داده رمزنگاری‌شده معتبر نیست." }
        require(storageKey.length <= 256) { "شناسه فضای ذخیره‌سازی معتبر نیست." }
        val payload = Base64.decode(value.removePrefix(ENCRYPTED_PREFIX), Base64.NO_WRAP)
        require(payload.size > 1 + GCM_IV_BYTES + GCM_TAG_BYTES && payload[0].toInt() == 2) { "ساختار داده رمزنگاری‌شده معتبر نیست." }
        val iv = payload.copyOfRange(1, 1 + GCM_IV_BYTES)
        val encrypted = payload.copyOfRange(1 + GCM_IV_BYTES, payload.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, localEncryptionKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
        cipher.updateAAD(storageKey.toByteArray(Charsets.UTF_8))
        return String(cipher.doFinal(encrypted), Charsets.UTF_8)
    }

    private fun launchBackupPicker(intent: Intent, requestCode: Int) {
        try {
            startActivityForResult(intent, requestCode)
        } catch (error: Exception) {
            val result = pendingBackupResult
            pendingBackupResult = null
            pendingBackupContent = null
            result?.error("backup_picker_unavailable", error.message, null)
        }
    }

    @Deprecated("Deprecated by Android, retained for compatibility with FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_SAVE && requestCode != REQUEST_OPEN) return

        val result = pendingBackupResult
        val content = pendingBackupContent
        pendingBackupResult = null
        pendingBackupContent = null
        if (result == null) return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }

        try {
            when (requestCode) {
                REQUEST_SAVE -> {
                    val backup = content ?: throw IllegalStateException("محتوای پشتیبان موجود نیست.")
                    val output = contentResolver.openOutputStream(uri, "w")
                        ?: throw IllegalStateException("فایل برای نوشتن باز نشد.")
                    output.bufferedWriter(Charsets.UTF_8).use { it.write(backup) }
                    result.success(true)
                }
                REQUEST_OPEN -> {
                    val input = contentResolver.openInputStream(uri)
                        ?: throw IllegalStateException("فایل برای خواندن باز نشد.")
                    val bytes = ByteArrayOutputStream()
                    input.use { stream ->
                        val buffer = ByteArray(8192)
                        var total = 0
                        while (true) {
                            val count = stream.read(buffer)
                            if (count < 0) break
                            total += count
                            if (total > MAX_BACKUP_BYTES) {
                                throw IllegalArgumentException("فایل پشتیبان بیش از حد بزرگ است.")
                            }
                            bytes.write(buffer, 0, count)
                        }
                    }
                    result.success(bytes.toString(Charsets.UTF_8.name()))
                }
            }
        } catch (error: Exception) {
            result.error("backup_io", error.message ?: "عملیات فایل پشتیبان ناموفق بود.", null)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    companion object {
        private const val ENGINE_ID = "moshaver_tahsili_engine"
        private const val BACKUP_CHANNEL = "ir.moshaver.tahsili/backup"
        private const val SECURE_CHANNEL = "ir.moshaver.tahsili/secure_storage"
        private const val LOCAL_DATA_KEY_ALIAS = "simorgh.local.data.aes.v1"
        private const val ENCRYPTED_PREFIX = "enc:v2:"
        private const val MAX_LOCAL_VALUE_BYTES = 4 * 1024 * 1024
        private const val GCM_IV_BYTES = 12
        private const val GCM_TAG_BITS = 128
        private const val GCM_TAG_BYTES = 16
        private const val REQUEST_SAVE = 7401
        private const val REQUEST_OPEN = 7402
        private const val MAX_BACKUP_BYTES = 5 * 1024 * 1024
        private const val DEFAULT_BACKUP_NAME = "simorgh-backup.json"
    }
}
