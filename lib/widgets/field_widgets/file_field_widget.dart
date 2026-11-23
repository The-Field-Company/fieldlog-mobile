import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fieldlog_mobile/app_typography.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../services/audio_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/attachment_accepts.dart';

class FileFieldWidget extends StatefulWidget {
  final String label;
  final bool isRequired;
  final String? accepts;
  final Map<String, dynamic>? initialValue;
  final ValueChanged<Map<String, dynamic>?> onChanged;

  const FileFieldWidget({
    super.key,
    required this.label,
    required this.onChanged,
    this.isRequired = false,
    this.accepts,
    this.initialValue,
  });

  @override
  State<FileFieldWidget> createState() => _FileFieldWidgetState();
}

class _FileFieldWidgetState extends State<FileFieldWidget>
    with SingleTickerProviderStateMixin {
  static const int _waveformBarCount = 24;

  File? _file;
  String? _originalName;
  int? _fileSize;
  bool _isAudio = false;

  // In-app recording state
  bool _isRecording = false;
  bool _isRecordingPaused = false;
  String? _recordingFileId;
  Duration _recordingElapsed = Duration.zero;
  Duration _recordingAccumulated = Duration.zero;
  DateTime? _recordingSegmentStartedAt;
  Timer? _recordingTimer;
  Timer? _amplitudeTimer;
  final List<double> _waveformLevels = List<double>.filled(
    _waveformBarCount,
    0.08,
    growable: true,
  );
  late final AnimationController _pulseController;

  // Audio playback preview state
  bool _isPlaying = false;
  bool _isPaused = false;
  int _positionMs = 0;
  int _durationMs = 0;
  Timer? _playbackTimer;

  final _picker = ImagePicker();

  Set<AttachmentKind> get _acceptedKinds => parseAcceptedKinds(widget.accepts);
  bool get _allowsImage => _acceptedKinds.contains(AttachmentKind.image);
  bool get _allowsAudio => _acceptedKinds.contains(AttachmentKind.audio);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.35,
      upperBound: 1.0,
    );
    _restoreInitialValue();
  }

  void _restoreInitialValue() {
    final initial = widget.initialValue;
    if (initial == null) return;
    final path = initial['file_path'] as String?;
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (!file.existsSync()) return;
    _file = file;
    _originalName =
        (initial['original_name'] as String?) ??
        (initial['file_name'] as String?) ??
        path.split('/').last;
    _fileSize = (initial['file_size'] as num?)?.toInt();
    _isAudio = isAudioPath(path);
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _amplitudeTimer?.cancel();
    _playbackTimer?.cancel();
    _pulseController.dispose();
    if (_isRecording) {
      AudioService.cancelRecording();
    }
    if (_isPlaying || _isPaused) {
      AudioService.setOnPlaybackComplete(null);
      AudioService.stopPlayback();
    }
    super.dispose();
  }

  void _showSnackBar(
    String message, {
    Color? backgroundColor,
    SnackBarAction? action,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        action: action,
      ),
    );
  }

  Future<void> _deleteLocalFile(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _pickImage(ImageSource source) async {
    await _stopPlayback();

    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1080,
    );
    if (picked == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final ext = extensionOf(picked.path);

    if (!imageExtensions.contains(ext)) {
      _showSnackBar(
        'Unsupported file type (.$ext). Please choose a JPG, PNG, WEBP, or HEIC image.',
      );
      return;
    }

    final id = const Uuid().v4();
    final newPath = '${dir.path}/$id.$ext';
    final saved = await File(picked.path).copy(newPath);

    final bytes = await saved.length();
    if (bytes > maxImageBytes) {
      _showSnackBar(
        'File too large (max ${maxMbForKind(AttachmentKind.image)} MB).',
      );
      await _deleteLocalFile(saved);
      return;
    }
    final mb = bytes / (1024 * 1024);
    if (mb > 2) {
      _showSnackBar(
        'Large file (${mb.toStringAsFixed(1)} MB) — upload may be slow',
        backgroundColor: Colors.orange.shade700,
      );
    }

    final previous = _file;
    final originalName = picked.name.isNotEmpty ? picked.name : '$id.$ext';
    if (!mounted) {
      await _deleteLocalFile(saved);
      return;
    }

    setState(() {
      _file = saved;
      _originalName = originalName;
      _fileSize = bytes;
      _isAudio = false;
      _positionMs = 0;
      _durationMs = 0;
    });
    if (previous != null && previous.path != saved.path) {
      await _deleteLocalFile(previous);
    }

    widget.onChanged({
      'file_path': saved.path,
      'file_name': '$id.$ext',
      'original_name': originalName,
      'file_size': bytes,
    });
  }

  Future<void> _pickAudioFile() async {
    await _stopPlayback();

    final dir = await getApplicationDocumentsDirectory();
    final id = const Uuid().v4();

    PickedAudioFile? picked;
    try {
      picked = await AudioService.pickAudioFile(
        destinationBasePath: '${dir.path}/$id',
      );
    } catch (_) {
      _showSnackBar('Could not open audio picker.');
      return;
    }
    if (picked == null) return;

    final saved = File(picked.path);
    final ext = extensionOf(picked.path).isNotEmpty
        ? extensionOf(picked.path)
        : extensionOf(picked.name);

    if (kindForExtension(ext) != AttachmentKind.audio) {
      _showSnackBar(
        'Unsupported audio format${ext.isNotEmpty ? ' (.$ext)' : ''}. '
        'Supported: M4A, MP3, WAV, OGG, OPUS, WEBM, AAC, FLAC.',
      );
      await _deleteLocalFile(saved);
      return;
    }

    final bytes = picked.size > 0 ? picked.size : await saved.length();
    if (bytes == 0) {
      _showSnackBar('Selected audio file is empty.');
      await _deleteLocalFile(saved);
      return;
    }
    if (bytes > maxAudioBytes) {
      _showSnackBar(
        'Audio file too large (max ${maxMbForKind(AttachmentKind.audio)} MB).',
      );
      await _deleteLocalFile(saved);
      return;
    }
    final mb = bytes / (1024 * 1024);
    if (mb > 10) {
      _showSnackBar(
        'Large audio file (${mb.toStringAsFixed(1)} MB) — upload may be slow',
        backgroundColor: Colors.orange.shade700,
      );
    }

    final previous = _file;
    if (!mounted) {
      await _deleteLocalFile(saved);
      return;
    }

    setState(() {
      _file = saved;
      _originalName = picked!.name;
      _fileSize = bytes;
      _isAudio = true;
      _positionMs = 0;
      _durationMs = 0;
    });
    if (previous != null && previous.path != saved.path) {
      await _deleteLocalFile(previous);
    }

    widget.onChanged({
      'file_path': saved.path,
      'file_name': '$id.$ext',
      'original_name': picked.name,
      'file_size': bytes,
    });
  }

  Future<void> _startRecording() async {
    await _stopPlayback();

    final granted = await AudioService.hasMicPermission();
    if (!granted) {
      _showSnackBar(
        'Microphone permission is required to record audio.',
        action: SnackBarAction(
          label: 'Settings',
          onPressed: AudioService.openAppSettings,
        ),
      );
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final id = const Uuid().v4();
    final path = '${dir.path}/$id.m4a';

    try {
      await AudioService.startRecording(path: path);
    } catch (_) {
      _showSnackBar('Could not start recording.');
      return;
    }

    if (!mounted) {
      await AudioService.cancelRecording();
      return;
    }

    _startRecordingTimers();
    setState(() {
      _isRecording = true;
      _isRecordingPaused = false;
      _recordingFileId = id;
      _recordingElapsed = Duration.zero;
      _recordingAccumulated = Duration.zero;
      _recordingSegmentStartedAt = DateTime.now();
      _waveformLevels
        ..clear()
        ..addAll(List<double>.filled(_waveformBarCount, 0.08));
    });
  }

  void _startRecordingTimers() {
    _recordingTimer?.cancel();
    _amplitudeTimer?.cancel();
    _pulseController.repeat(reverse: true);

    _recordingTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || !_isRecording || _isRecordingPaused) return;
      final startedAt = _recordingSegmentStartedAt;
      if (startedAt == null) return;
      setState(() {
        _recordingElapsed =
            _recordingAccumulated + DateTime.now().difference(startedAt);
      });
    });

    _amplitudeTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) async {
        if (!mounted || !_isRecording || _isRecordingPaused) return;
        final level = await AudioService.getRecordingAmplitude();
        if (!mounted || !_isRecording || _isRecordingPaused) return;
        setState(() {
          if (_waveformLevels.length >= _waveformBarCount) {
            _waveformLevels.removeAt(0);
          }
          _waveformLevels.add(level.clamp(0.08, 1.0));
        });
      },
    );
  }

  Future<void> _toggleRecordingPause() async {
    if (!_isRecording) return;
    if (_isRecordingPaused) {
      try {
        await AudioService.resumeRecording();
      } catch (_) {
        _showSnackBar('Could not resume recording.');
        return;
      }
      if (!mounted) return;
      _recordingSegmentStartedAt = DateTime.now();
      setState(() => _isRecordingPaused = false);
      _startRecordingTimers();
    } else {
      try {
        await AudioService.pauseRecording();
      } catch (_) {
        _showSnackBar('Could not pause recording.');
        return;
      }
      if (!mounted) return;
      if (_recordingSegmentStartedAt != null) {
        _recordingAccumulated += DateTime.now().difference(
          _recordingSegmentStartedAt!,
        );
        _recordingSegmentStartedAt = null;
      }
      _stopRecordingTimers();
      setState(() {
        _isRecordingPaused = true;
        _recordingElapsed = _recordingAccumulated;
      });
    }
  }

  void _stopRecordingTimers() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    _pulseController.stop();
    _pulseController.value = 1.0;
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    _stopRecordingTimers();

    final fileId = _recordingFileId ?? const Uuid().v4();
    RecordedAudio? recorded;
    try {
      recorded = await AudioService.stopRecording();
    } catch (_) {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _isRecordingPaused = false;
          _recordingFileId = null;
        });
      }
      _showSnackBar('Could not save recording.');
      return;
    }

    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isRecordingPaused = false;
      _recordingFileId = null;
      _recordingAccumulated = Duration.zero;
      _recordingSegmentStartedAt = null;
    });

    if (recorded == null || recorded.size <= 0) {
      _showSnackBar('Recording was too short. Please try again.');
      return;
    }

    final saved = File(recorded.path);
    if (recorded.size > maxAudioBytes) {
      await _deleteLocalFile(saved);
      _showSnackBar(
        'Recording too large (max ${maxMbForKind(AttachmentKind.audio)} MB).',
      );
      return;
    }

    final now = DateTime.now();
    final timestamp =
        '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final displayName = 'recording_$timestamp.m4a';

    final previous = _file;
    setState(() {
      _file = saved;
      _originalName = displayName;
      _fileSize = recorded!.size;
      _isAudio = true;
      _positionMs = 0;
      _durationMs = recorded.durationMs;
    });
    if (previous != null && previous.path != saved.path) {
      await _deleteLocalFile(previous);
    }

    widget.onChanged({
      'file_path': saved.path,
      'file_name': '$fileId.m4a',
      'original_name': displayName,
      'file_size': recorded.size,
    });
  }

  Future<void> _cancelRecording() async {
    _stopRecordingTimers();
    await AudioService.cancelRecording();
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isRecordingPaused = false;
      _recordingFileId = null;
      _recordingElapsed = Duration.zero;
      _recordingAccumulated = Duration.zero;
      _recordingSegmentStartedAt = null;
    });
  }

  Future<void> _togglePlayback() async {
    final file = _file;
    if (file == null || !_isAudio) return;

    if (_isPlaying) {
      try {
        await AudioService.pausePlayback();
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
        await AudioService.resumePlayback();
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

    AudioService.setOnPlaybackComplete(() {
      _playbackTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _isPaused = false;
        _positionMs = 0;
      });
    });

    try {
      final durationMs = await AudioService.startPlayback(path: file.path);
      if (!mounted) return;
      setState(() {
        _isPlaying = true;
        _isPaused = false;
        _positionMs = 0;
        if (durationMs > 0) _durationMs = durationMs;
      });
      _startPlaybackPolling();
    } catch (_) {
      _showSnackBar('Could not play audio file.');
    }
  }

  void _startPlaybackPolling() {
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 250), (
      _,
    ) async {
      if (!mounted || !_isPlaying) return;
      final status = await AudioService.getPlaybackStatus();
      if (!mounted) return;
      setState(() {
        _positionMs = status.positionMs;
        if (status.durationMs > 0) _durationMs = status.durationMs;
        if (!status.isPlaying && _isPlaying) {
          _isPlaying = false;
          _isPaused = false;
          _positionMs = 0;
          _playbackTimer?.cancel();
        }
      });
    });
  }

  Future<void> _stopPlayback() async {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    if (_isPlaying || _isPaused) {
      AudioService.setOnPlaybackComplete(null);
      await AudioService.stopPlayback();
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _isPaused = false;
          _positionMs = 0;
        });
      }
    }
  }

  Widget _buildSheetOption({
    required BuildContext sheetContext,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        Navigator.pop(sheetContext);
        onTap();
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.textStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.textStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _showPicker() {
    if (_isRecording) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.primaryBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (_allowsImage) ...[
                _buildSheetOption(
                  sheetContext: ctx,
                  icon: Icons.photo_camera_outlined,
                  title: 'Camera',
                  subtitle: 'Take a new photo',
                  onTap: () => _pickImage(ImageSource.camera),
                ),
                _buildSheetOption(
                  sheetContext: ctx,
                  icon: Icons.photo_library_outlined,
                  title: 'Photo Library',
                  subtitle: 'JPG, PNG, WEBP, HEIC up to 10 MB',
                  onTap: () => _pickImage(ImageSource.gallery),
                ),
              ],
              if (_allowsAudio) ...[
                _buildSheetOption(
                  sheetContext: ctx,
                  icon: Icons.mic_none_rounded,
                  title: 'Record Audio',
                  subtitle: 'Capture a clip with your microphone',
                  onTap: _startRecording,
                ),
                _buildSheetOption(
                  sheetContext: ctx,
                  icon: Icons.audio_file_outlined,
                  title: 'Choose Audio File',
                  subtitle: 'M4A, MP3, WAV, OGG, FLAC up to 50 MB',
                  onTap: _pickAudioFile,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _remove() async {
    await _stopPlayback();
    final current = _file;
    setState(() {
      _file = null;
      _originalName = null;
      _fileSize = null;
      _isAudio = false;
      _positionMs = 0;
      _durationMs = 0;
    });
    widget.onChanged(null);
    await _deleteLocalFile(current);
  }

  IconData get _emptyIcon {
    if (_allowsImage && _allowsAudio) return Icons.add_rounded;
    if (_allowsAudio) return Icons.mic_none_rounded;
    return Icons.photo_camera_outlined;
  }

  String get _emptyTitle {
    if (_allowsImage && _allowsAudio) return 'Add photo or audio';
    if (_allowsAudio) return 'Add audio';
    return 'Add photo';
  }

  String get _emptySubtitle {
    if (_allowsImage && _allowsAudio) {
      return 'Take a photo, record audio, or choose a file';
    }
    if (_allowsAudio) {
      return 'Record live or choose an audio file · up to 50 MB';
    }
    return 'Take a photo or choose from library · up to 10 MB';
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildEmptyBox() {
    return InkWell(
      onTap: _showPicker,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.025),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_emptyIcon, size: 20, color: AppColors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _emptyTitle,
                    style: AppTypography.textStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _emptySubtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingBox() {
    final isPaused = _isRecordingPaused;
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
                _formatDuration(_recordingElapsed),
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
                  onPressed: _cancelRecording,
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
                  onPressed: _toggleRecordingPause,
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
                  onPressed: _stopRecording,
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

  Widget _buildAudioPreview() {
    final progress = (_durationMs > 0)
        ? (_positionMs / _durationMs).clamp(0.0, 1.0)
        : 0.0;
    final subtitleParts = <String>[];
    if (_durationMs > 0) {
      final pos = _formatDuration(Duration(milliseconds: _positionMs));
      final dur = _formatDuration(Duration(milliseconds: _durationMs));
      subtitleParts.add(_isPlaying || _isPaused ? '$pos / $dur' : dur);
    }
    if (_fileSize != null && _fileSize! > 0) {
      subtitleParts.add(formatFileSize(_fileSize!));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _togglePlayback,
            customBorder: const CircleBorder(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _isPlaying
                    ? AppColors.accent
                    : AppColors.accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: _isPlaying ? Colors.white : AppColors.accent,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _originalName ?? 'Audio recording',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 2.5,
                    backgroundColor: AppColors.dividerColor,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.accent,
                    ),
                  ),
                ),
                if (subtitleParts.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitleParts.join(' · '),
                    style: AppTypography.textStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: _remove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppColors.textTertiary,
            ),
            tooltip: 'Remove audio',
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            _file!,
            width: double.infinity,
            height: 180,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: GestureDetector(
            onTap: _remove,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: FormField<File>(
        validator: (value) {
          if (_isRecording) {
            return 'Save or discard recording before submitting';
          }
          if (widget.isRequired && _file == null) {
            return '${widget.label} is required';
          }
          return null;
        },
        builder: (state) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.label + (widget.isRequired ? ' *' : ''),
                style: AppTypography.textStyle(
                  fontSize: 16,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              if (_isRecording)
                _buildRecordingBox()
              else if (_file == null)
                _buildEmptyBox()
              else if (_isAudio)
                _buildAudioPreview()
              else
                _buildImagePreview(),
              if (state.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    state.errorText!,
                    style: AppTypography.textStyle(
                      fontSize: 12,
                      color: AppColors.error,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
