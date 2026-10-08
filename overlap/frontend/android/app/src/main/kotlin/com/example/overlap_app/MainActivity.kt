package com.example.overlap_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var currentLocationChannel: CurrentLocationChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        currentLocationChannel = CurrentLocationChannel(
            this, flutterEngine.dartExecutor.binaryMessenger,
        )

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

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        currentLocationChannel?.close()
        currentLocationChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
