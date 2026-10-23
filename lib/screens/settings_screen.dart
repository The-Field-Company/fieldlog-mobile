import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fieldlog_mobile/app_typography.dart';
import '../theme/app_colors.dart';
import '../services/preferences_service.dart';
import '../services/telemetry_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _serverController = TextEditingController();
  final _powerSyncController = TextEditingController();
  bool _saved = false;
  bool _telemetryEnabled = TelemetryService.isEnabled;

  @override
  void initState() {
    super.initState();
    _loadUrls();
  }

  Future<void> _loadUrls() async {
    final serverUrl = await PreferencesService.getServerUrl();
    final powerSyncUrl = await PreferencesService.getPowerSyncUrl();
    if (!mounted) return;
    setState(() {
      _serverController.text = serverUrl;
      _powerSyncController.text = powerSyncUrl;
    });
  }

  String _cleanUrl(String url) {
    final trimmed = url.trim();
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  Future<void> _save() async {
    final serverUrl = _serverController.text.trim();
    final powerSyncUrl = _powerSyncController.text.trim();
    if (serverUrl.isEmpty || powerSyncUrl.isEmpty) return;

    await PreferencesService.setServerUrl(_cleanUrl(serverUrl));
    await PreferencesService.setPowerSyncUrl(_cleanUrl(powerSyncUrl));

    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  Future<void> _setTelemetryEnabled(bool enabled) async {
    setState(() => _telemetryEnabled = enabled);
    try {
      await TelemetryService.setEnabled(enabled);
    } catch (_) {
      if (!mounted) return;
      setState(() => _telemetryEnabled = TelemetryService.isEnabled);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save the diagnostics setting.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _serverController.dispose();
    _powerSyncController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              kDebugMode ? _buildEditableSettings() : _buildLockedSettings(),
              const SizedBox(height: 32),
              _buildDiagnosticsSettings(),
            ],
          ),
        ),
      ),
    );
  }

  /// Editable URL form — only shown in debug builds.
  Widget _buildEditableSettings() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Server URL
        Text(
          'SERVER URL',
          style: AppTypography.textStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textTertiary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _serverController,
          keyboardType: TextInputType.url,
          autocorrect: false,
          style: AppTypography.textStyle(
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
          decoration: const InputDecoration(
            hintText: 'https://your-server.example.com',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Set SERVER_URL in your .env.json to configure the default.',
          style: AppTypography.textStyle(
            fontSize: 13,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 32),

        // PowerSync URL
        Text(
          'POWERSYNC URL',
          style: AppTypography.textStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textTertiary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _powerSyncController,
          keyboardType: TextInputType.url,
          autocorrect: false,
          style: AppTypography.textStyle(
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
          decoration: const InputDecoration(
            hintText: 'https://your-powersync.example.com',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'PowerSync service URL. Default port is 8080.',
          style: AppTypography.textStyle(
            fontSize: 13,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 24),

        // Save button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _save,
            child: Text(_saved ? 'Saved!' : 'Save'),
          ),
        ),
      ],
    );
  }

  /// Read-only view shown in release builds.
  /// URLs are compiled in at build time and cannot be changed by users.
  Widget _buildLockedSettings() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.textTertiary.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.textTertiary.withAlpha(60)),
          ),
          child: Text(
            'Server configuration is managed by your administrator and cannot be changed on this device.',
            style: AppTypography.textStyle(
              fontSize: 13,
              color: AppColors.textTertiary,
            ),
          ),
        ),
        const SizedBox(height: 32),

        Text(
          'SERVER URL',
          style: AppTypography.textStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textTertiary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _serverController.text.isNotEmpty ? _serverController.text : '—',
          style: AppTypography.textStyle(
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 32),

        Text(
          'POWERSYNC URL',
          style: AppTypography.textStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textTertiary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _powerSyncController.text.isNotEmpty
              ? _powerSyncController.text
              : '—',
          style: AppTypography.textStyle(
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildDiagnosticsSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PRIVACY',
          style: AppTypography.textStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textTertiary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Share diagnostics',
            style: AppTypography.textStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          subtitle: Text(
            TelemetryService.isConfigured
                ? 'Opt in to send app error reports and performance traces to the diagnostics service configured for this build. Off by default.'
                : 'Diagnostics are not configured in this build.',
            style: AppTypography.textStyle(
              fontSize: 13,
              color: AppColors.textTertiary,
            ),
          ),
          value: TelemetryService.isConfigured && _telemetryEnabled,
          onChanged: TelemetryService.isConfigured
              ? _setTelemetryEnabled
              : null,
        ),
      ],
    );
  }
}
