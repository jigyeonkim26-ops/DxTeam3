package com.example.overlap_app

import android.annotation.SuppressLint
import android.content.Context
import android.location.LocationManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.core.location.LocationManagerCompat
import androidx.core.os.CancellationSignal
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** One-shot device GPS requests without geolocator's GNSS/NMEA listeners. */
class CurrentLocationChannel(context: Context, messenger: BinaryMessenger) {
    companion object {
        private const val TAG = "OverlapGPS"
    }

    private val manager = context.applicationContext
        .getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "overlap/current_location")
    private var pending: Request? = null

    private class Request(val result: MethodChannel.Result) {
        val startedAt = SystemClock.elapsedRealtime()
        val cancellation = CancellationSignal()
        lateinit var timeout: Runnable
    }

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "getCurrentPosition") readPosition(result)
            else result.notImplemented()
        }
    }

    @SuppressLint("MissingPermission") // Dart requests permission; SecurityException handles revocation.
    private fun readPosition(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("unavailable", "A GPS request is already pending", null)
            return
        }
        val request = Request(result)
        pending = request
        Log.d(TAG, "request started provider=GPS timeout_ms=15000")
        request.timeout = Runnable { finish(request, error = "timeout") }
        main.postDelayed(request.timeout, 15_000)
        // Even registration/cancellation Binder calls must not block the UI thread.
        worker.execute {
            try {
                if (request.cancellation.isCanceled) return@execute
                if (!LocationManagerCompat.isLocationEnabled(manager) ||
                    !manager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                    Log.d(TAG, "request unavailable location_enabled=false or gps_provider_disabled")
                    main.post { finish(request, error = "serviceDisabled") }
                    return@execute
                }
                LocationManagerCompat.getCurrentLocation(
                    manager,
                    LocationManager.GPS_PROVIDER,
                    request.cancellation,
                    worker,
                ) { location ->
                    main.post {
                        if (location == null) {
                            Log.d(TAG, "provider returned no fix")
                            finish(request, error = "unavailable")
                        } else {
                            Log.d(TAG, "provider returned a fix; coordinates withheld")
                            finish(request, coordinates = mapOf(
                                "latitude" to location.latitude,
                                "longitude" to location.longitude,
                            ))
                        }
                    }
                }
            } catch (_: SecurityException) {
                Log.w(TAG, "request failed type=SecurityException")
                main.post { finish(request, error = "permissionDenied") }
            } catch (error: Exception) {
                Log.w(TAG, "request failed type=${error.javaClass.simpleName}")
                main.post { finish(request, error = "unavailable") }
            }
        }
    }

    private fun finish(
        request: Request,
        coordinates: Map<String, Double>? = null,
        error: String? = null,
    ) {
        if (pending !== request) return
        pending = null
        main.removeCallbacks(request.timeout)
        worker.execute { request.cancellation.cancel() }
        Log.d(
            TAG,
            "request finished status=${error ?: "success"} " +
                "elapsed_ms=${SystemClock.elapsedRealtime() - request.startedAt}",
        )
        if (error != null) request.result.error(error, "GPS request failed: $error", null)
        else request.result.success(coordinates)
    }

    fun close() {
        channel.setMethodCallHandler(null)
        pending?.let { finish(it, error = "unavailable") }
        worker.shutdown()
    }
}
