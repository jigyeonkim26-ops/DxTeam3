package com.example.overlap_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "overlap/kakao_config",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getJavaScriptKey" -> result.success(getString(R.string.kakao_javascript_key))
                else -> result.notImplemented()
            }
        }
    }
}
