import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';

class FieldSlider extends StatefulWidget {
  final String label;
  final num min;
  final num max;
  final num step;
  final ValueChanged<double> onChanged;
  final double? initialValue;

  const FieldSlider({
    super.key,
    required this.label,
    required this.onChanged,
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.initialValue,
  });

  @override
  State<FieldSlider> createState() => _FieldSliderState();
}

class _FieldSliderState extends State<FieldSlider> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue ?? widget.min.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.label,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                _value.toStringAsFixed(
                    widget.step is int || widget.step == widget.step.roundToDouble()
                        ? 0
                        : 1),
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          Slider(
            value: _value,
            min: widget.min.toDouble(),
            max: widget.max.toDouble(),
            divisions: widget.step > 0
                ? ((widget.max - widget.min) / widget.step).round()
                : null,
            activeColor: AppColors.accent,
            inactiveColor: AppColors.borderColor,
            onChanged: (value) {
              setState(() => _value = value);
              widget.onChanged(value);
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${widget.min}',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppColors.textTertiary)),
              Text('${widget.max}',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppColors.textTertiary)),
            ],
          ),
        ],
      ),
    );
  }
}
