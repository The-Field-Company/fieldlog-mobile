import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// OS-level network connectivity service.
///
/// Wraps connectivity_plus so widgets get an immediate boolean signal when the
/// device interface changes, without waiting for PowerSync's WebSocket to time
/// out (which can take 30+ seconds after the device actually goes offline).
///
/// [init] must be awaited in main() before runApp().
class ConnectivityService {
  static final Connectivity _connectivity = Connectivity();
  static final StreamController<bool> _controller =
      StreamController<bool>.broadcast();

  // Optimistic default — overwritten by init() before any widget mounts.
  static bool _isOnline = true;

  static bool get isOnline => _isOnline;
  static Stream<bool> get stream => _controller.stream;

  static Future<void> init() async {
    // Snapshot current state first.
    final initial = await _connectivity.checkConnectivity();
    _isOnline = _hasConnection(initial);

    // Subscribe so future changes are captured. This is a static singleton
    // that lives for the app's entire lifetime, so we intentionally do not
    // store or cancel the subscription.
    _connectivity.onConnectivityChanged.listen((results) {
      final online = _hasConnection(results);
      if (online == _isOnline) return; // no change, skip
      _isOnline = online;
      _controller.add(online);
    });
  }

  static bool _hasConnection(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);
}
