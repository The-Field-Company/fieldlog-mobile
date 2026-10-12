import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/survey_element.dart';
import '../../theme/app_colors.dart';

class MatrixFieldWidget extends StatefulWidget {
  final String label;
  final List<SurveyChoice> rows;
  final List<SurveyChoice> columns;
  final bool isRequired;
  final Map<String, dynamic>? initialValue;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const MatrixFieldWidget({
    super.key,
    required this.label,
    required this.rows,
    required this.columns,
    required this.onChanged,
    this.isRequired = false,
    this.initialValue,
  });

  @override
  State<MatrixFieldWidget> createState() => _MatrixFieldWidgetState();
}

class _MatrixFieldWidgetState extends State<MatrixFieldWidget> {
  late Map<String, String> _values;

  @override
  void initState() {
    super.initState();
    _values = {};
    if (widget.initialValue != null) {
      for (final entry in widget.initialValue!.entries) {
        _values[entry.key] = entry.value.toString();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: FormField<Map<String, String>>(
        validator: widget.isRequired
            ? (value) {
                final unanswered = widget.rows
                    .where((r) => !_values.containsKey(r.value))
                    .toList();
                if (unanswered.isNotEmpty) {
                  return 'Please answer all rows';
                }
                return null;
              }
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
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 16,
                  headingRowHeight: 40,
                  dataRowMinHeight: 40,
                  dataRowMaxHeight: 48,
                  columns: [
                    const DataColumn(label: SizedBox(width: 80)),
                    ...widget.columns.map(
                      (col) => DataColumn(
                        label: Text(
                          col.text,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                  rows: widget.rows.map((row) {
                    return DataRow(
                      cells: [
                        DataCell(
                          SizedBox(
                            width: 80,
                            child: Text(
                              row.text,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                        ...widget.columns.map((col) {
                          return DataCell(
                            RadioGroup<String>(
                              groupValue: _values[row.value],
                              onChanged: (v) {
                                setState(() => _values[row.value] = v!);
                                state.didChange(_values);
                                widget.onChanged(Map.from(_values));
                              },
                              child: Radio<String>(
                                value: col.value,
                                activeColor: AppColors.accent,
                              ),
                            ),
                          );
                        }),
                      ],
                    );
                  }).toList(),
                ),
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
