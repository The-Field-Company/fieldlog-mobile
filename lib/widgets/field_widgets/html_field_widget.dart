import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';

/// Renders static HTML content as styled text.
/// Strips basic HTML tags for a POC-level rendering.
class HtmlFieldWidget extends StatelessWidget {
  final String html;

  const HtmlFieldWidget({super.key, required this.html});

  @override
  Widget build(BuildContext context) {
    final text = _stripHtml(html);
    if (text.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.borderColor.withValues(alpha: 0.5)),
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 14,
            height: 1.5,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  static String _stripHtml(String html) {
    // Replace common block tags with newlines
    var text = html
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'</(p|div|h[1-6]|li)>'), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '') // strip all remaining tags
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
    // Collapse multiple newlines
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return text;
  }
}
