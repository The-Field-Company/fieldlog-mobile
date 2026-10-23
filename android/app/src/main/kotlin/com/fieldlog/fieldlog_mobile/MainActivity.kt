package com.fieldlog.fieldlog_mobile

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.fieldlog/location"
        private const val LOCATION_PERMISSION_REQUEST = 7402
        private const val LOCATION_TIMEOUT_MS = 10_000L
        private const val FUSED_PROVIDER = "fused"
        private const val PREFERENCES_NAME = "fieldlog_location_permissions"
        private const val PERMISSION_REQUESTED_KEY = "location_permission_requested"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val locationManager: LocationManager
        get() = getSystemService(LOCATION_SERVICE) as LocationManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isLocationServiceEnabled" -> result.success(isLocationServiceEnabled())
                    "checkPermission" -> result.success(permissionStatus())
                    "requestPermission" -> requestLocationPermission(result)
                    "getCurrentPosition" -> CurrentLocationRequest(result).start()
                    "openLocationSettings" -> result.success(openSettings(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
                    "openAppSettings" -> result.success(openAppSettings())
                    else -> result.notImplemented()
                }
            }
    }

    private fun isLocationServiceEnabled(): Boolean {
        return try {
            listOf(
                LocationManager.GPS_PROVIDER,
                LocationManager.NETWORK_PROVIDER,
                FUSED_PROVIDER,
            ).any { provider ->
                try {
                    locationManager.allProviders.contains(provider) &&
                        locationManager.isProviderEnabled(provider)
                } catch (_: IllegalArgumentException) {
                    false
                }
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun hasPermission(permission: String): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasLocationPermission(): Boolean {
        return hasPermission(Manifest.permission.ACCESS_FINE_LOCATION) ||
            hasPermission(Manifest.permission.ACCESS_COARSE_LOCATION)
    }

    private fun permissionStatus(): String {
        if (hasLocationPermission()) return "granted"
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return "granted"

        val preferences = getSharedPreferences(PREFERENCES_NAME, MODE_PRIVATE)
        val wasRequested = preferences.getBoolean(PERMISSION_REQUESTED_KEY, false)
        val canShowRationale = shouldShowRequestPermissionRationale(
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) || shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_COARSE_LOCATION)

        return if (wasRequested && !canShowRationale) "deniedForever" else "denied"
    }

    private fun requestLocationPermission(result: MethodChannel.Result) {
        val status = permissionStatus()
        if (status != "denied") {
            result.success(status)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("PERMISSION_REQUEST_IN_PROGRESS", "A location permission request is already active", null)
            return
        }

        pendingPermissionResult = result
        getSharedPreferences(PREFERENCES_NAME, MODE_PRIVATE)
            .edit()
            .putBoolean(PERMISSION_REQUESTED_KEY, true)
            .apply()
        requestPermissions(
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ),
            LOCATION_PERMISSION_REQUEST,
        )
    }

    @Deprecated("Deprecated in Android")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == LOCATION_PERMISSION_REQUEST) {
            pendingPermissionResult?.success(permissionStatus())
            pendingPermissionResult = null
        }
    }

    private fun openSettings(action: String): Boolean {
        return try {
            startActivity(Intent(action))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun openAppSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private inner class CurrentLocationRequest(
        private val result: MethodChannel.Result,
    ) {
        private val listeners = mutableListOf<LocationListener>()
        private var bestLocation: Location? = null
        private var finished = false
        private val timeout = Runnable { finish(bestLocation) }

        fun start() {
            if (!hasLocationPermission()) {
                result.error("PERMISSION_DENIED", "Location permission is not granted", null)
                return
            }
            if (!isLocationServiceEnabled()) {
                result.error("LOCATION_DISABLED", "Location services are disabled", null)
                return
            }

            val availableProviders = locationManager.allProviders.filter { provider ->
                try {
                    locationManager.isProviderEnabled(provider)
                } catch (_: IllegalArgumentException) {
                    false
                } catch (_: SecurityException) {
                    false
                }
            }
            val providers = buildList {
                if (hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)) {
                    add(LocationManager.GPS_PROVIDER)
                }
                add(FUSED_PROVIDER)
                add(LocationManager.NETWORK_PROVIDER)
            }.distinct().filter { availableProviders.contains(it) }

            if (providers.isEmpty()) {
                result.error("LOCATION_UNAVAILABLE", "No enabled location provider is available", null)
                return
            }

            mainHandler.postDelayed(timeout, LOCATION_TIMEOUT_MS)
            providers.forEach { provider -> requestUpdates(provider) }
            if (listeners.isEmpty()) {
                finish(null)
            }
        }

        private fun requestUpdates(provider: String) {
            val listener = object : LocationListener {
                override fun onLocationChanged(location: Location) {
                    if (location.accuracy > 0f) {
                        val previous = bestLocation
                        if (previous == null || location.accuracy < previous.accuracy) {
                            bestLocation = location
                        }

                        // Return a good GPS/system-fused fix promptly; otherwise
                        // keep listening until the timeout and return the best fix.
                        if ((provider == LocationManager.GPS_PROVIDER || provider == FUSED_PROVIDER) &&
                            location.accuracy <= 30f
                        ) {
                            finish(bestLocation)
                        }
                    }
                }

                override fun onProviderEnabled(provider: String) = Unit

                override fun onProviderDisabled(provider: String) = Unit

                @Deprecated("Deprecated in Android")
                override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit
            }

            try {
                locationManager.requestLocationUpdates(
                    provider,
                    0L,
                    0f,
                    listener,
                    Looper.getMainLooper(),
                )
                listeners.add(listener)
            } catch (_: SecurityException) {
                // A coarse-only grant may not allow every provider. Try the others.
            } catch (_: IllegalArgumentException) {
                // Some Android devices advertise providers that cannot be used.
            }
        }

        private fun finish(location: Location?) {
            if (finished) return
            finished = true
            mainHandler.removeCallbacks(timeout)
            listeners.forEach { listener ->
                try {
                    locationManager.removeUpdates(listener)
                } catch (_: SecurityException) {
                    // Permission may have been revoked while the request was active.
                }
            }
            listeners.clear()

            if (location == null) {
                result.error("LOCATION_TIMEOUT", "No location fix was available", null)
            } else {
                result.success(
                    mapOf(
                        "latitude" to location.latitude,
                        "longitude" to location.longitude,
                        "accuracy" to location.accuracy.toDouble(),
                    ),
                )
            }
        }
    }
}
