import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/survey_element.dart';
import '../../theme/app_colors.dart';

class ImagePickerFieldWidget extends StatefulWidget {
  final String label;
  final List<SurveyChoice> choices;
  final bool multiSelect;
  final bool showLabel;
  final bool isRequired;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;

  const ImagePickerFieldWidget({
    super.key,
    required this.label,
    required this.choices,
    required this.onChanged,
    this.multiSelect = false,
    this.showLabel = true,
    this.isRequired = false,
    this.initialValue,
  });

  @override
  State<ImagePickerFieldWidget> createState() => _ImagePickerFieldWidgetState();
}

class _ImagePickerFieldWidgetState extends State<ImagePickerFieldWidget> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = _parseInitial(widget.initialValue);
  }

  Set<String> _parseInitial(dynamic value) {
    if (value == null) return {};
    if (value is List) return value.map((e) => e.toString()).toSet();
    return {value.toString()};
  }

  void _onTap(String value) {
    setState(() {
      if (widget.multiSelect) {
        if (_selected.contains(value)) {
          _selected.remove(value);
        } else {
          _selected.add(value);
        }
        widget.onChanged(_selected.toList());
      } else {
        _selected = {value};
        widget.onChanged(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: FormField<dynamic>(
        initialValue: widget.initialValue,
        validator: widget.isRequired
            ? (_) => _selected.isEmpty ? '${widget.label} is required' : null
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
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1,
                ),
                itemCount: widget.choices.length,
                itemBuilder: (context, index) {
                  final choice = widget.choices[index];
                  final isSelected = _selected.contains(choice.value);
                  return _buildChoice(choice, isSelected);
                },
              ),
              if (state.hasError) ...[
                const SizedBox(height: 8),
                Text(
                  state.errorText!,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildChoice(SurveyChoice choice, bool isSelected) {
    return GestureDetector(
      onTap: () => _onTap(choice.value),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.borderColor,
            width: isSelected ? 2.5 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image
              if (choice.imageLink != null && choice.imageLink!.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: choice.imageLink!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Colors.grey.shade100,
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey.shade100,
                    child: const Center(
                      child: Icon(Icons.broken_image,
                          size: 32, color: AppColors.textTertiary),
                    ),
                  ),
                )
              else
                Container(
                  color: Colors.grey.shade100,
                  child: Center(
                    child: Text(
                      choice.text,
                      style: GoogleFonts.inter(color: AppColors.textSecondary),
                    ),
                  ),
                ),
              // Selection indicator
              if (isSelected)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check,
                        size: 16, color: Colors.white),
                  ),
                ),
              // Label at bottom
              if (widget.showLabel)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.6),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Text(
                      choice.text,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
