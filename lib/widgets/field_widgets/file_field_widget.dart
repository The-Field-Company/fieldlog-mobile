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
import 'audio_preview_card.dart';
import 'audio_recorder_card.dart';

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
    with AutomaticKeepAliveClientMixin {
  final _formFieldKey = GlobalKey<FormFieldState<File>>();
  final String _ownerId = const Uuid().v4();
  final _picker = ImagePicker();

  File? _file;
  String? _originalName;
  int? _fileSize;
  int _audioDurationMs = 0;
  bool _isAudio = false;
  bool _isRecording = false;
  bool _isBusy = false;
  String? _recordingFileId;

  Set<AttachmentKind> get _acceptedKinds => parseAcceptedKinds(widget.accepts);
  bool get _allowsImage => _acceptedKinds.contains(AttachmentKind.image);
  bool get _allowsAudio => _acceptedKinds.contains(AttachmentKind.audio);

  @override
  bool get wantKeepAlive => _isRecording || _file != null;

  @override
  void initState() {
    super.initState();
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

  void _clearFieldErrorIfValid(File? file) {
    final fieldState = _formFieldKey.currentState;
    if (fieldState == null) return;
    fieldState.didChange(file);
    if (fieldState.hasError) {
      fieldState.validate();
    }
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
    if (_isBusy) return;
    _isBusy = true;
    try {
      await AudioService.stopPlayback(ownerId: _ownerId);

      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2048,
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
        _audioDurationMs = 0;
        _isAudio = false;
      });
      updateKeepAlive();
      if (previous != null && previous.path != saved.path) {
        await _deleteLocalFile(previous);
      }

      widget.onChanged({
        'file_path': saved.path,
        'file_name': '$id.$ext',
        'original_name': originalName,
        'file_size': bytes,
      });
    } finally {
      _isBusy = false;
    }
  }

  Future<void> _pickAudioFile() async {
    if (_isBusy) return;
    _isBusy = true;
    try {
      await AudioService.stopPlayback(ownerId: _ownerId);

      final dir = await getApplicationDocumentsDirectory();
      final id = const Uuid().v4();

      PickedAudioFile? picked;
      try {
        picked = await AudioService.pickAudioFile(
          destinationBasePath: '${dir.path}/$id',
        );
      } on AudioPickException catch (e) {
        _showSnackBar(e.message);
        return;
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
        _audioDurationMs = 0;
        _isAudio = true;
      });
      updateKeepAlive();
      if (previous != null && previous.path != saved.path) {
        await _deleteLocalFile(previous);
      }

      widget.onChanged({
        'file_path': saved.path,
        'file_name': '$id.$ext',
        'original_name': picked.name,
        'file_size': bytes,
      });
    } finally {
      _isBusy = false;
    }
  }

  Future<void> _startRecording() async {
    if (_isBusy || _isRecording) return;
    _isBusy = true;
    try {
      await AudioService.stopPlayback(ownerId: _ownerId);

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
        await AudioService.startRecording(path: path, ownerId: _ownerId);
      } on StateError {
        _showSnackBar('Finish or discard the other active recording first.');
        return;
      } catch (_) {
        _showSnackBar('Could not start recording.');
        return;
      }

      if (!mounted) {
        await AudioService.cancelRecording(ownerId: _ownerId);
        return;
      }

      setState(() {
        _isRecording = true;
        _recordingFileId = id;
      });
      updateKeepAlive();
    } finally {
      _isBusy = false;
    }
  }

  Future<void> _handleRecordingSaved(RecordedAudio recorded) async {
    final fileId = _recordingFileId ?? const Uuid().v4();
    final saved = File(recorded.path);

    if (recorded.size > maxAudioBytes) {
      await _deleteLocalFile(saved);
      if (mounted) {
        setState(() {
          _isRecording = false;
          _recordingFileId = null;
        });
        updateKeepAlive();
        _showSnackBar(
          'Recording too large (max ${maxMbForKind(AttachmentKind.audio)} MB).',
        );
      }
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
      _isRecording = false;
      _recordingFileId = null;
      _file = saved;
      _originalName = displayName;
      _fileSize = recorded.size;
      _audioDurationMs = recorded.durationMs;
      _isAudio = true;
    });
    _clearFieldErrorIfValid(saved);
    updateKeepAlive();
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

  void _handleRecordingDiscarded() {
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _recordingFileId = null;
    });
    _clearFieldErrorIfValid(_file);
    updateKeepAlive();
  }

  Future<void> _remove() async {
    final current = _file;
    setState(() {
      _file = null;
      _originalName = null;
      _fileSize = null;
      _audioDurationMs = 0;
      _isAudio = false;
    });
    updateKeepAlive();
    widget.onChanged(null);
    await _deleteLocalFile(current);
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
    if (_isRecording || _isBusy) return;
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
    super.build(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: FormField<File>(
        key: _formFieldKey,
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
                AudioRecorderCard(
                  ownerId: _ownerId,
                  onSaved: _handleRecordingSaved,
                  onDiscarded: _handleRecordingDiscarded,
                  onError: _showSnackBar,
                )
              else if (_file == null)
                _buildEmptyBox()
              else if (_isAudio)
                AudioPreviewCard(
                  ownerId: _ownerId,
                  filePath: _file!.path,
                  displayName: _originalName ?? 'Audio recording',
                  fileSize: _fileSize,
                  initialDurationMs: _audioDurationMs,
                  onRemove: _remove,
                  onError: _showSnackBar,
                )
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
