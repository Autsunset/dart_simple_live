package com.xycz.simple_live

import android.app.ActivityManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.xycz.simple_live/diagnostics").setMethodCallHandler { call, result ->
            if (call.method != "previousExits") {
                result.notImplemented()
            } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                result.success(emptyList<Any>())
            } else {
                try {
                    val manager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
                    val exits = manager.getHistoricalProcessExitReasons(packageName, 0, 5)
                    result.success(exits.map { exit ->
                        mapOf(
                            "timestamp" to exit.timestamp,
                            "reason" to exit.reason,
                            "status" to exit.status,
                            "description" to exit.description,
                            "importance" to exit.importance,
                            "pssKiB" to exit.pss,
                            "rssKiB" to exit.rss,
                            "process" to exit.processName,
                            "device" to "${Build.MANUFACTURER} ${Build.MODEL}",
                            "androidSdk" to Build.VERSION.SDK_INT
                        )
                    })
                } catch (error: Exception) {
                    result.error("exit_info", error.message, null)
                }
            }
        }
    }
}
