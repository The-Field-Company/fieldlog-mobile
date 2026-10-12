import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';

class FieldRating extends StatefulWidget {
  final String label;
  final bool isRequired;
  final int maxRating;
  final int rateMin;
  final String? rateType;
  final int? initialValue;
  final ValueChanged<int> onChanged;

  const FieldRating({
    super.key,
    required this.label,
    required this.onChanged,
    this.isRequired = false,
    this.maxRating = 5,
    this.rateMin = 1,
    this.rateType,
    this.initialValue,
  });

  @override
  State<FieldRating> createState() => _FieldRatingState();
}

class _FieldRatingState extends State<FieldRating> {
  late int _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue ?? 0;
  }

  IconData _iconFor(int index, bool filled) {
    switch (widget.rateType) {
      case 'smileys':
        return filled ? Icons.sentiment_satisfied : Icons.sentiment_satisfied_outlined;
      default: // 'stars' or null
        return filled ? Icons.star : Icons.star_border;
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.maxRating - widget.rateMin + 1;

    if (widget.rateType == 'numerical') {
      return _buildNumerical(count);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: FormField<int>(
        validator: widget.isRequired
            ? (value) =>
                _value == 0 ? '${widget.label} is required' : null
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
              Row(
                children: List.generate(count, (index) {
                  final ratingValue = widget.rateMin + index;
                  final filled = ratingValue <= _value;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _value = ratingValue);
                      state.didChange(ratingValue);
                      widget.onChanged(ratingValue);
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        _iconFor(ratingValue, filled),
                        color: filled
                            ? AppColors.accent
                            : AppColors.borderColor,
                        size: 32,
                      ),
                    ),
                  );
                }),
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

  Widget _buildNumerical(int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: FormField<int>(
        validator: widget.isRequired
            ? (value) =>
                _value == 0 ? '${widget.label} is required' : null
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(count, (index) {
                  final ratingValue = widget.rateMin + index;
                  final selected = ratingValue == _value;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _value = ratingValue);
                      state.didChange(ratingValue);
                      widget.onChanged(ratingValue);
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.accent
                            : Colors.transparent,
                        border: Border.all(
                          color: selected
                              ? AppColors.accent
                              : AppColors.borderColor,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$ratingValue',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: selected
                              ? Colors.white
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  );
                }),
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
