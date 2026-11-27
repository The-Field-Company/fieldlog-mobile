import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fieldlog_mobile/app_typography.dart';
import 'package:powersync/powersync.dart' hide Column;
import '../theme/app_colors.dart';
import '../services/connectivity_service.dart';
import '../services/media_upload_queue_service.dart';
import '../services/powersync_service.dart';
import '../services/preferences_service.dart';
import '../utils/attachment_accepts.dart';

class SyncStatusWidget extends StatefulWidget {
  final void Function(SyncStateTransition transition)? onTransition;

  const SyncStatusWidget({super.key, this.onTransition});

  @override
  State<SyncStatusWidget> createState() => _SyncStatusWidgetState();
}

enum SyncStateTransition { wentOffline, backOnline, syncComplete }

class _SyncStatusWidgetState extends State<SyncStatusWidget> {
  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<SyncStatus>? _psSubscription;
  StreamSubscription<PendingMediaSummary>? _mediaSubscription;
  bool _connected = false;
  bool _psConnected = false;
  bool _uploading = false;
  bool? _previousConnected;
  PendingMediaSummary _media = MediaUploadQueueService.currentSummary;

  @override
  void initState() {
    super.initState();
    _listenToStatus();
  }

  void _listenToStatus() {
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

    _media = MediaUploadQueueService.currentSummary;
    _mediaSubscription = MediaUploadQueueService.summaryStream.listen((summary) {
      if (!mounted) return;
      setState(() => _media = summary);
    });

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

  void _openSyncSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _MediaSyncSheet(),
    );
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _psSubscription?.cancel();
    _mediaSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final String label;
    late final Color color;
    final bool showSpinner;
    double? progressFraction;

    if (!_connected) {
      icon = Icons.cloud_off_outlined;
      label = _media.pendingTotal > 0 ? 'Offline (${_media.pendingTotal})' : 'Offline';
      color = Colors.orange.shade700;
      showSpinner = false;
    } else if (_uploading) {
      icon = Icons.cloud_upload_outlined;
      label = 'Syncing';
      color = AppColors.accentLight;
      showSpinner = true;
    } else if (_media.isUploading || _media.queuedCount > 0) {
      icon = Icons.cloud_upload_outlined;
      if (_media.isUploading && _media.activeProgress != null) {
        final pct = (_media.activeProgress! * 100).round().clamp(0, 99);
        label = 'Media $pct%';
        progressFraction = _media.activeProgress!.clamp(0.0, 1.0);
      } else {
        label = 'Media (${_media.pendingTotal})';
      }
      color = AppColors.accentLight;
      showSpinner = true;
    } else if (_media.isPausedForWifi) {
      icon = Icons.wifi_outlined;
      label = 'Wi-Fi wait (${_media.pausedWifiCount})';
      color = Colors.orange.shade700;
      showSpinner = false;
    } else if (_media.failedCount > 0) {
      icon = Icons.error_outline;
      label = 'Media failed (${_media.failedCount})';
      color = AppColors.error;
      showSpinner = false;
    } else if (!_psConnected) {
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

    return InkWell(
      onTap: _openSyncSheet,
      borderRadius: BorderRadius.circular(12),
      child: Container(
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
                child: CircularProgressIndicator(
                  value: progressFraction,
                  strokeWidth: 1.5,
                  color: color,
                  backgroundColor: progressFraction != null
                      ? color.withValues(alpha: 0.22)
                      : null,
                ),
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
            const SizedBox(width: 2),
            Icon(Icons.expand_more, size: 13, color: color),
          ],
        ),
      ),
    );
  }
}

class _MediaSyncSheet extends StatelessWidget {
  const _MediaSyncSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: StreamBuilder<PendingMediaSummary>(
          initialData: MediaUploadQueueService.currentSummary,
          stream: MediaUploadQueueService.summaryStream,
          builder: (context, snapshot) {
            final summary = snapshot.data ?? const PendingMediaSummary();
            return ValueListenableBuilder<MediaUploadNetworkPolicy>(
              valueListenable: PreferencesService.mediaPolicyNotifier,
              builder: (context, policy, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: PreferencesService.lowCoverageModeNotifier,
                  builder: (context, lowCoverage, _) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Media uploads',
                          style: AppTypography.textStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _statusSubtitle(summary),
                          style: AppTypography.textStyle(
                            fontSize: 13,
                            color: summary.failedCount > 0
                                ? AppColors.error
                                : AppColors.textSecondary,
                          ),
                        ),
                        if (summary.isUploading && summary.activeProgress != null) ...[
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: summary.activeProgress,
                            color: AppColors.accent,
                            backgroundColor: AppColors.dividerColor,
                          ),
                          if (summary.activeBytesSent != null &&
                              summary.activeTotalBytes != null &&
                              summary.activeTotalBytes! > 0) ...[
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                '${formatFileSize(summary.activeBytesSent!)} / ${formatFileSize(summary.activeTotalBytes!)}',
                                style: AppTypography.textStyle(
                                  fontSize: 11,
                                  color: AppColors.textTertiary,
                                ).copyWith(
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ],
                        ],
                        if (summary.failedCount > 0) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => MediaUploadQueueService.retryFailed(),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Retry failed'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.accent,
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        SwitchListTile(
                          value: lowCoverage,
                          onChanged: (enabled) =>
                              PreferencesService.setLowCoverageMode(enabled),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: AppColors.accent,
                          title: Text(
                            'Low Coverage Mode',
                            style: AppTypography.textStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            'Smaller uploads for weak signal',
                            style: AppTypography.textStyle(
                              fontSize: 12,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Upload media on',
                          style: AppTypography.textStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        RadioGroup<MediaUploadNetworkPolicy>(
                          groupValue: policy,
                          onChanged: (next) {
                            if (next != null) {
                              PreferencesService.setMediaUploadPolicy(next);
                            }
                          },
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PolicyTile(
                                value: MediaUploadNetworkPolicy.anyNetwork,
                                title: 'Any network',
                              ),
                              _PolicyTile(
                                value: MediaUploadNetworkPolicy.wifiOnlyLarge,
                                title: 'Wi-Fi only for files over 5 MB',
                              ),
                              _PolicyTile(
                                value: MediaUploadNetworkPolicy.wifiOnlyAll,
                                title: 'Wi-Fi only',
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  static String _files(int count) => count == 1 ? '1 file' : '$count files';

  static String _statusSubtitle(PendingMediaSummary summary) {
    final failSuffix = summary.failedCount > 0
        ? ' · ${summary.failedCount} failed'
        : '';
    if (summary.isUploading && summary.activeFileName != null) {
      final pct = summary.activeProgress != null
          ? ' · ${(summary.activeProgress! * 100).round()}%'
          : '';
      final left = summary.pendingTotal > 1
          ? ' · ${summary.pendingTotal - 1} more'
          : '';
      return 'Uploading ${summary.activeFileName}$pct$left$failSuffix';
    }
    if (summary.isPausedForWifi) {
      return '${_files(summary.pausedWifiCount)} waiting for Wi-Fi$failSuffix';
    }
    if (summary.failedCount > 0) {
      return '${_files(summary.failedCount)} failed';
    }
    if (summary.pendingTotal > 0) {
      return '${_files(summary.pendingTotal)} queued';
    }
    return 'All media uploaded';
  }
}

class _PolicyTile extends StatelessWidget {
  final MediaUploadNetworkPolicy value;
  final String title;

  const _PolicyTile({
    required this.value,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<MediaUploadNetworkPolicy>(
      value: value,
      dense: true,
      contentPadding: EdgeInsets.zero,
      activeColor: AppColors.accent,
      title: Text(
        title,
        style: AppTypography.textStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
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
  StreamSubscription<PendingMediaSummary>? _mediaSubscription;
  bool _connected = false;
  bool _uploading = false;
  bool _uploadConfirmed = false;
  PendingMediaSummary _media = MediaUploadQueueService.currentSummary;

  @override
  void initState() {
    super.initState();

    _connected = ConnectivityService.isOnline;
    _connectivitySubscription = ConnectivityService.stream.listen((isOnline) {
      if (!mounted) return;
      setState(() => _connected = isOnline);
    });

    _media = MediaUploadQueueService.currentSummary;
    _mediaSubscription = MediaUploadQueueService.summaryStream.listen((summary) {
      if (!mounted) return;
      setState(() => _media = summary);
    });

    final db = PowerSyncService.getPowerSync();
    if (db != null) {
      _uploading = db.currentStatus.uploading;
      if (_connected && !_uploading) {
        _checkPendingCrud(db);
      }

      _psSubscription = db.statusStream.listen((status) {
        if (!mounted) return;
        final wasUploading = _uploading;
        setState(() {
          _uploading = status.uploading;
          if (wasUploading && !status.uploading && status.connected) {
            _uploadConfirmed = true;
          }
        });
      });
    }
  }

  Future<void> _checkPendingCrud(PowerSyncDatabase db) async {
    try {
      final rows = await db.getAll('SELECT id FROM ps_crud LIMIT 1');
      if (!mounted || _uploadConfirmed || _uploading) return;
      if (rows.isEmpty) {
        setState(() => _uploadConfirmed = true);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _psSubscription?.cancel();
    _mediaSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_uploadConfirmed &&
        _media.isUploading &&
        _media.activeTotalBytes != null &&
        _media.activeTotalBytes! > 0) {
      return _UploadProgressCard(summary: _media);
    }

    late final IconData icon;
    late final String text;
    late final Color color;

    if (_uploadConfirmed) {
      if (_media.isPausedForWifi) {
        icon = Icons.wifi_outlined;
        text = 'Observation synced \u2014 media waiting for Wi-Fi';
        color = Colors.orange.shade700;
      } else if (_media.pendingTotal > 0 && !_connected) {
        icon = Icons.cloud_queue_outlined;
        text = 'Observation synced \u2014 media waiting for connection';
        color = Colors.orange.shade700;
      } else if (_media.pendingTotal > 0) {
        icon = Icons.cloud_upload_outlined;
        text = 'Observation synced \u2014 uploading media in background';
        color = AppColors.accentLight;
      } else if (_media.failedCount > 0) {
        icon = Icons.error_outline;
        text = 'Observation synced \u2014 some media failed to upload';
        color = AppColors.error;
      } else {
        icon = Icons.cloud_done_outlined;
        text = 'Uploaded to server';
        color = AppColors.accent;
      }
    } else if (!_connected) {
      icon = Icons.cloud_queue_outlined;
      text = 'Saved locally \u2014 will upload when online';
      color = Colors.orange.shade700;
    } else {
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
        Flexible(
          child: Text(
            text,
            style: AppTypography.textStyle(fontSize: 13, color: color),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _UploadProgressCard extends StatelessWidget {
  final PendingMediaSummary summary;

  const _UploadProgressCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final fraction = (summary.activeProgress ?? 0.0).clamp(0.0, 1.0);
    final percent = (fraction * 100).round().clamp(0, 99);
    final label = summary.activeFileName != null && summary.activeFileName!.isNotEmpty
        ? 'Uploading ${summary.activeFileName}'
        : 'Uploading media';
    final sent = summary.activeBytesSent ?? 0;
    final total = summary.activeTotalBytes ?? 0;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.dividerColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cloud_upload_outlined,
                size: 15,
                color: AppColors.accent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$percent%',
                style: AppTypography.textStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent,
                ).copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: fraction),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              builder: (_, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 5,
                color: AppColors.accent,
                backgroundColor: AppColors.accent.withValues(alpha: 0.12),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${formatFileSize(sent)} / ${formatFileSize(total)}',
              style: AppTypography.textStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ).copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hairline progress bar pinned under app bars while a background media upload runs.
class UploadProgressBar extends StatelessWidget {
  const UploadProgressBar({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PendingMediaSummary>(
      initialData: MediaUploadQueueService.currentSummary,
      stream: MediaUploadQueueService.summaryStream,
      builder: (_, snapshot) {
        final summary = snapshot.data ?? const PendingMediaSummary();
        if (!summary.isUploading || summary.activeProgress == null) {
          return const SizedBox.shrink();
        }
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: summary.activeProgress!.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          builder: (_, value, _) => LinearProgressIndicator(
            value: value,
            minHeight: 2.5,
            color: AppColors.accentLight,
            backgroundColor: AppColors.accent.withValues(alpha: 0.1),
          ),
        );
      },
    );
  }
}
