import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityState {
  final bool isOnline;
  final bool isOnWifi;

  const ConnectivityState({
    required this.isOnline,
    required this.isOnWifi,
  });

  @override
  bool operator ==(Object other) =>
      other is ConnectivityState &&
      other.isOnline == isOnline &&
      other.isOnWifi == isOnWifi;

  @override
  int get hashCode => Object.hash(isOnline, isOnWifi);
}

/// OS-level network connectivity service.
///
/// Wraps connectivity_plus so widgets and background queues get an immediate
/// signal when network availability or transport type (Wi-Fi vs cellular)
/// changes, without waiting for PowerSync's WebSocket to time out.
///
/// [init] must be awaited in main() before runApp().
class ConnectivityService {
  static final Connectivity _connectivity = Connectivity();
  static final StreamController<bool> _controller =
      StreamController<bool>.broadcast();
  static final StreamController<ConnectivityState> _stateController =
      StreamController<ConnectivityState>.broadcast();

  // Optimistic defaults — overwritten by init() before any widget mounts.
  static bool _isOnline = true;
  static bool _isOnWifi = true;

  static bool get isOnline => _isOnline;
  static bool get isOnWifi => _isOnWifi;
  static ConnectivityState get state =>
      ConnectivityState(isOnline: _isOnline, isOnWifi: _isOnWifi);
  static Stream<bool> get stream => _controller.stream;
  static Stream<ConnectivityState> get stateStream => _stateController.stream;

  static Future<void> init() async {
    final initial = await _connectivity.checkConnectivity();
    _isOnline = _hasConnection(initial);
    _isOnWifi = _hasUnmeteredConnection(initial);

    // Static app-lifetime singleton subscription.
    _connectivity.onConnectivityChanged.listen((results) {
      final online = _hasConnection(results);
      final wifi = _hasUnmeteredConnection(results);
      final onlineChanged = online != _isOnline;
      final wifiChanged = wifi != _isOnWifi;
      if (!onlineChanged && !wifiChanged) return;

      _isOnline = online;
      _isOnWifi = wifi;
      if (onlineChanged) _controller.add(online);
      _stateController.add(ConnectivityState(isOnline: online, isOnWifi: wifi));
    });
  }

  static bool _hasConnection(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  static bool _hasUnmeteredConnection(List<ConnectivityResult> results) =>
      results.any(
        (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet,
      );
}
