package com.richi.fintrack

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity dibutuhkan oleh local_auth (sidik jari / face unlock)
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Saklar FLAG_SECURE: sembunyikan isi aplikasi di Recent Apps & blokir screenshot.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fintrack/secure_screen")
            .setMethodCallHandler { call, result ->
                if (call.method == "set") {
                    val on = call.arguments as? Boolean ?: false
                    if (on) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
