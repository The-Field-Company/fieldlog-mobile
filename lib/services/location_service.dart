import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  static Future<Map<String, dynamic>?> captureLocation() async {
    try {
      final permission = await _ensurePermission();
      if (!permission) return null;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('[LocationService] captureLocation failed: $e');
      return null;
    }
  }

  static Future<bool> _ensurePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;

    return true;
  }

  /// Requests permission if not yet granted, then returns a detailed status.
  /// Call this on form load — it shows the native dialog on first use.
  static Future<String> requestAndCheckStatus() async {
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return 'Location services disabled';

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        return 'Location access permanently denied';
      }
      if (permission == LocationPermission.denied) {
        return 'Location permission denied';
      }

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
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return 'Location services disabled';

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.deniedForever) {
        return 'Location access permanently denied';
      }
      if (permission == LocationPermission.denied) {
        return 'Location permission denied';
      }

      return 'Location available';
    } catch (e) {
      if (kDebugMode) debugPrint('[LocationService] getStatus failed: $e');
      return 'Location unavailable';
    }
  }
}
