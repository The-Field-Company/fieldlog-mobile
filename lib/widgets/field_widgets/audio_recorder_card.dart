import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fieldlog_mobile/app_typography.dart';
import '../../services/audio_service.dart';
import '../../theme/app_colors.dart';

class AudioRecorderCard extends StatefulWidget {
  final String ownerId;
  final ValueChanged<RecordedAudio> onSaved;
  final VoidCallback onDiscarded;
  final ValueChanged<String> onError;

  const AudioRecorderCard({
    super.key,
    required this.ownerId,
    required this.onSaved,
    required this.onDiscarded,
    required this.onError,
  });

  @override
  State<AudioRecorderCard> createState() => _AudioRecorderCardState();
}

class _AudioRecorderCardState extends State<AudioRecorderCard>
    with SingleTickerProviderStateMixin {
  static const int _waveformBarCount = 24;

  bool _isPaused = false;
  bool _isBusy = false;
  bool _finished = false;
  Duration _elapsed = Duration.zero;
  Duration _accumulated = Duration.zero;
  DateTime? _segmentStartedAt;
  Timer? _elapsedTimer;
  Timer? _amplitudeTimer;
  final List<double> _waveformLevels = List<double>.filled(
    _waveformBarCount,
    0.08,
    growable: true,
  );
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.35,
      upperBound: 1.0,
    );
    _segmentStartedAt = DateTime.now();
    _startTimers();
  }

  @override
  void dispose() {
    _stopTimers();
    _pulseController.dispose();
    if (!_finished) {
      AudioService.cancelRecording(ownerId: widget.ownerId);
    }
    super.dispose();
  }

  void _startTimers() {
    _elapsedTimer?.cancel();
    _amplitudeTimer?.cancel();
    _pulseController.repeat(reverse: true);

    _elapsedTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || _isPaused || _finished) return;
      final startedAt = _segmentStartedAt;
      if (startedAt == null) return;
      setState(() {
        _elapsed = _accumulated + DateTime.now().difference(startedAt);
      });
    });

    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 120), (
      _,
    ) async {
      if (!mounted || _isPaused || _finished) return;
      final level = await AudioService.getRecordingAmplitude(
        ownerId: widget.ownerId,
      );
      if (!mounted || _isPaused || _finished) return;
      setState(() {
        if (_waveformLevels.length >= _waveformBarCount) {
          _waveformLevels.removeAt(0);
        }
        _waveformLevels.add(level.clamp(0.08, 1.0));
      });
    });
  }

  void _stopTimers() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    _pulseController.stop();
    _pulseController.value = 1.0;
  }

  Future<void> _togglePause() async {
    if (_isBusy || _finished) return;
    _isBusy = true;
    try {
      if (_isPaused) {
        try {
          await AudioService.resumeRecording(ownerId: widget.ownerId);
        } catch (_) {
          widget.onError('Could not resume recording.');
          return;
        }
        if (!mounted) return;
        _segmentStartedAt = DateTime.now();
        setState(() => _isPaused = false);
        _startTimers();
      } else {
        try {
          await AudioService.pauseRecording(ownerId: widget.ownerId);
        } catch (_) {
          widget.onError('Could not pause recording.');
          return;
        }
        if (!mounted) return;
        if (_segmentStartedAt != null) {
          _accumulated += DateTime.now().difference(_segmentStartedAt!);
          _segmentStartedAt = null;
        }
        _stopTimers();
        setState(() {
          _isPaused = true;
          _elapsed = _accumulated;
        });
      }
    } finally {
      _isBusy = false;
    }
  }

  Future<void> _save() async {
    if (_isBusy || _finished) return;
    _isBusy = true;
    _finished = true;
    _stopTimers();

    RecordedAudio? recorded;
    try {
      recorded = await AudioService.stopRecording(ownerId: widget.ownerId);
    } catch (_) {
      _isBusy = false;
      if (mounted) {
        widget.onError('Could not save recording.');
        widget.onDiscarded();
      }
      return;
    }

    // Delete orphaned recording if the widget was unmounted while stopping.
    if (!mounted) {
      if (recorded != null) {
        try {
          final file = File(recorded.path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      return;
    }

    _isBusy = false;
    if (recorded == null || recorded.size <= 0) {
      widget.onError('Recording was too short. Please try again.');
      widget.onDiscarded();
      return;
    }

    widget.onSaved(recorded);
  }

  Future<void> _discard() async {
    if (_isBusy || _finished) return;
    _isBusy = true;
    _finished = true;
    _stopTimers();
    await AudioService.cancelRecording(ownerId: widget.ownerId);
    _isBusy = false;
    if (mounted) widget.onDiscarded();
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isPaused = _isPaused;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: isPaused ? 0.02 : 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPaused
              ? AppColors.borderColor
              : AppColors.accent.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (isPaused)
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppColors.textTertiary,
                    shape: BoxShape.circle,
                  ),
                )
              else
                FadeTransition(
                  opacity: _pulseController,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.accentLight,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(_elapsed),
                style: AppTypography.textStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isPaused
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (isPaused) ...[
                const SizedBox(width: 6),
                Text(
                  'Paused',
                  style: AppTypography.textStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 22,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: List.generate(_waveformBarCount, (index) {
                      final level = index < _waveformLevels.length
                          ? _waveformLevels[index]
                          : 0.08;
                      final barHeight = 3.0 + (level * 18.0);
                      final isRecent = index >= _waveformBarCount - 6;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 110),
                        width: 2.5,
                        height: barHeight,
                        decoration: BoxDecoration(
                          color: isPaused
                              ? AppColors.borderColor
                              : (isRecent
                                    ? AppColors.accent
                                    : AppColors.accentLight.withValues(
                                        alpha: 0.45,
                                      )),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                height: 34,
                child: TextButton.icon(
                  onPressed: _discard,
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('Discard'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: AppTypography.textStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 34,
                child: OutlinedButton.icon(
                  onPressed: _togglePause,
                  icon: Icon(
                    isPaused ? Icons.mic_none_rounded : Icons.pause_rounded,
                    size: 16,
                  ),
                  label: Text(isPaused ? 'Resume' : 'Pause'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: BorderSide(
                      color: AppColors.accent.withValues(alpha: 0.4),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: AppTypography.textStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 34,
                child: ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Save'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: AppTypography.textStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
