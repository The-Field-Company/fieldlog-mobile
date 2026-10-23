import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads one location fix through the operating system's native location APIs.
///
/// Android uses LocationManager (no Google Play Services dependency), and iOS
/// uses Core Location. Location is requested only by sessions that enable it.
class LocationService {
  static const MethodChannel _channel = MethodChannel('com.fieldlog/location');

  static Future<bool> _locationServicesEnabled() async {
    return await _channel.invokeMethod<bool>('isLocationServiceEnabled') ??
        false;
  }

  static Future<String> _permissionStatus() async {
    return await _channel.invokeMethod<String>('checkPermission') ?? 'denied';
  }

  static Future<String> _requestPermission() async {
    return await _channel.invokeMethod<String>('requestPermission') ??
        'denied';
  }

  static Future<bool> _ensurePermission() async {
    if (!await _locationServicesEnabled()) return false;

    final permission = await _permissionStatus();
    if (permission == 'granted') return true;
    if (permission == 'denied') {
      final requestedPermission = await _requestPermission();
      return requestedPermission == 'granted';
    }
    return false;
  }

  static Future<Map<String, dynamic>?> captureLocation() async {
    try {
      if (!await _ensurePermission()) return null;
      return await _channel.invokeMapMethod<String, dynamic>(
        'getCurrentPosition',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[LocationService] captureLocation failed: $e');
      return null;
    }
  }

  /// Requests permission if needed, then returns the current location status.
  /// Call this on form load so the native permission dialog appears on first use.
  static Future<String> requestAndCheckStatus() async {
    try {
      if (!await _locationServicesEnabled()) {
        return 'Location services disabled';
      }

      var permission = await _permissionStatus();
      if (permission == 'denied') {
        permission = await _requestPermission();
      }

      if (permission == 'deniedForever') {
        return 'Location access permanently denied';
      }
      if (permission != 'granted') return 'Location permission denied';

      return 'Location available';
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LocationService] requestAndCheckStatus failed: $e');
      }
      return 'Location unavailable';
    }
  }

  static Future<String> getStatus() async {
    try {
      if (!await _locationServicesEnabled()) {
        return 'Location services disabled';
      }

      final permission = await _permissionStatus();
      if (permission == 'deniedForever') {
        return 'Location access permanently denied';
      }
      if (permission == 'denied') return 'Location permission denied';

      return 'Location available';
    } catch (e) {
      if (kDebugMode) debugPrint('[LocationService] getStatus failed: $e');
      return 'Location unavailable';
    }
  }

  static Future<bool> openLocationSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openLocationSettings') ?? false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LocationService] openLocationSettings failed: $e');
      }
      return false;
    }
  }

  static Future<bool> openAppSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openAppSettings') ?? false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LocationService] openAppSettings failed: $e');
      }
      return false;
    }
  }
}
