package ir.moshaver.tahsili

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONException
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.security.GeneralSecurityException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * فعالیت اصلی برنامه‌ی «سیمرغ».
 *
 * کانال‌های method-channel موجود (سازگار با نسخه‌ی قبلی):
 *   - ir.moshaver.tahsili/secure_storage  : encrypt, decrypt
 *   - ir.moshaver.tahsili/share            : shareText
 *   - ir.moshaver.tahsili/backup           : saveBackup, openBackup
 *
 * کانال‌ها/متدهای جدید در این نسخه:
 *   - secure_storage:
 *       • isKeyPresent  → bool   : آیا کلید رمزنگاری محلی ساخته شده؟
 *       • removeKey      → bool   : حذف کلید (برای بازنشانی کامل داده‌ها)
 *       • getKeyInfo     → Map    : اطلاعات فنی کلید (نسخه، الگوریتم، اندازه)
 *   - ir.moshaver.tahsili/system (کانال جدید):
 *       • openAppSettings → bool  : باز کردن تنظیمات برنامه
 *       • copyToClipboard → bool  : کپی متن با برچسب و محدودیت حجم
 *       • getDeviceInfo    → Map   : اطلاعات دستگاه برای عیب‌یابی
 */
class MainActivity : FlutterActivity() {

    // مدیریت وضعیت عملیات SAF — به‌دلیل رقابت بین lifecycle و picker باید synchronized باشد
    private val pendingLock = Any()
    private var pendingBackupResult: MethodChannel.Result? = null
    private var pendingBackupContent: String? = null
    private var pendingBackupAction: Int = ACTION_NONE

    // ----- راه‌اندازی کانال‌ها -----

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerSecureStorageChannel(flutterEngine)
        registerShareChannel(flutterEngine)
        registerBackupChannel(flutterEngine)
        registerSystemChannel(flutterEngine)
    }

    private fun registerSecureStorageChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "encrypt" -> handleEncrypt(call, result)
                        "decrypt" -> handleDecrypt(call, result)
                        "isKeyPresent" -> result.success(isEncryptionKeyPresent())
                        "removeKey" -> handleRemoveKey(result)
                        "getKeyInfo" -> result.success(getKeyInfo())
                        else -> result.notImplemented()
                    }
                } catch (error: Throwable) {
                    result.error(
                        errorCode(error, "secure_storage"),
                        error.message ?: "عملیات رمزنگاری ناموفق بود.",
                        mapOf("type" to error.javaClass.simpleName)
                    )
                }
            }
    }

    private fun registerShareChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareText" -> handleShareText(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun registerBackupChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKUP_CHANNEL)
            .setMethodCallHandler { call, result ->
                synchronized(pendingLock) {
                    if (pendingBackupResult != null) {
                        result.error("backup_busy", "یک عملیات فایل پشتیبان در حال اجراست.", null)
                        return@setMethodCallHandler
                    }
                }
                when (call.method) {
                    "saveBackup" -> handleSaveBackup(call, result)
                    "openBackup" -> handleOpenBackup(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun registerSystemChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "openAppSettings" -> handleOpenAppSettings(result)
                        "copyToClipboard" -> handleCopyToClipboard(call, result)
                        "getDeviceInfo" -> result.success(getDeviceInfo())
                        else -> result.notImplemented()
                    }
                } catch (error: Throwable) {
                    result.error(
                        errorCode(error, "system"),
                        error.message ?: "عملیات سیستمی ناموفق بود.",
                        mapOf("type" to error.javaClass.simpleName)
                    )
                }
            }
    }

    // ----- Secure Storage handlers -----

    private fun handleEncrypt(call: MethodCall, result: MethodChannel.Result) {
        val plaintext = call.argument<String>("plaintext")
            ?: throw IllegalArgumentException("متن ارسال نشده است.")
        val storageKey = call.argument<String>("key")
            ?: throw IllegalArgumentException("کلید داده ارسال نشده است.")
        result.success(encryptLocalData(plaintext, storageKey))
    }

    private fun handleDecrypt(call: MethodCall, result: MethodChannel.Result) {
        val ciphertext = call.argument<String>("ciphertext")
            ?: throw IllegalArgumentException("داده رمزنگاری‌شده ارسال نشده است.")
        val storageKey = call.argument<String>("key")
            ?: throw IllegalArgumentException("کلید داده ارسال نشده است.")
        result.success(decryptLocalData(ciphertext, storageKey))
    }

    private fun handleRemoveKey(result: MethodChannel.Result) {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        if (keyStore.containsAlias(LOCAL_DATA_KEY_ALIAS)) {
            keyStore.deleteEntry(LOCAL_DATA_KEY_ALIAS)
            result.success(true)
        } else {
            result.success(false)
        }
    }

    private fun getKeyInfo(): Map<String, Any> {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        val present = keyStore.containsAlias(LOCAL_DATA_KEY_ALIAS)
        return mapOf(
            "present" to present,
            "alias" to LOCAL_DATA_KEY_ALIAS,
            "version" to ENCRYPTED_V2_VERSION.toInt(),
            "algorithm" to AES_GCM_NO_PADDING,
            "keySize" to AES_KEY_SIZE_BITS,
            "strongBoxAvailable" to isStrongBoxAvailable()
        )
    }

    private fun isEncryptionKeyPresent(): Boolean {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        return keyStore.containsAlias(LOCAL_DATA_KEY_ALIAS)
    }

    // ----- Core crypto -----

    private fun localEncryptionKey(createIfMissing: Boolean = true): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        (keyStore.getKey(LOCAL_DATA_KEY_ALIAS, null) as? SecretKey)?.let { return it }
        if (!createIfMissing) {
            throw IllegalStateException("کلید رمزنگاری محلی موجود نیست؛ داده قبلی بازنویسی نمی‌شود.")
        }
        return generateAesKey()
    }

    /**
     * ساخت کلید AES-256 با GCM. در ابتدا سعی می‌کند از StrongBox (Android 9+) استفاده کند
     * که سخت‌افزار امن اختصاصی دارد؛ اگر در دسترس نباشد، به‌صورت شفاف به کلید TEE-backed بازمی‌گردد.
     */
    private fun generateAesKey(): SecretKey {
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                val strongBoxBuilder = baseKeyBuilder().setIsStrongBoxBacked(true)
                generator.init(strongBoxBuilder.build())
                return generator.generateKey()
            } catch (_: Throwable) {
                // StrongBox روی این دستگاه در دسترس نیست — مسیر جایگزین را امتحان کن
            }
        }

        generator.init(baseKeyBuilder().build())
        return generator.generateKey()
    }

    private fun baseKeyBuilder(): KeyGenParameterSpec.Builder {
        return KeyGenParameterSpec.Builder(
            LOCAL_DATA_KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(AES_KEY_SIZE_BITS)
            .setRandomizedEncryptionRequired(true)
    }

    private fun encryptLocalData(plaintext: String, storageKey: String): String {
        require(plaintext.toByteArray(Charsets.UTF_8).size <= MAX_LOCAL_VALUE_BYTES) {
            "اطلاعات بیش از اندازه مجاز است."
        }
        require(storageKey.length <= MAX_STORAGE_KEY_LENGTH) {
            "شناسه فضای ذخیره‌سازی معتبر نیست."
        }
        val cipher = Cipher.getInstance(AES_GCM_NO_PADDING)
        cipher.init(Cipher.ENCRYPT_MODE, localEncryptionKey())
        cipher.updateAAD(storageKey.toByteArray(Charsets.UTF_8))
        val encrypted = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        return ENCRYPTED_PREFIX +
            Base64.encodeToString(
                byteArrayOf(ENCRYPTED_V2_VERSION) + cipher.iv + encrypted,
                Base64.NO_WRAP
            )
    }

    private fun decryptLocalData(value: String, storageKey: String): String {
        require(value.startsWith(ENCRYPTED_PREFIX)) {
            "نسخه داده رمزنگاری‌شده معتبر نیست."
        }
        require(storageKey.length <= MAX_STORAGE_KEY_LENGTH) {
            "شناسه فضای ذخیره‌سازی معتبر نیست."
        }
        val payload = Base64.decode(value.removePrefix(ENCRYPTED_PREFIX), Base64.NO_WRAP)
        require(payload.size > 1 + GCM_IV_BYTES + GCM_TAG_BYTES) {
            "ساختار داده رمزنگاری‌شده معتبر نیست."
        }
        val version = payload[0].toInt()
        require(version == ENCRYPTED_V2_VERSION.toInt()) {
            "نسخه داده رمزنگاری‌شده پشتیبانی نمی‌شود: $version"
        }
        val iv = payload.copyOfRange(1, 1 + GCM_IV_BYTES)
        val encrypted = payload.copyOfRange(1 + GCM_IV_BYTES, payload.size)
        val cipher = Cipher.getInstance(AES_GCM_NO_PADDING)
        cipher.init(
            Cipher.DECRYPT_MODE,
            localEncryptionKey(createIfMissing = false),
            GCMParameterSpec(GCM_TAG_BITS, iv)
        )
        cipher.updateAAD(storageKey.toByteArray(Charsets.UTF_8))
        return String(cipher.doFinal(encrypted), Charsets.UTF_8)
    }

    // ----- Share -----

    private fun handleShareText(call: MethodCall, result: MethodChannel.Result) {
        val message = call.argument<String>("text")
        val subject = call.argument<String>("subject")
        if (message.isNullOrBlank() || message.length > MAX_SHARE_TEXT_LENGTH) {
            result.error("invalid_share_text", "متن معرفی معتبر نیست.", null)
            return
        }
        try {
            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                if (!subject.isNullOrBlank()) putExtra(Intent.EXTRA_SUBJECT, subject)
                putExtra(Intent.EXTRA_TEXT, message)
            }
            startActivity(Intent.createChooser(sendIntent, "معرفی سیمرغ به دوستان"))
            result.success(true)
        } catch (error: Throwable) {
            result.error("share_unavailable", error.message ?: "اشتراک‌گذاری در دسترس نیست.", null)
        }
    }

    // ----- Backup -----

    private fun handleSaveBackup(call: MethodCall, result: MethodChannel.Result) {
        val content = call.argument<String>("content")
        val fileName = call.argument<String>("fileName") ?: DEFAULT_BACKUP_NAME
        if (content == null) {
            result.error("invalid_backup", "محتوای پشتیبان خالی است.", null)
            return
        }
        val bytes = content.toByteArray(Charsets.UTF_8)
        if (bytes.size > MAX_BACKUP_BYTES) {
            result.error("invalid_backup", "حجم پشتیبان بیش از حد مجاز است.", null)
            return
        }
        // اعتبارسنجی ساختار JSON پیش از باز کردن picker تا خطا زودتر گزارش شود
        try {
            JSONObject(content)
        } catch (_: JSONException) {
            result.error("invalid_backup", "ساختار JSON پشتیبان معتبر نیست.", null)
            return
        }
        synchronized(pendingLock) {
            pendingBackupResult = result
            pendingBackupContent = content
            pendingBackupAction = ACTION_SAVE
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        launchBackupPicker(intent, REQUEST_SAVE)
    }

    private fun handleOpenBackup(result: MethodChannel.Result) {
        synchronized(pendingLock) {
            pendingBackupResult = result
            pendingBackupContent = null
            pendingBackupAction = ACTION_OPEN
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
        }
        launchBackupPicker(intent, REQUEST_OPEN)
    }

    private fun launchBackupPicker(intent: Intent, requestCode: Int) {
        try {
            startActivityForResult(intent, requestCode)
        } catch (error: Throwable) {
            val pending = synchronized(pendingLock) { pendingBackupResult }
            clearPendingBackup()
            pending?.error("backup_picker_unavailable", error.message, null)
        }
    }

    @Deprecated("Deprecated by Android, retained for compatibility with FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_SAVE && requestCode != REQUEST_OPEN) return

        val result: MethodChannel.Result?
        val content: String?
        val action: Int
        // synchronized یک تابع inline است؛ اجازه می‌دهد val یک‌بار داخل lambda مقدار بگیرد
        synchronized(pendingLock) {
            result = pendingBackupResult
            content = pendingBackupContent
            action = pendingBackupAction
        }
        clearPendingBackup()

        if (result == null) return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }

        try {
            when (requestCode) {
                REQUEST_SAVE -> {
                    if (action != ACTION_SAVE) {
                        result.error("backup_state", "وضعیت عملیات پشتیبان ناسازگار است.", null)
                        return
                    }
                    val backup = content
                        ?: throw IllegalStateException("محتوای پشتیبان موجود نیست.")
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
                        val buffer = ByteArray(READ_BUFFER_SIZE)
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
                    val text = bytes.toString(Charsets.UTF_8.name())
                    // اعتبارسنجی ساختار JSON پیش از ارسال به Dart
                    try {
                        JSONObject(text)
                    } catch (_: JSONException) {
                        result.error("invalid_backup", "ساختار فایل پشتیبان معتبر نیست.", null)
                        return
                    }
                    result.success(text)
                }
            }
        } catch (error: Throwable) {
            result.error("backup_io", error.message ?: "عملیات فایل پشتیبان ناموفق بود.", null)
        }
    }

    private fun clearPendingBackup() {
        synchronized(pendingLock) {
            pendingBackupResult = null
            pendingBackupContent = null
            pendingBackupAction = ACTION_NONE
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        // جلوگیری از نشت callback اگه Activity طی SAF picker نابود شود
        clearPendingBackup()
    }

    // ----- System handlers -----

    private fun handleOpenAppSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (error: Throwable) {
            result.error("settings_unavailable", error.message ?: "باز کردن تنظیمات ناموفق بود.", null)
        }
    }

    private fun handleCopyToClipboard(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text")
        val label = call.argument<String>("label") ?: DEFAULT_CLIP_LABEL
        if (text.isNullOrBlank() || text.length > MAX_CLIPBOARD_TEXT_LENGTH) {
            result.error("invalid_clipboard_text", "متن Clipboard معتبر نیست.", null)
            return
        }
        try {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                ?: throw IllegalStateException("سرویس Clipboard در دسترس نیست.")
            clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
            result.success(true)
        } catch (error: Throwable) {
            result.error("clipboard_unavailable", error.message ?: "Clipboard در دسترس نیست.", null)
        }
    }

    private fun getDeviceInfo(): Map<String, Any> {
        return mapOf(
            "manufacturer" to (Build.MANUFACTURER ?: "unknown"),
            "model" to (Build.MODEL ?: "unknown"),
            "sdkInt" to Build.VERSION.SDK_INT,
            "release" to (Build.VERSION.RELEASE ?: ""),
            "strongBoxCapable" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
        )
    }

    // ----- Helpers -----

    private fun isStrongBoxAvailable(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        return try {
            packageManager.hasSystemFeature("android.software.strongbox_keystore")
        } catch (_: Throwable) {
            false
        }
    }

    private fun errorCode(error: Throwable, channel: String): String = when (error) {
        is IllegalArgumentException -> "${channel}_invalid_argument"
        is IllegalStateException -> "${channel}_invalid_state"
        is GeneralSecurityException -> "${channel}_crypto"
        is IOException -> "${channel}_io"
        is JSONException -> "${channel}_json"
        else -> channel
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    companion object {
        // کانال‌ها
        private const val SECURE_CHANNEL = "ir.moshaver.tahsili/secure_storage"
        private const val SHARE_CHANNEL = "ir.moshaver.tahsili/share"
        private const val BACKUP_CHANNEL = "ir.moshaver.tahsili/backup"
        private const val SYSTEM_CHANNEL = "ir.moshaver.tahsili/system"

        // Keystore
        private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
        private const val LOCAL_DATA_KEY_ALIAS = "simorgh.local.data.aes.v1"

        // رمزنگاری
        private const val AES_GCM_NO_PADDING = "AES/GCM/NoPadding"
        private const val AES_KEY_SIZE_BITS = 256
        private const val ENCRYPTED_PREFIX = "enc:v2:"
        private const val ENCRYPTED_V2_VERSION: Byte = 2
        private const val MAX_LOCAL_VALUE_BYTES = 4 * 1024 * 1024
        private const val MAX_STORAGE_KEY_LENGTH = 256
        private const val GCM_IV_BYTES = 12
        private const val GCM_TAG_BITS = 128
        private const val GCM_TAG_BYTES = 16

        // SAF / پشتیبان
        private const val REQUEST_SAVE = 7401
        private const val REQUEST_OPEN = 7402
        private const val ACTION_NONE = 0
        private const val ACTION_SAVE = 1
        private const val ACTION_OPEN = 2
        private const val MAX_BACKUP_BYTES = 5 * 1024 * 1024
        private const val READ_BUFFER_SIZE = 8192
        private const val DEFAULT_BACKUP_NAME = "simorgh-backup.json"

        // Share / Clipboard
        private const val MAX_SHARE_TEXT_LENGTH = 4000
        private const val MAX_CLIPBOARD_TEXT_LENGTH = 16 * 1024
        private const val DEFAULT_CLIP_LABEL = "simorgh_clip"
    }
}
