package ir.moshaver.tahsili

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONException
import org.json.JSONObject
import org.json.JSONTokener
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.GeneralSecurityException
import java.security.KeyStore
import java.security.ProviderException
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * فعالیت اصلی برنامه سیمرغ.
 *
 * کانال‌های سازگار با نسخه قبلی:
 *
 * ir.moshaver.tahsili/secure_storage
 *   encrypt, decrypt, isKeyPresent, removeKey, getKeyInfo
 *
 * ir.moshaver.tahsili/share
 *   shareText
 *
 * ir.moshaver.tahsili/backup
 *   saveBackup, openBackup
 *
 * ir.moshaver.tahsili/system
 *   openAppSettings, copyToClipboard, getDeviceInfo
 *
 * نکات:
 * - کارهای سنگین روی executor تک‌نخی اجرا می‌شوند.
 * - وضعیت کانال‌ها و picker فقط روی thread اصلی مدیریت می‌شود.
 * - هر درخواست حداکثر یک پاسخ دریافت می‌کند.
 * - هنگام نابودی Activity یا جداشدن engine، درخواست‌های معلق لغو می‌شوند.
 * - کلید Android Keystore قابل انتقال به دستگاه دیگر نیست.
 * - این کلاس محتوای JSON پشتیبان را رمزنگاری نمی‌کند.
 */
class MainActivity : FlutterActivity() {

    private val mainHandler = Handler(Looper.getMainLooper())

    private val worker = Executors.newSingleThreadExecutor { task ->
        Thread(task, "simorgh-native-worker")
    }

    private val channels = mutableListOf<MethodChannel>()
    private val activeReplies = mutableSetOf<SafeResult>()

    // این وضعیت فقط روی thread اصلی خوانده/نوشته می‌شود.
    private var pendingBackup: PendingBackup? = null

    private var destroyed = false
    private var engineAttached = false

    private enum class BackupAction {
        SAVE,
        OPEN
    }

    private enum class BackupStage {
        PREPARING,
        PICKING,
        IO
    }

    private class PendingBackup(
        val reply: SafeResult,
        val action: BackupAction,
        val content: String? = null,
        var stage: BackupStage = BackupStage.PREPARING
    )

    /**
     * تکمیل درخواست‌ها فقط روی thread اصلی انجام می‌شود.
     * پاسخ‌های worker پس از لغو lifecycle نادیده گرفته می‌شوند.
     */
    private inner class SafeResult(
        private val delegate: MethodChannel.Result
    ) {
        private var completed = false

        fun success(value: Any?) {
            complete { delegate.success(value) }
        }

        fun error(
            code: String,
            message: String,
            details: Any? = null
        ) {
            complete { delegate.error(code, message, details) }
        }

        fun notImplemented() {
            complete { delegate.notImplemented() }
        }

        private fun complete(deliver: () -> Unit) {
            onMain {
                if (!completed) {
                    completed = true
                    activeReplies.remove(this)
                    deliver()
                }
            }
        }
    }

    // ----- Flutter lifecycle -----

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // محافظت در برابر ثبت دوباره روی همان Activity.
        unregisterChannels()
        cancelOutstandingRequests()

        engineAttached = true

        registerChannel(flutterEngine, SECURE_CHANNEL) { call, reply ->
            handleSecureStorage(call, reply)
        }

        registerChannel(flutterEngine, SHARE_CHANNEL) { call, reply ->
            when (call.method) {
                "shareText" -> handleShareText(call, reply)
                else -> reply.notImplemented()
            }
        }

        registerChannel(flutterEngine, BACKUP_CHANNEL) { call, reply ->
            when (call.method) {
                "saveBackup" -> handleSaveBackup(call, reply)
                "openBackup" -> handleOpenBackup(reply)
                else -> reply.notImplemented()
            }
        }

        registerChannel(flutterEngine, SYSTEM_CHANNEL) { call, reply ->
            when (call.method) {
                "openAppSettings" -> handleOpenAppSettings(reply)
                "copyToClipboard" -> handleCopyToClipboard(call, reply)
                "getDeviceInfo" -> reply.success(getDeviceInfo())
                else -> reply.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        cancelOutstandingRequests()
        engineAttached = false
        unregisterChannels()

        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        destroyed = true

        cancelOutstandingRequests()
        engineAttached = false
        unregisterChannels()

        // Providerهای فایل لزوماً interruption را رعایت نمی‌کنند.
        // عملیات آغازشده ممکن است در سطح provider همچنان تمام شود.
        worker.shutdownNow()

        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    private fun registerChannel(
        engine: FlutterEngine,
        name: String,
        handler: (MethodCall, SafeResult) -> Unit
    ) {
        val channel = MethodChannel(
            engine.dartExecutor.binaryMessenger,
            name
        )

        channels.add(channel)

        channel.setMethodCallHandler { call, result ->
            val reply = SafeResult(result)

            onMain {
                activeReplies.add(reply)

                if (destroyed || !engineAttached) {
                    reply.error(
                        "activity_unavailable",
                        "صفحه برنامه در دسترس نیست."
                    )
                } else {
                    try {
                        handler(call, reply)
                    } catch (error: Exception) {
                        reportError(reply, error, channelErrorPrefix(name))
                    }
                }
            }
        }
    }

    private fun unregisterChannels() {
        channels.forEach { it.setMethodCallHandler(null) }
        channels.clear()
    }

    private fun cancelOutstandingRequests() {
        pendingBackup = null

        activeReplies.toList().forEach { reply ->
            reply.error(
                "operation_cancelled",
                "عملیات به دلیل بسته‌شدن یا بازسازی صفحه لغو شد."
            )
        }
    }

    private fun onMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post { block() }
        }
    }

    private fun submitTask(
        reply: SafeResult,
        prefix: String,
        task: () -> Any?
    ) {
        try {
            worker.execute {
                try {
                    reply.success(task())
                } catch (error: Exception) {
                    reportError(reply, error, prefix)
                }
            }
        } catch (_: RejectedExecutionException) {
            reply.error(
                "activity_unavailable",
                "امکان اجرای عملیات وجود ندارد."
            )
        }
    }

    // ----- Secure storage -----

    private fun handleSecureStorage(
        call: MethodCall,
        reply: SafeResult
    ) {
        when (call.method) {
            "encrypt" -> {
                val plaintext = requiredString(call, "plaintext")
                val storageKey = requiredString(call, "key")

                validateStorageKey(storageKey)

                require(plaintext.length <= MAX_LOCAL_VALUE_BYTES) {
                    "اطلاعات بیش از اندازه مجاز است."
                }

                submitTask(reply, "secure_storage") {
                    synchronized(CRYPTO_LOCK) {
                        encryptLocalData(plaintext, storageKey)
                    }
                }
            }

            "decrypt" -> {
                val ciphertext = requiredString(call, "ciphertext")
                val storageKey = requiredString(call, "key")

                validateStorageKey(storageKey)

                require(
                    ciphertext.length <=
                        ENCRYPTED_PREFIX.length + MAX_ENCRYPTED_BASE64_LENGTH
                ) {
                    "داده رمزنگاری‌شده بیش از اندازه مجاز است."
                }

                submitTask(reply, "secure_storage") {
                    synchronized(CRYPTO_LOCK) {
                        decryptLocalData(ciphertext, storageKey)
                    }
                }
            }

            "isKeyPresent" -> {
                submitTask(reply, "secure_storage") {
                    synchronized(CRYPTO_LOCK) {
                        openKeyStore().containsAlias(LOCAL_DATA_KEY_ALIAS)
                    }
                }
            }

            "removeKey" -> {
                submitTask(reply, "secure_storage") {
                    synchronized(CRYPTO_LOCK) {
                        val keyStore = openKeyStore()
                        val present =
                            keyStore.containsAlias(LOCAL_DATA_KEY_ALIAS)

                        if (present) {
                            keyStore.deleteEntry(LOCAL_DATA_KEY_ALIAS)
                        }

                        present
                    }
                }
            }

            "getKeyInfo" -> {
                submitTask(reply, "secure_storage") {
                    synchronized(CRYPTO_LOCK) {
                        getKeyInfo()
                    }
                }
            }

            else -> reply.notImplemented()
        }
    }

    private fun openKeyStore(): KeyStore {
        return KeyStore.getInstance(KEYSTORE_PROVIDER).apply {
            load(null)
        }
    }

    private fun localEncryptionKey(
        createIfMissing: Boolean
    ): SecretKey {
        val keyStore = openKeyStore()

        if (keyStore.containsAlias(LOCAL_DATA_KEY_ALIAS)) {
            return keyStore.getKey(LOCAL_DATA_KEY_ALIAS, null) as? SecretKey
                ?: throw IllegalStateException(
                    "کلید موجود از نوع مورد انتظار نیست."
                )
        }

        if (!createIfMissing) {
            throw IllegalStateException(
                "کلید رمزنگاری محلی موجود نیست."
            )
        }

        return generateAesKey()
    }

    /**
     * ابتدا StrongBox، در صورت وجود feature مربوط، امتحان می‌شود.
     * fallback به Android Keystore معمولی است؛ سخت‌افزاری‌بودن آن
     * بدون بررسی KeyInfo تضمین نمی‌شود.
     */
    private fun generateAesKey(): SecretKey {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            isStrongBoxAvailable()
        ) {
            try {
                val generator = KeyGenerator.getInstance(
                    KeyProperties.KEY_ALGORITHM_AES,
                    KEYSTORE_PROVIDER
                )

                generator.init(
                    baseKeyBuilder()
                        .setIsStrongBoxBacked(true)
                        .build()
                )

                return generator.generateKey()
            } catch (_: StrongBoxUnavailableException) {
                // ادامه با Android Keystore معمولی.
            } catch (_: GeneralSecurityException) {
                // پارامترها یا provider StrongBox پشتیبانی نشده‌اند.
            } catch (_: ProviderException) {
                // شکست provider؛ مسیر معمولی امتحان می‌شود.
            }
        }

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            KEYSTORE_PROVIDER
        )

        generator.init(baseKeyBuilder().build())
        return generator.generateKey()
    }

    private fun baseKeyBuilder(): KeyGenParameterSpec.Builder {
        return KeyGenParameterSpec.Builder(
            LOCAL_DATA_KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or
                KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(
                KeyProperties.ENCRYPTION_PADDING_NONE
            )
            .setKeySize(AES_KEY_SIZE_BITS)
            .setRandomizedEncryptionRequired(true)
    }

    private fun encryptLocalData(
        plaintext: String,
        storageKey: String
    ): String {
        validateStorageKey(storageKey)

        // یک بار تبدیل، برای جلوگیری از تخصیص تکراری.
        val plaintextBytes = plaintext.toByteArray(Charsets.UTF_8)

        require(plaintextBytes.size <= MAX_LOCAL_VALUE_BYTES) {
            "اطلاعات بیش از اندازه مجاز است."
        }

        val cipher = Cipher.getInstance(AES_GCM_NO_PADDING)

        cipher.init(
            Cipher.ENCRYPT_MODE,
            localEncryptionKey(createIfMissing = true)
        )

        cipher.updateAAD(storageKey.toByteArray(Charsets.UTF_8))

        val encrypted = cipher.doFinal(plaintextBytes)
        val iv = cipher.iv

        check(iv.size == GCM_IV_BYTES) {
            "اندازه بردار اولیه رمزنگاری معتبر نیست."
        }

        val payload = byteArrayOf(ENCRYPTED_V2_VERSION) + iv + encrypted

        return ENCRYPTED_PREFIX +
            Base64.encodeToString(payload, Base64.NO_WRAP)
    }

    private fun decryptLocalData(
        value: String,
        storageKey: String
    ): String {
        validateStorageKey(storageKey)

        require(value.startsWith(ENCRYPTED_PREFIX)) {
            "نسخه داده رمزنگاری‌شده معتبر نیست."
        }

        require(
            value.length <=
                ENCRYPTED_PREFIX.length + MAX_ENCRYPTED_BASE64_LENGTH
        ) {
            "داده رمزنگاری‌شده بیش از اندازه مجاز است."
        }

        val encoded = value.substring(ENCRYPTED_PREFIX.length)

        require(encoded.isNotEmpty()) {
            "داده رمزنگاری‌شده خالی است."
        }

        val payload = Base64.decode(encoded, Base64.NO_WRAP)

        require(
            payload.size in MIN_ENCRYPTED_PAYLOAD_BYTES..
                MAX_ENCRYPTED_PAYLOAD_BYTES
        ) {
            "ساختار یا حجم داده رمزنگاری‌شده معتبر نیست."
        }

        val version = payload[0].toInt() and 0xFF

        require(version == ENCRYPTED_V2_VERSION.toInt()) {
            "نسخه داده رمزنگاری‌شده پشتیبانی نمی‌شود."
        }

        val iv = payload.copyOfRange(1, 1 + GCM_IV_BYTES)
        val encrypted = payload.copyOfRange(
            1 + GCM_IV_BYTES,
            payload.size
        )

        val cipher = Cipher.getInstance(AES_GCM_NO_PADDING)

        cipher.init(
            Cipher.DECRYPT_MODE,
            localEncryptionKey(createIfMissing = false),
            GCMParameterSpec(GCM_TAG_BITS, iv)
        )

        cipher.updateAAD(storageKey.toByteArray(Charsets.UTF_8))

        val plaintext = cipher.doFinal(encrypted)

        require(plaintext.size <= MAX_LOCAL_VALUE_BYTES) {
            "اطلاعات بیش از اندازه مجاز است."
        }

        return decodeUtf8Strict(plaintext)
    }

    private fun validateStorageKey(storageKey: String) {
        // برای سازگاری، رفتار قبلی درباره کلید خالی حفظ شده است.
        require(storageKey.length <= MAX_STORAGE_KEY_LENGTH) {
            "شناسه فضای ذخیره‌سازی معتبر نیست."
        }
    }

    private fun getKeyInfo(): Map<String, Any> {
        return mapOf(
            "present" to
                openKeyStore().containsAlias(LOCAL_DATA_KEY_ALIAS),
            "alias" to LOCAL_DATA_KEY_ALIAS,
            "version" to ENCRYPTED_V2_VERSION.toInt(),
            "algorithm" to AES_GCM_NO_PADDING,
            "keySize" to AES_KEY_SIZE_BITS,

            // قابلیت دستگاه است، نه تأیید backing کلید فعلی.
            "strongBoxAvailable" to isStrongBoxAvailable()
        )
    }

    // ----- Share -----

    private fun handleShareText(
        call: MethodCall,
        reply: SafeResult
    ) {
        val text = optionalString(call, "text")
        val subject = optionalString(call, "subject")

        if (
            text.isNullOrBlank() ||
            text.length > MAX_SHARE_TEXT_LENGTH ||
            (subject != null && subject.length > MAX_SUBJECT_LENGTH)
        ) {
            reply.error(
                "invalid_share_text",
                "متن یا عنوان اشتراک‌گذاری معتبر نیست."
            )
            return
        }

        try {
            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)

                if (!subject.isNullOrBlank()) {
                    putExtra(Intent.EXTRA_SUBJECT, subject)
                }
            }

            startActivity(
                Intent.createChooser(
                    sendIntent,
                    "معرفی سیمرغ به دوستان"
                )
            )

            // موفقیت یعنی chooser باز شده، نه اینکه اشتراک انجام شده باشد.
            reply.success(true)
        } catch (_: Exception) {
            reply.error(
                "share_unavailable",
                "اشتراک‌گذاری در دسترس نیست."
            )
        }
    }

    // ----- Backup -----

    private fun reserveBackup(pending: PendingBackup): Boolean {
        if (pendingBackup != null) {
            pending.reply.error(
                "backup_busy",
                "یک عملیات فایل پشتیبان در حال اجراست."
            )
            return false
        }

        pendingBackup = pending
        return true
    }

    private fun handleSaveBackup(
        call: MethodCall,
        reply: SafeResult
    ) {
        val content = optionalString(call, "content")

        if (content == null || content.length > MAX_BACKUP_BYTES) {
            reply.error(
                "invalid_backup",
                "محتوا یا حجم پشتیبان معتبر نیست."
            )
            return
        }

        val fileName = validateBackupFileName(
            optionalString(call, "fileName") ?: DEFAULT_BACKUP_NAME
        )

        val pending = PendingBackup(
            reply = reply,
            action = BackupAction.SAVE,
            content = content
        )

        if (!reserveBackup(pending)) return

        try {
            worker.execute {
                try {
                    require(
                        content.toByteArray(Charsets.UTF_8).size <=
                            MAX_BACKUP_BYTES
                    ) {
                        "حجم پشتیبان بیش از اندازه مجاز است."
                    }

                    validateJsonObject(content)

                    onMain {
                        if (
                            pendingBackup === pending &&
                            !destroyed &&
                            engineAttached
                        ) {
                            val intent = Intent(
                                Intent.ACTION_CREATE_DOCUMENT
                            ).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "application/json"
                                putExtra(Intent.EXTRA_TITLE, fileName)
                            }

                            launchBackupPicker(
                                pending,
                                intent,
                                REQUEST_SAVE
                            )
                        }
                    }
                } catch (_: Exception) {
                    failBackup(
                        pending,
                        "invalid_backup",
                        "ساختار یا حجم پشتیبان معتبر نیست."
                    )
                }
            }
        } catch (_: RejectedExecutionException) {
            failBackup(
                pending,
                "activity_unavailable",
                "امکان اجرای عملیات وجود ندارد."
            )
        }
    }

    private fun handleOpenBackup(reply: SafeResult) {
        val pending = PendingBackup(
            reply = reply,
            action = BackupAction.OPEN
        )

        if (!reserveBackup(pending)) return

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
        }

        launchBackupPicker(pending, intent, REQUEST_OPEN)
    }

    @Suppress("DEPRECATION")
    private fun launchBackupPicker(
        pending: PendingBackup,
        intent: Intent,
        requestCode: Int
    ) {
        if (pendingBackup !== pending) return

        pending.stage = BackupStage.PICKING

        try {
            startActivityForResult(intent, requestCode)
        } catch (_: Exception) {
            failBackup(
                pending,
                "backup_picker_unavailable",
                "انتخاب‌گر فایل در دسترس نیست."
            )
        }
    }

    @Deprecated(
        "Retained for compatibility with FlutterActivity"
    )
    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {
        super.onActivityResult(requestCode, resultCode, data)

        if (
            requestCode != REQUEST_SAVE &&
            requestCode != REQUEST_OPEN
        ) {
            return
        }

        val pending = pendingBackup ?: return

        // callback تکراری در زمان I/O نباید دوباره پردازش شود.
        if (pending.stage != BackupStage.PICKING) return

        val expectedRequest = when (pending.action) {
            BackupAction.SAVE -> REQUEST_SAVE
            BackupAction.OPEN -> REQUEST_OPEN
        }

        // نتیجه نامرتبط را به درخواست جاری نسبت نمی‌دهیم.
        if (requestCode != expectedRequest) return

        if (resultCode != Activity.RESULT_OK) {
            completeBackup(pending, null)
            return
        }

        val uri = data?.data

        if (uri == null) {
            failBackup(
                pending,
                "backup_invalid_uri",
                "مسیر فایل انتخاب‌شده معتبر نیست."
            )
            return
        }

        pending.stage = BackupStage.IO

        try {
            worker.execute {
                try {
                    val response: Any = when (pending.action) {
                        BackupAction.SAVE -> {
                            val content = pending.content
                                ?: throw IllegalStateException(
                                    "محتوای پشتیبان موجود نیست."
                                )

                            writeBackup(uri, content)
                            true
                        }

                        BackupAction.OPEN -> readBackup(uri)
                    }

                    completeBackup(pending, response)
                } catch (error: Exception) {
                    val code = when (error) {
                        is IllegalArgumentException,
                        is JSONException -> "invalid_backup"

                        is SecurityException -> "backup_permission"

                        else -> "backup_io"
                    }

                    val message = when (code) {
                        "invalid_backup" ->
                            "ساختار، کدگذاری یا حجم پشتیبان معتبر نیست."

                        "backup_permission" ->
                            "اجازه دسترسی به فایل پشتیبان وجود ندارد."

                        else ->
                            "خواندن یا نوشتن فایل پشتیبان ناموفق بود."
                    }

                    failBackup(pending, code, message)
                }
            }
        } catch (_: RejectedExecutionException) {
            failBackup(
                pending,
                "activity_unavailable",
                "امکان اجرای عملیات وجود ندارد."
            )
        }
    }

    private fun writeBackup(uri: Uri, content: String) {
        val bytes = content.toByteArray(Charsets.UTF_8)

        require(bytes.size <= MAX_BACKUP_BYTES) {
            "حجم پشتیبان بیش از اندازه مجاز است."
        }

        // wt درخواست نوشتن همراه با truncate است.
        // رفتار نهایی وابسته به document provider است.
        val output = contentResolver.openOutputStream(uri, "wt")
            ?: throw IOException("فایل برای نوشتن باز نشد.")

        output.use { stream ->
            stream.write(bytes)
            stream.flush()
        }
    }

    private fun readBackup(uri: Uri): String {
        val input = contentResolver.openInputStream(uri)
            ?: throw IOException("فایل برای خواندن باز نشد.")

        val output = ByteArrayOutputStream()

        input.use { stream ->
            val buffer = ByteArray(READ_BUFFER_SIZE)
            var total = 0

            while (true) {
                if (Thread.currentThread().isInterrupted) {
                    throw IOException("عملیات لغو شده است.")
                }

                val count = stream.read(buffer)

                if (count < 0) break
                if (count == 0) continue

                require(count <= MAX_BACKUP_BYTES - total) {
                    "فایل پشتیبان بیش از اندازه مجاز است."
                }

                output.write(buffer, 0, count)
                total += count
            }
        }

        val text = decodeUtf8Strict(output.toByteArray())
            .removePrefix("\uFEFF")

        validateJsonObject(text)

        return text
    }

    private fun validateJsonObject(text: String) {
        val tokener = JSONTokener(text)
        val value = tokener.nextValue()

        require(value is JSONObject) {
            "ریشه پشتیبان باید یک شیء JSON باشد."
        }

        // متن اضافه پس از پایان شیء پذیرفته نمی‌شود.
        require(tokener.nextClean() == '\u0000') {
            "داده اضافه پس از JSON وجود دارد."
        }

        // اعتبارسنجی schema و نسخه پشتیبان باید در لایه Dart انجام شود.
        // JSONTokener اندروید parser کاملاً strict مطابق RFC نیست.
    }

    private fun validateBackupFileName(value: String): String {
        require(
            value.isNotBlank() &&
                value.length <= MAX_BACKUP_FILENAME_LENGTH &&
                value != "." &&
                value != ".." &&
                value.none {
                    it == '/' ||
                        it == '\\' ||
                        it.code < 0x20 ||
                        it.code == 0x7F
                }
        ) {
            "نام فایل پشتیبان معتبر نیست."
        }

        return value
    }

    private fun completeBackup(
        pending: PendingBackup,
        value: Any?
    ) {
        onMain {
            if (pendingBackup === pending) {
                pendingBackup = null
                pending.reply.success(value)
            }
        }
    }

    private fun failBackup(
        pending: PendingBackup,
        code: String,
        message: String
    ) {
        onMain {
            if (pendingBackup === pending) {
                pendingBackup = null
                pending.reply.error(code, message)
            }
        }
    }

    // ----- System -----

    private fun handleOpenAppSettings(reply: SafeResult) {
        try {
            val intent = Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS
            ).apply {
                data = Uri.fromParts("package", packageName, null)
            }

            startActivity(intent)
            reply.success(true)
        } catch (_: Exception) {
            reply.error(
                "settings_unavailable",
                "باز کردن تنظیمات برنامه ناموفق بود."
            )
        }
    }

    private fun handleCopyToClipboard(
        call: MethodCall,
        reply: SafeResult
    ) {
        val text = optionalString(call, "text")
        val label =
            optionalString(call, "label") ?: DEFAULT_CLIP_LABEL
        val sensitive = optionalBoolean(call, "sensitive") ?: false

        if (
            text.isNullOrBlank() ||
            text.length > MAX_CLIPBOARD_TEXT_LENGTH ||
            label.length > MAX_CLIPBOARD_LABEL_LENGTH
        ) {
            reply.error(
                "invalid_clipboard_text",
                "متن یا برچسب Clipboard معتبر نیست."
            )
            return
        }

        try {
            val clipboard =
                getSystemService(Context.CLIPBOARD_SERVICE)
                    as? ClipboardManager
                    ?: throw IllegalStateException(
                        "سرویس Clipboard موجود نیست."
                    )

            val clip = ClipData.newPlainText(label, text)

            if (
                sensitive &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
            ) {
                // رشته رسمی اجازه می‌دهد compileSdk 33 الزامی نباشد.
                // Android 13+ از آن برای مخفی‌کردن preview استفاده می‌کند.
                clip.description.extras =
                    android.os.PersistableBundle().apply {
                        putBoolean(
                            "android.content.extra.IS_SENSITIVE",
                            true
                        )
                    }
            }

            clipboard.setPrimaryClip(clip)
            reply.success(true)
        } catch (_: Exception) {
            reply.error(
                "clipboard_unavailable",
                "Clipboard در دسترس نیست."
            )
        }
    }

    private fun getDeviceInfo(): Map<String, Any> {
        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "sdkInt" to Build.VERSION.SDK_INT,
            "release" to Build.VERSION.RELEASE,
            "strongBoxCapable" to isStrongBoxAvailable()
        )
    }

    private fun isStrongBoxAvailable(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            packageManager.hasSystemFeature(
                PackageManager.FEATURE_STRONGBOX_KEYSTORE
            )
    }

    // ----- Validation and errors -----

    private fun requiredString(
        call: MethodCall,
        name: String
    ): String {
        return optionalString(call, name)
            ?: throw IllegalArgumentException(
                "پارامتر ضروری ارسال نشده است."
            )
    }

    private fun optionalString(
        call: MethodCall,
        name: String
    ): String? {
        val value = call.argument<Any>(name) ?: return null

        require(value is String) {
            "نوع پارامتر معتبر نیست."
        }

        return value
    }

    private fun optionalBoolean(
        call: MethodCall,
        name: String
    ): Boolean? {
        val value = call.argument<Any>(name) ?: return null

        require(value is Boolean) {
            "نوع پارامتر معتبر نیست."
        }

        return value
    }

    private fun decodeUtf8Strict(bytes: ByteArray): String {
        return try {
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes))
                .toString()
        } catch (_: java.nio.charset.CharacterCodingException) {
            throw IllegalArgumentException(
                "کدگذاری UTF-8 معتبر نیست."
            )
        }
    }

    private fun channelErrorPrefix(channel: String): String {
        return when (channel) {
            SECURE_CHANNEL -> "secure_storage"
            SHARE_CHANNEL -> "share"
            BACKUP_CHANNEL -> "backup"
            SYSTEM_CHANNEL -> "system"
            else -> "native"
        }
    }

    private fun reportError(
        reply: SafeResult,
        error: Exception,
        prefix: String
    ) {
        val suffix = when (error) {
            is AEADBadTagException -> "authentication_failed"
            is IllegalArgumentException -> "invalid_argument"
            is IllegalStateException -> "invalid_state"
            is SecurityException -> "permission"
            is GeneralSecurityException -> "crypto"
            is IOException -> "io"
            is JSONException -> "json"
            else -> "failed"
        }

        val message = when {
            error is AEADBadTagException ->
                "اصالت داده تأیید نشد؛ کلید، شناسه داده یا محتوا ناسازگار است."

            prefix == "secure_storage" &&
                error is IllegalStateException ->
                "کلید یا وضعیت رمزنگاری محلی در دسترس نیست."

            error is IllegalArgumentException ->
                "پارامتر، ساختار داده یا حجم ورودی معتبر نیست."

            error is SecurityException ->
                "اجازه اجرای عملیات وجود ندارد."

            prefix == "secure_storage" ->
                "عملیات رمزنگاری ناموفق بود."

            prefix == "backup" ->
                "عملیات فایل پشتیبان ناموفق بود."

            else ->
                "عملیات درخواستی ناموفق بود."
        }

        // پیام خام exception، مسیر فایل و محتوای ورودی منتشر نمی‌شوند.
        reply.error(
            "${prefix}_$suffix",
            message,
            mapOf("type" to error.javaClass.simpleName)
        )
    }

    companion object {
        // کانال‌ها
        private const val SECURE_CHANNEL =
            "ir.moshaver.tahsili/secure_storage"

        private const val SHARE_CHANNEL =
            "ir.moshaver.tahsili/share"

        private const val BACKUP_CHANNEL =
            "ir.moshaver.tahsili/backup"

        private const val SYSTEM_CHANNEL =
            "ir.moshaver.tahsili/system"

        // قفل مشترک میان نمونه‌های Activity در همین process.
        private val CRYPTO_LOCK = Any()

        // Keystore
        private const val KEYSTORE_PROVIDER = "AndroidKeyStore"

        // برای سازگاری با داده‌های قبلی، alias را تغییر ندهید.
        private const val LOCAL_DATA_KEY_ALIAS =
            "simorgh.local.data.aes.v1"

        // Crypto
        private const val AES_GCM_NO_PADDING = "AES/GCM/NoPadding"
        private const val AES_KEY_SIZE_BITS = 256

        private const val ENCRYPTED_PREFIX = "enc:v2:"
        private const val ENCRYPTED_V2_VERSION: Byte = 2

        private const val MAX_LOCAL_VALUE_BYTES = 4 * 1024 * 1024
        private const val MAX_STORAGE_KEY_LENGTH = 256

        private const val GCM_IV_BYTES = 12
        private const val GCM_TAG_BITS = 128
        private const val GCM_TAG_BYTES = 16

        private const val MIN_ENCRYPTED_PAYLOAD_BYTES =
            1 + GCM_IV_BYTES + GCM_TAG_BYTES

        private const val MAX_ENCRYPTED_PAYLOAD_BYTES =
            MIN_ENCRYPTED_PAYLOAD_BYTES + MAX_LOCAL_VALUE_BYTES

        private const val MAX_ENCRYPTED_BASE64_LENGTH =
            4 * ((MAX_ENCRYPTED_PAYLOAD_BYTES + 2) / 3)

        // SAF / Backup
        private const val REQUEST_SAVE = 7401
        private const val REQUEST_OPEN = 7402

        private const val MAX_BACKUP_BYTES = 5 * 1024 * 1024
        private const val READ_BUFFER_SIZE = 8192
        private const val MAX_BACKUP_FILENAME_LENGTH = 128

        private const val DEFAULT_BACKUP_NAME =
            "simorgh-backup.json"

        // Share / Clipboard
        private const val MAX_SHARE_TEXT_LENGTH = 4000
        private const val MAX_SUBJECT_LENGTH = 256

        private const val MAX_CLIPBOARD_TEXT_LENGTH = 16 * 1024
        private const val MAX_CLIPBOARD_LABEL_LENGTH = 128

        private const val DEFAULT_CLIP_LABEL = "simorgh_clip"
    }
}
