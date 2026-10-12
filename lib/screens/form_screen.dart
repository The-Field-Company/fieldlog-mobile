import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/session.dart';
import '../theme/app_colors.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/powersync_service.dart';
import '../services/preferences_service.dart';
import '../services/location_service.dart';
import '../widgets/formkit_renderer.dart';
import '../widgets/tally_renderer.dart';
import '../widgets/surveyjs_renderer.dart';
import '../widgets/sync_status_widget.dart';

class FormScreen extends StatefulWidget {
  const FormScreen({super.key});

  @override
  State<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends State<FormScreen> {
  late Session _session;
  String _locationStatus = 'Acquiring location...';
  bool _locationReady = false;
  Map<String, int> _tallyCounts = {};
  bool _tallyCountsLoaded = false;
  bool _sessionRefreshed = false;
  Map<String, dynamic>? _cachedLocation;
  DateTime? _locationCapturedAt;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session = ModalRoute.of(context)!.settings.arguments as Session;
    if (_session.trackLocation) {
      _initLocation();
    }
    if (_session.formMode == 'tally' && !_tallyCountsLoaded) {
      _loadTallyCounts();
    }
    if (!_sessionRefreshed) {
      _sessionRefreshed = true;
      _refreshSession();
    }
  }

  Future<void> _loadTallyCounts() async {
    final db = PowerSyncService.getPowerSync();
    if (db == null) {
      setState(() => _tallyCountsLoaded = true);
      return;
    }

    try {
      final rows = await db.getAll(
        'SELECT data FROM fieldlog_submission WHERE session_id = ?',
        [_session.id],
      );

      final counts = <String, int>{};
      for (final row in rows) {
        final data = jsonDecode(row['data'] as String) as Map<String, dynamic>;
        final key = data['tally_key'] as String?;
        if (key != null) {
          counts[key] = (counts[key] ?? 0) + 1;
        }
      }

      if (mounted) {
        setState(() {
          _tallyCounts = counts;
          _tallyCountsLoaded = true;
        });
      }
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        withScope: (scope) => scope.setTag('session_id', _session.id.toString()),
      );
      if (mounted) setState(() => _tallyCountsLoaded = true);
    }
  }

  Future<void> _refreshSession() async {
    try {
      final fresh = await ApiService.getSession(_session.id.toString());
      await PreferencesService.cacheSession(fresh);
      if (!mounted) return;
      setState(() => _session = fresh);
    } catch (e) {
      // Offline or server error — keep using the cached session
      if (kDebugMode) debugPrint('[FormScreen] Session refresh failed, using cache: $e');
    }
  }

  Future<void> _initLocation() async {
    final status = await LocationService.requestAndCheckStatus();
    if (mounted) {
      setState(() {
        _locationStatus = status;
        _locationReady = status == 'Location available';
      });
      // Start capturing in background so the fix is ready by submit time.
      if (_locationReady) _prefetchLocation();
    }
  }

  Future<void> _prefetchLocation() async {
    final location = await LocationService.captureLocation();
    if (mounted && location != null) {
      _cachedLocation = location;
      _locationCapturedAt = DateTime.now();
    }
  }

  /// Returns the cached fix if it is less than 60 seconds old, otherwise null.
  /// 60 s is accurate enough for a stationary or slow-moving field observer.
  Map<String, dynamic>? _freshCachedLocation() {
    if (_cachedLocation == null || _locationCapturedAt == null) return null;
    if (DateTime.now().difference(_locationCapturedAt!) >
        const Duration(seconds: 60)) {
      return null;
    }
    return _cachedLocation;
  }

  void _onSyncTransition(SyncStateTransition transition) {
    if (!mounted) return;

    // In tally mode, suppress syncComplete — it fires after every single tap
    // when online, which spams the user. The pill widget still shows status.
    if (transition == SyncStateTransition.syncComplete &&
        _session.formMode == 'tally') {
      return;
    }

    late final String message;
    late final Color bgColor;

    switch (transition) {
      case SyncStateTransition.wentOffline:
        message = 'You\'re offline \u2014 data saves locally';
        bgColor = Colors.orange.shade700;
      case SyncStateTransition.backOnline:
        message = 'Back online';
        bgColor = AppColors.accentLight;
      case SyncStateTransition.syncComplete:
        message = 'All submissions synced';
        bgColor = AppColors.accent;
    }

    // Clear previous sync toasts to prevent stacking on rapid flapping
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _submitToLocal(Map<String, dynamic> data) async {
    final db = PowerSyncService.getPowerSync();
    if (db == null) {
      throw Exception('PowerSync not initialized');
    }

    final id = const Uuid().v4();
    final username = AuthService.getUsername() ?? 'Anonymous';

    await db.execute(
      'INSERT INTO fieldlog_submission (id, session_id, submitted_by, data, submitted_at) VALUES (?, ?, ?, ?, ?)',
      [
        id,
        _session.id,
        username,
        jsonEncode(data),
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  Future<void> _submitFormData(Map<String, dynamic> data) async {
    final transaction = Sentry.startTransaction(
      'submit_observation',
      'form',
      bindToScope: true,
    );
    transaction.setTag('session_id', _session.id.toString());

    try {
      // Attach location if tracking. Use prefetched fix when fresh, else capture now.
      if (_session.trackLocation) {
        final location =
            _freshCachedLocation() ?? await LocationService.captureLocation();
        if (location != null) {
          data['_location'] = location;
        }
      }

      final submitSpan = transaction.startChild(
        'submit_local',
        description: 'Insert submission into PowerSync local DB',
      );
      try {
        await _submitToLocal(data);
      } finally {
        await submitSpan.finish();
      }
    } catch (e, stackTrace) {
      transaction.throwable = e;
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        withScope: (scope) => scope.setTag('session_id', _session.id.toString()),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
      return;
    } finally {
      await transaction.finish();
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context,
      '/success',
      arguments: _session,
    );
  }

  Future<void> _submitTally(Map<String, dynamic> data) async {
    // Attach location if tracking. Use prefetched fix when fresh, else capture now.
    if (_session.trackLocation) {
      final location =
          _freshCachedLocation() ?? await LocationService.captureLocation();
      if (location != null) {
        data['_location'] = location;
      }
    }

    try {
      await _submitToLocal(data);
    } catch (e, stackTrace) {
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
        withScope: (scope) => scope.setTag('session_id', _session.id.toString()),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to record tally: $e'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (!mounted) return;

    // Keep local counts in sync without re-querying
    final tallyKey = data['tally_key'] as String?;
    if (tallyKey != null) {
      setState(() {
        _tallyCounts = Map<String, int>.from(_tallyCounts);
        _tallyCounts[tallyKey] = (_tallyCounts[tallyKey] ?? 0) + 1;
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${data['tally_label']} +1'),
        duration: const Duration(milliseconds: 800),
        backgroundColor: AppColors.accent,
      ),
    );
  }

  Widget _buildRenderer() {
    switch (_session.formMode) {
      case 'tally':
        if (!_tallyCountsLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        return TallyRenderer(
          components: _session.components,
          onTap: _submitTally,
          initialCounts: _tallyCounts,
        );
      case 'surveyjs':
        if (_session.schema != null) {
          return SurveyjsRenderer(
            schema: _session.schema!,
            onSubmit: _submitFormData,
          );
        }
        return const Center(child: Text('No survey schema found'));
      case 'formkit':
      default:
        return FormkitRenderer(
          components: _session.components,
          onSubmit: _submitFormData,
        );
    }
  }

  Widget _buildLocationIndicator() {
    if (!_session.trackLocation) return const SizedBox.shrink();

    // Transient: acquiring — subtle strip, disappears once resolved
    if (_locationStatus == 'Acquiring location...') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.dividerColor)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Acquiring location...',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      );
    }

    // Ready: silent
    if (_locationReady) return const SizedBox.shrink();

    // Persistent: service disabled or permanently denied — banner with action.
    // 'Location permission denied' after requesting means the user just tapped
    // Deny on the native dialog; no settings action is available at that point.
    final bool isServiceDisabled =
        _locationStatus == 'Location services disabled';
    final bool isPermanentlyDenied =
        _locationStatus == 'Location access permanently denied';
    final bool hasSettingsAction = isServiceDisabled || isPermanentlyDenied;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 12, hasSettingsAction ? 8 : 16, 12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.orange.shade200),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.location_off_outlined,
            size: 16,
            color: Colors.orange.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _locationStatus,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (hasSettingsAction)
            TextButton(
              onPressed: () async {
                if (isServiceDisabled) {
                  await Geolocator.openLocationSettings();
                } else {
                  await Geolocator.openAppSettings();
                }
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Open Settings',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.accent,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_session.name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SyncStatusWidget(onTransition: _onSyncTransition),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildLocationIndicator(),
          Expanded(child: _buildRenderer()),
        ],
      ),
    );
  }
}
