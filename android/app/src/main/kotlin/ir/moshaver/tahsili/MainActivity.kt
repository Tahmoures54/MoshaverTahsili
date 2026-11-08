package ir.moshaver.tahsili

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache

class MainActivity : FlutterActivity() {

    /**
     * ۱) گرم‌کردن موتور فلاتر برای راه‌اندازی سریع‌تر
     *    وقتی اپ از پس‌زمینه یا دیپ‌لینک باز می‌شود، تأخیر کمتر می‌شود.
     */
    override fun provideFlutterEngine(context: android.content.Context): FlutterEngine? {
        return FlutterEngineCache.getInstance().get(ENGINE_ID)
            ?: super.provideFlutterEngine(context)
    }

    /**
     * ۲) پیکربندی موتور فلاتر
     *    اگر پلتفرم‌چنل سفارشی دارید، اینجا رجیستر کنید.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // مثال:
        // MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ir.moshaver.tahsili/native")
        //     .setMethodCallHandler { call, result -> ... }
    }

    /**
     * ۳) هدایت Intent جدید به فلاتر
     *    ضروری برای:
     *      - بازگشت از پرداخت بازار (Bazaar IAP)
     *      - دیپ‌لینک‌ها وقتی اپ در پس‌زمینه است
     *      - نوتیفیکیشن‌های پوش
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    companion object {
        private const val ENGINE_ID = "moshaver_tahsili_engine"
    }
}
