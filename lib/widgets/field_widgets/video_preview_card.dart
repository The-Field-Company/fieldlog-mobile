import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:fieldlog_mobile/app_typography.dart';
import 'package:video_player/video_player.dart';
import '../../services/audio_service.dart';
import '../../services/video_thumbnail_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/attachment_accepts.dart';

/// Visual 180px frame preview card for an attached video file, matching the
/// photo preview footprint; opens a modal player on tap so scrolling forms
/// never allocate native video decoders eagerly.
class VideoPreviewCard extends StatefulWidget {
  final String filePath;
  final String displayName;
  final int? fileSize;
  final VoidCallback onRemove;

  const VideoPreviewCard({
    super.key,
    required this.filePath,
    required this.displayName,
    required this.onRemove,
    this.fileSize,
  });

  @override
  State<VideoPreviewCard> createState() => _VideoPreviewCardState();
}

class _VideoPreviewCardState extends State<VideoPreviewCard> {
  Uint8List? _thumbnailBytes;
  int? _durationMs;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(VideoPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _thumbnailBytes = null;
      _durationMs = null;
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    final requestedPath = widget.filePath;
    final data = await VideoThumbnailService.load(requestedPath);
    if (!mounted || widget.filePath != requestedPath || data == null) return;
    setState(() {
      _thumbnailBytes = data.bytes;
      _durationMs = data.durationMs;
    });
  }

  Future<void> _openPlayer(BuildContext context) async {
    await AudioService.stopActivePlayback();
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => _VideoPlayerDialog(
        filePath: widget.filePath,
        displayName: widget.displayName,
      ),
    );
  }

  String _formatDurationMs(int ms) {
    final total = (ms ~/ 1000).clamp(0, 359999);
    final minutes = total ~/ 60;
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final sizeText = widget.fileSize != null
        ? formatFileSize(widget.fileSize!)
        : null;
    final subtitle = sizeText != null ? 'Video · $sizeText' : 'Video';
    final durationLabel = _durationMs != null && _durationMs! > 0
        ? _formatDurationMs(_durationMs!)
        : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: double.infinity,
        height: 180,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_thumbnailBytes != null)
              Image.memory(
                _thumbnailBytes!,
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              )
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1B3126), Color(0xFF0E1D15)],
                  ),
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.45, 1.0],
                  colors: [
                    Color(0x22000000),
                    Color(0x18000000),
                    Color(0xB8000000),
                  ],
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _openPlayer(context),
                child: Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E1D15).withValues(alpha: 0.68),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.9),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ),
            ),
            if (durationLabel != null)
              Positioned(
                top: 8,
                left: 8,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      durationLabel,
                      style: AppTypography.textStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 0,
              right: 0,
              child: Tooltip(
                message: 'Remove video',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onRemove,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
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
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: IgnorePointer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.textStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: AppTypography.textStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPlayerDialog extends StatefulWidget {
  final String filePath;
  final String displayName;

  const _VideoPlayerDialog({
    required this.filePath,
    required this.displayName,
  });

  @override
  State<_VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<_VideoPlayerDialog> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _userPaused = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.filePath));
    _init();
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      setState(() => _ready = true);
      await _controller.play();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'This video could not be played on this device.');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final total = d.inSeconds.clamp(0, 359999);
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  static bool _hasKnownDuration(VideoPlayerValue value) =>
      value.duration.inMilliseconds > 1;

  void _togglePlay() {
    if (!_ready) return;
    final value = _controller.value;
    if (value.isPlaying) {
      _userPaused = true;
      _controller.pause();
    } else {
      final reachedEnd = _hasKnownDuration(value)
          ? value.isCompleted || value.position >= value.duration
          : !_userPaused;
      if (reachedEnd) {
        _controller.seekTo(Duration.zero);
      }
      _userPaused = false;
      _controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenCap = MediaQuery.of(context).size.height * 0.55;
    return Dialog(
      backgroundColor: AppColors.primaryBg,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Reserve vertical space for dialog padding, header row, gaps, and
          // playback controls so the player stays inside short landscape dialogs.
          const dialogChromeHeight = 140.0;
          final availableVideoHeight = constraints.maxHeight.isFinite
              ? (constraints.maxHeight - dialogChromeHeight)
                  .clamp(80.0, screenCap > 80.0 ? screenCap : 80.0)
              : screenCap;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.textStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Close',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 24,
                      horizontal: 8,
                    ),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: AppTypography.textStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                else if (!_ready)
                  SizedBox(
                    height: availableVideoHeight.clamp(80.0, 180.0),
                    child: const Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: availableVideoHeight,
                      ),
                      child: AspectRatio(
                        aspectRatio: _controller.value.aspectRatio > 0
                            ? _controller.value.aspectRatio
                            : 16 / 9,
                        child: GestureDetector(
                          onTap: _togglePlay,
                          child: VideoPlayer(_controller),
                        ),
                      ),
                    ),
                  ),
              const SizedBox(height: 8),
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _controller,
                builder: (_, value, _) => Row(
                  children: [
                    IconButton(
                      onPressed: _togglePlay,
                      icon: Icon(
                        value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: AppColors.accent,
                      ),
                    ),
                    Expanded(
                      child: _hasKnownDuration(value)
                          ? VideoProgressIndicator(
                              _controller,
                              allowScrubbing: true,
                              colors: const VideoProgressColors(
                                playedColor: AppColors.accent,
                                bufferedColor: AppColors.borderColor,
                                backgroundColor: Color(0xFFE5E5EA),
                              ),
                            )
                          : LinearProgressIndicator(
                              value: value.isPlaying ? null : 0,
                              minHeight: 4,
                              color: AppColors.accent,
                              backgroundColor: const Color(0xFFE5E5EA),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _hasKnownDuration(value)
                          ? '${_formatDuration(value.position)} / ${_formatDuration(value.duration)}'
                          : '',
                      style: AppTypography.textStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
    );
  }
}
