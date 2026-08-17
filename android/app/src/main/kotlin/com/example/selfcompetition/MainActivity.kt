package com.example.selfcompetition

import android.content.Context
import android.os.PowerManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val powerChannel = "selfcompetition/power"
	private var partialWakeLock: PowerManager.WakeLock? = null
	private var originalScreenBrightness: Float? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, powerChannel)
			.setMethodCallHandler { call, result ->
				if (call.method == "setRecordingKeepScreenOn") {
					val enabled = call.arguments as? Boolean ?: false
					if (enabled) {
						window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
					} else {
						window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
					}
					result.success(null)
				} else if (call.method == "setPowerSavingMode") {
					val enabled = call.arguments as? Boolean ?: false
					setPowerSavingMode(enabled)
					result.success(null)
				} else {
					result.notImplemented()
				}
			}
	}

	private fun setPowerSavingMode(enabled: Boolean) {
		if (enabled) {
			if (originalScreenBrightness == null) {
				originalScreenBrightness = window.attributes.screenBrightness
			}
			val attributes = window.attributes
			attributes.screenBrightness = 0.0f
			window.attributes = attributes
			window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

			if (partialWakeLock?.isHeld != true) {
				val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
				partialWakeLock = powerManager.newWakeLock(
					PowerManager.PARTIAL_WAKE_LOCK,
					"selfcompetition:power_saving",
				)
				partialWakeLock?.setReferenceCounted(false)
				partialWakeLock?.acquire()
			}
		} else {
			partialWakeLock?.let {
				if (it.isHeld) it.release()
			}
			partialWakeLock = null

			val attributes = window.attributes
			attributes.screenBrightness = originalScreenBrightness ?: -1.0f
			window.attributes = attributes
			originalScreenBrightness = null
			}
	}
}
