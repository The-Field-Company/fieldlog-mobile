import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';

class ImageFieldWidget extends StatelessWidget {
  final String imageLink;
  final String? label;

  const ImageFieldWidget({
    super.key,
    required this.imageLink,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    if (imageLink.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null && label!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                label!,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: imageLink,
              width: double.infinity,
              fit: BoxFit.contain,
              placeholder: (context, url) => Container(
                height: 150,
                color: Colors.grey.shade100,
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (context, url, error) => Container(
                height: 100,
                color: Colors.grey.shade100,
                child: const Center(
                  child: Icon(Icons.broken_image,
                      size: 32, color: AppColors.textTertiary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
