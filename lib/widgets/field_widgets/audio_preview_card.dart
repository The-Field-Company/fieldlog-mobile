import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fieldlog_mobile/app_typography.dart';
import '../../services/audio_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/attachment_accepts.dart';

class AudioPreviewCard extends StatefulWidget {
  final String ownerId;
  final String filePath;
  final String displayName;
  final int? fileSize;
  final int initialDurationMs;
  final VoidCallback onRemove;
  final ValueChanged<String> onError;

  const AudioPreviewCard({
    super.key,
    required this.ownerId,
    required this.filePath,
    required this.displayName,
    required this.onRemove,
    required this.onError,
    this.fileSize,
    this.initialDurationMs = 0,
  });

  @override
  State<AudioPreviewCard> createState() => _AudioPreviewCardState();
}

class _AudioPreviewCardState extends State<AudioPreviewCard> {
  static const List<double> _waveformProfile = [
    0.28, 0.48, 0.72, 0.54, 0.92, 0.64, 0.36, 0.82,
    1.00, 0.68, 0.44, 0.76, 0.88, 0.52, 0.34, 0.70,
    0.96, 0.60, 0.42, 0.78, 0.56, 0.38, 0.62, 0.30,
  ];

  bool _isPlaying = false;
  bool _isPaused = false;
  bool _isBusy = false;
  int _positionMs = 0;
  int _durationMs = 0;
  Timer? _playbackTimer;

  @override
  void initState() {
    super.initState();
    _durationMs = widget.initialDurationMs;
  }

  @override
  void didUpdateWidget(AudioPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _stopPlayback();
      _durationMs = widget.initialDurationMs;
    }
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    if (_isPlaying || _isPaused) {
      AudioService.stopPlayback(ownerId: widget.ownerId);
    }
    super.dispose();
  }

  void _resetPlaybackState() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    if (!mounted) return;
    setState(() {
      _isPlaying = false;
      _isPaused = false;
      _positionMs = 0;
    });
  }

  Future<void> _stopPlayback() async {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    if (_isPlaying || _isPaused) {
      await AudioService.stopPlayback(ownerId: widget.ownerId);
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _isPaused = false;
          _positionMs = 0;
        });
      }
    }
  }

  void _startPlaybackPolling() {
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 250), (
      _,
    ) async {
      if (!mounted || !_isPlaying) return;
      final status = await AudioService.getPlaybackStatus(
        ownerId: widget.ownerId,
      );
      if (!mounted || !_isPlaying) return;
      setState(() {
        _positionMs = status.positionMs;
        if (status.durationMs > 0) _durationMs = status.durationMs;
      });
    });
  }

  Future<void> _togglePlayback() async {
    if (_isBusy) return;
    _isBusy = true;
    try {
      if (_isPlaying) {
        try {
          await AudioService.pausePlayback(ownerId: widget.ownerId);
        } catch (_) {}
        _playbackTimer?.cancel();
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _isPaused = true;
          });
        }
        return;
      }

      if (_isPaused) {
        try {
          await AudioService.resumePlayback(ownerId: widget.ownerId);
          if (mounted) {
            setState(() {
              _isPlaying = true;
              _isPaused = false;
            });
            _startPlaybackPolling();
          }
          return;
        } catch (_) {
          // Fall through to fresh playback start.
        }
      }

      try {
        final durationMs = await AudioService.startPlayback(
          path: widget.filePath,
          ownerId: widget.ownerId,
          onComplete: _resetPlaybackState,
          onInterrupted: _resetPlaybackState,
        );
        if (!mounted) {
          await AudioService.stopPlayback(ownerId: widget.ownerId);
          return;
        }
        setState(() {
          _isPlaying = true;
          _isPaused = false;
          _positionMs = 0;
          if (durationMs > 0) _durationMs = durationMs;
        });
        _startPlaybackPolling();
      } on StateError catch (e) {
        widget.onError(e.message);
      } catch (_) {
        widget.onError('Could not play audio file.');
      }
    } finally {
      _isBusy = false;
    }
  }

  Future<void> _handleRemove() async {
    await _stopPlayback();
    widget.onRemove();
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_durationMs > 0)
        ? (_positionMs / _durationMs).clamp(0.0, 1.0)
        : 0.0;
    final subtitleParts = <String>[];
    if (_durationMs > 0) {
      final pos = _formatDuration(Duration(milliseconds: _positionMs));
      final dur = _formatDuration(Duration(milliseconds: _durationMs));
      subtitleParts.add(_isPlaying || _isPaused ? '$pos / $dur' : dur);
    }
    if (widget.fileSize != null && widget.fileSize! > 0) {
      subtitleParts.add(formatFileSize(widget.fileSize!));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isPlaying
              ? AppColors.accent.withValues(alpha: 0.35)
              : AppColors.borderColor,
        ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _togglePlayback,
            customBorder: const CircleBorder(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _isPlaying
                    ? AppColors.accent
                    : AppColors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: _isPlaying ? Colors.white : AppColors.accent,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 16,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: List.generate(_waveformProfile.length, (index) {
                      final barThreshold =
                          (index + 1) / _waveformProfile.length;
                      final isPlayed = progress > 0 && progress >= barThreshold;
                      final barHeight = 3.0 + (_waveformProfile[index] * 13.0);
                      return Container(
                        width: 2.5,
                        height: barHeight,
                        decoration: BoxDecoration(
                          color: isPlayed
                              ? AppColors.accent
                              : AppColors.accent.withValues(
                                  alpha: _isPlaying ? 0.28 : 0.2,
                                ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }),
                  ),
                ),
                if (subtitleParts.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    subtitleParts.join(' · '),
                    style: AppTypography.textStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: _handleRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppColors.textSecondary,
            ),
            tooltip: 'Remove audio',
          ),
        ],
      ),
    );
  }
}
