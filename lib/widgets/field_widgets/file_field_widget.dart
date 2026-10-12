import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../theme/app_colors.dart';

class FileFieldWidget extends StatefulWidget {
  final String label;
  final bool isRequired;
  final ValueChanged<Map<String, dynamic>?> onChanged;

  const FileFieldWidget({
    super.key,
    required this.label,
    required this.onChanged,
    this.isRequired = false,
  });

  @override
  State<FileFieldWidget> createState() => _FileFieldWidgetState();
}

class _FileFieldWidgetState extends State<FileFieldWidget> {
  File? _file;
  final _picker = ImagePicker();

  Future<void> _pick(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1080,
    );
    if (picked == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final ext = picked.path.split('.').last.toLowerCase();

    if (!{'jpg', 'jpeg', 'png', 'webp', 'heic'}.contains(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Unsupported file type (.$ext). Please choose a JPG, PNG, WEBP, or HEIC image.',
            ),
          ),
        );
      }
      return;
    }

    final id = const Uuid().v4();
    final newPath = '${dir.path}/$id.$ext';
    final saved = await File(picked.path).copy(newPath);

    // Check file size
    final bytes = await saved.length();
    final mb = bytes / (1024 * 1024);
    if (mb > 10) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File too large (max 10 MB).')),
        );
      }
      await saved.delete();
      return;
    }
    if (mb > 2 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Large file (${mb.toStringAsFixed(1)}MB) — upload may be slow'),
          backgroundColor: Colors.orange.shade700,
        ),
      );
    }

    setState(() => _file = saved);
    widget.onChanged({
      'file_path': saved.path,
      'file_name': '$id.$ext',
      'original_name': picked.name.isNotEmpty ? picked.name : '$id.$ext',
      'file_size': bytes,
    });
  }

  void _showPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(ctx);
                _pick(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Photo Library'),
              onTap: () {
                Navigator.pop(ctx);
                _pick(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _remove() {
    setState(() => _file = null);
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: FormField<File>(
        validator: widget.isRequired
            ? (value) =>
                _file == null ? '${widget.label} is required' : null
            : null,
        builder: (state) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.label + (widget.isRequired ? ' *' : ''),
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              if (_file == null)
                GestureDetector(
                  onTap: _showPicker,
                  child: SizedBox(
                    width: double.infinity,
                    height: 120,
                    child: CustomPaint(
                      painter: _DashedBorderPainter(
                          color: AppColors.borderColor),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.camera_alt,
                                size: 32, color: AppColors.textTertiary),
                            const SizedBox(height: 4),
                            Text(
                              'Tap to add photo',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        _file!,
                        width: double.infinity,
                        height: 180,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: _remove,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              if (state.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    state.errorText!,
                    style: GoogleFonts.inter(
                        fontSize: 12, color: AppColors.error),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const dashWidth = 6.0;
    const dashSpace = 4.0;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(8),
    );

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().first;
    double distance = 0;
    while (distance < metrics.length) {
      final end =
          (distance + dashWidth).clamp(0.0, metrics.length);
      final extracted =
          metrics.extractPath(distance, end);
      canvas.drawPath(extracted, paint);
      distance += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
