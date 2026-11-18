package ir.moshaver.tahsili

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private var pendingBackupResult: MethodChannel.Result? = null
    private var pendingBackupContent: String? = null

    override fun provideFlutterEngine(context: android.content.Context): FlutterEngine? {
        return FlutterEngineCache.getInstance().get(ENGINE_ID)
            ?: super.provideFlutterEngine(context)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
        private const val REQUEST_SAVE = 7401
        private const val REQUEST_OPEN = 7402
        private const val MAX_BACKUP_BYTES = 5 * 1024 * 1024
        private const val DEFAULT_BACKUP_NAME = "simorgh-backup.json"
    }
}
