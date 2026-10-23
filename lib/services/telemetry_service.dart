import 'package:shared_preferences/shared_preferences.dart';

/// Stores the user's opt-in choice for sending diagnostics to GlitchTip/Sentry.
class TelemetryService {
  static const _enabledKey = 'diagnostics_enabled';
  static const dsn = String.fromEnvironment('GLITCHTIP_DSN');

  static bool _enabled = false;

  static bool get isEnabled => _enabled;
  static bool get isConfigured => dsn.trim().isNotEmpty;

  /// Load the saved choice before Sentry is initialized.
  /// Diagnostics remain off if preferences cannot be read.
  static Future<void> initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _enabled = isConfigured && (preferences.getBool(_enabledKey) ?? false);
    } catch (_) {
      _enabled = false;
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    if (enabled && !isConfigured) {
      throw StateError('Diagnostics are not configured in this build.');
    }

    // Apply opt-out immediately; opt-in takes effect only after it is saved.
    if (!enabled) _enabled = false;

    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setBool(_enabledKey, enabled);
    if (!saved) {
      if (enabled) _enabled = false;
      throw StateError('Could not save the diagnostics preference.');
    }

    if (enabled) _enabled = true;
  }
}
