package ir.moshaver.tahsili

import io.flutter.app.FlutterApplication
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

class App : FlutterApplication() {

    override fun onCreate() {
        super.onCreate()

        // پیش‌بارگذاری موتور فلاتر در پس‌زمینه
        val engine = FlutterEngine(this).apply {
            dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
        }
        FlutterEngineCache.getInstance().put("moshaver_tahsili_engine", engine)
    }
}
