package dev.yureru.yureru

import android.app.PictureInPictureParams
import android.os.Build
import android.util.Rational
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "yureru/media_picker"
    private var pipChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setBackgroundPlayback" -> {
                    val playing = call.arguments as? Boolean ?: false
                    val serviceIntent = android.content.Intent(
                        this,
                        PlaybackForegroundService::class.java,
                    ).setAction(
                        if (playing) PlaybackForegroundService.ACTION_START
                        else PlaybackForegroundService.ACTION_STOP,
                    )
                    try {
                        if (playing && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "enterSystemPictureInPicture" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                        result.success(false)
                    } else {
                        try {
                            val params = PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(16, 9))
                                .build()
                            result.success(enterPictureInPictureMode(params))
                        } catch (_: IllegalArgumentException) {
                            result.success(false)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: android.content.res.Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("onSystemPictureInPictureChanged", isInPictureInPictureMode)
    }
}
