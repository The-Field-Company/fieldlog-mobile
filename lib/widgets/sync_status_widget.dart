import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fieldlog_mobile/app_typography.dart';
import 'package:powersync/powersync.dart';
import '../theme/app_colors.dart';
import '../services/powersync_service.dart';
import '../services/connectivity_service.dart';

/// A compact pill widget that shows the current sync state.
/// Designed for app bars — small, unobtrusive, glanceable.
class SyncStatusWidget extends StatefulWidget {
  /// Optional callback when sync state transitions happen.
  /// Useful for parent widgets that want to show toasts.
  final void Function(SyncStateTransition transition)? onTransition;

  const SyncStatusWidget({super.key, this.onTransition});

  @override
  State<SyncStatusWidget> createState() => _SyncStatusWidgetState();
}

enum SyncStateTransition { wentOffline, backOnline, syncComplete }

class _SyncStatusWidgetState extends State<SyncStatusWidget> {
  // Three pieces of state, from two sources:
  // - ConnectivityService  → _connected  (OS network interface — fast)
  // - PowerSync statusStream → _psConnected (WebSocket to PS service) + _uploading
  //
  // We keep them separate because they change at different times:
  //   OS online → _connected=true  (immediate)
  //   PS WebSocket reconnects → _psConnected=true  (seconds/minutes later)
  // "Reconnecting…" is shown when OS says online but PS hasn't reconnected yet.
  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<SyncStatus>? _psSubscription;
  bool _connected = false;
  bool _psConnected = false;
  bool _uploading = false;
  bool? _previousConnected;

  @override
  void initState() {
    super.initState();
    _listenToStatus();
  }

  void _listenToStatus() {
    // 1. OS-level connectivity — drives offline/online toasts.
    _connected = ConnectivityService.isOnline;
    _previousConnected = _connected;

    _connectivitySubscription = ConnectivityService.stream.listen((isOnline) {
      if (!mounted) return;
      final wasConnected = _previousConnected;
      setState(() => _connected = isOnline);

      if (widget.onTransition != null) {
        if (wasConnected == true && !isOnline) {
          widget.onTransition!(SyncStateTransition.wentOffline);
        } else if (wasConnected == false && isOnline) {
          widget.onTransition!(SyncStateTransition.backOnline);
        }
      }
      _previousConnected = isOnline;
    });

    // 2. PowerSync stream — WebSocket connection state, upload state, and
    //    the syncComplete transition.
    final db = PowerSyncService.getPowerSync();
    if (db == null) return;

    _psConnected = db.currentStatus.connected;
    _uploading = db.currentStatus.uploading;

    _psSubscription = db.statusStream.listen((status) {
      if (!mounted) return;
      final wasUploading = _uploading;
      setState(() {
        _psConnected = status.connected;
        _uploading = status.uploading;
      });

      if (widget.onTransition != null) {
        if (wasUploading && !status.uploading && status.connected) {
          widget.onTransition!(SyncStateTransition.syncComplete);
        }
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _psSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final String label;
    late final Color color;
    // Show a spinner for both "uploading" and "reconnecting" states.
    final bool showSpinner;

    if (!_connected) {
      icon = Icons.cloud_off_outlined;
      label = 'Offline';
      color = Colors.orange.shade700;
      showSpinner = false;
    } else if (_uploading) {
      icon = Icons.cloud_upload_outlined;
      label = 'Syncing';
      color = AppColors.accentLight;
      showSpinner = true;
    } else if (!_psConnected) {
      // OS has network but PowerSync WebSocket hasn't reconnected yet.
      icon = Icons.cloud_sync_outlined;
      label = 'Reconnecting';
      color = Colors.orange.shade400;
      showSpinner = true;
    } else {
      icon = Icons.cloud_outlined;
      label = 'Online';
      color = AppColors.accent;
      showSpinner = false;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSpinner)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            )
          else
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.textStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Standalone widget for the success screen that shows sync state as a subtitle line.
class SyncStatusText extends StatefulWidget {
  const SyncStatusText({super.key});

  @override
  State<SyncStatusText> createState() => _SyncStatusTextState();
}

class _SyncStatusTextState extends State<SyncStatusText> {
  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<SyncStatus>? _psSubscription;
  bool _connected = false;
  bool _uploading = false;
  // True once upload is confirmed done. Set either by observing the
  // uploading→done transition via the stream, or — to fix the race where the
  // upload completes before this screen renders — by finding ps_crud empty on
  // mount.
  bool _uploadConfirmed = false;

  @override
  void initState() {
    super.initState();

    // 1. Device-level connectivity — drives the offline/online display.
    _connected = ConnectivityService.isOnline;
    _connectivitySubscription = ConnectivityService.stream.listen((isOnline) {
      if (!mounted) return;
      setState(() => _connected = isOnline);
    });

    // 2. PowerSync stream — drives uploading state and upload confirmation.
    final db = PowerSyncService.getPowerSync();
    if (db != null) {
      _uploading = db.currentStatus.uploading;

      // If connected and idle on mount the upload may have already finished
      // before this screen rendered (fast network / fast server). Check the
      // CRUD queue directly rather than waiting for a transition that already
      // happened and will never fire again.
      if (_connected && !_uploading) {
        _checkPendingCrud(db);
      }

      _psSubscription = db.statusStream.listen((status) {
        if (!mounted) return;
        final wasUploading = _uploading;
        setState(() {
          _uploading = status.uploading;
          // Use status.connected (PowerSync WebSocket) here rather than
          // _connected (device level) so confirmation is tied to the actual
          // upload completing on the PowerSync service, not just device state.
          if (wasUploading && !status.uploading && status.connected) {
            _uploadConfirmed = true;
          }
        });
      });
    }
  }

  /// Queries the PowerSync CRUD queue. If it is empty while connected and
  /// idle, the upload completed before this widget mounted.
  Future<void> _checkPendingCrud(PowerSyncDatabase db) async {
    try {
      final rows = await db.getAll('SELECT id FROM ps_crud LIMIT 1');
      // Bail out if state changed while the query was in flight.
      if (!mounted || _uploadConfirmed || _uploading) return;
      if (rows.isEmpty) {
        setState(() => _uploadConfirmed = true);
      }
    } catch (_) {
      // ps_crud inaccessible (SDK change) — stream-based detection still active.
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _psSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final String text;
    late final Color color;

    if (_uploadConfirmed) {
      // Terminal state: upload is done regardless of current connectivity.
      // Must be checked first — going offline after a confirmed upload does
      // not invalidate the upload.
      icon = Icons.cloud_done_outlined;
      text = 'Uploaded to server';
      color = AppColors.accent;
    } else if (!_connected) {
      icon = Icons.cloud_queue_outlined;
      text = 'Saved locally \u2014 will upload when online';
      color = Colors.orange.shade700;
    } else {
      // Covers both: actively uploading, and pending (connected but PowerSync
      // hasn't started the cycle yet). Both correctly read as "in progress".
      icon = Icons.cloud_upload_outlined;
      text = 'Uploading to server...';
      color = AppColors.accentLight;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(text, style: AppTypography.textStyle(fontSize: 13, color: color)),
      ],
    );
  }
}
