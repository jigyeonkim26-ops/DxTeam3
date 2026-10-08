package com.example.overlap_app

import android.annotation.SuppressLint
import android.content.Context
import android.location.LocationManager
import android.os.Handler
import android.os.Looper
import androidx.core.location.LocationManagerCompat
import androidx.core.os.CancellationSignal
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** One-shot device GPS requests without geolocator's GNSS/NMEA listeners. */
class CurrentLocationChannel(context: Context, messenger: BinaryMessenger) {
    private val manager = context.applicationContext
        .getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "overlap/current_location")
    private var pending: Request? = null

    private class Request(val result: MethodChannel.Result) {
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
        request.timeout = Runnable { finish(request, error = "timeout") }
        main.postDelayed(request.timeout, 15_000)
        // Even registration/cancellation Binder calls must not block the UI thread.
        worker.execute {
            try {
                if (request.cancellation.isCanceled) return@execute
                if (!LocationManagerCompat.isLocationEnabled(manager) ||
                    !manager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
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
                        if (location == null) finish(request, error = "unavailable")
                        else finish(request, coordinates = mapOf(
                            "latitude" to location.latitude,
                            "longitude" to location.longitude,
                        ))
                    }
                }
            } catch (_: SecurityException) {
                main.post { finish(request, error = "permissionDenied") }
            } catch (_: Exception) {
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
        if (error != null) request.result.error(error, "GPS request failed: $error", null)
        else request.result.success(coordinates)
    }

    fun close() {
        channel.setMethodCallHandler(null)
        pending?.let { finish(it, error = "unavailable") }
        worker.shutdown()
    }
}
