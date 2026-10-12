import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';

class TagboxFieldWidget extends StatefulWidget {
  final String label;
  final bool isRequired;
  final List<MapEntry<String, String>> options;
  final List<String>? initialValue;
  final ValueChanged<List<String>> onChanged;

  const TagboxFieldWidget({
    super.key,
    required this.label,
    required this.options,
    required this.onChanged,
    this.isRequired = false,
    this.initialValue,
  });

  @override
  State<TagboxFieldWidget> createState() => _TagboxFieldWidgetState();
}

class _TagboxFieldWidgetState extends State<TagboxFieldWidget> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialValue?.toSet() ?? {};
  }

  void _openPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _TagboxSheet(
        options: widget.options,
        selected: Set.from(_selected),
        onDone: (selected) {
          setState(() => _selected = selected);
          widget.onChanged(_selected.toList());
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: FormField<List<String>>(
        validator: widget.isRequired
            ? (value) =>
                _selected.isEmpty ? '${widget.label} is required' : null
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
              GestureDetector(
                onTap: _openPicker,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.borderColor),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: _selected.isEmpty
                      ? Text(
                          'Tap to select...',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppColors.textTertiary,
                          ),
                        )
                      : Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _selected.map((val) {
                            final label = widget.options
                                .firstWhere((o) => o.key == val,
                                    orElse: () => MapEntry(val, val))
                                .value;
                            return Chip(
                              label: Text(label,
                                  style: GoogleFonts.inter(fontSize: 13)),
                              deleteIcon:
                                  const Icon(Icons.close, size: 16),
                              onDeleted: () {
                                setState(() => _selected.remove(val));
                                state.didChange(_selected.toList());
                                widget.onChanged(_selected.toList());
                              },
                              backgroundColor: AppColors.accent
                                  .withValues(alpha: 0.08),
                              side: BorderSide.none,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            );
                          }).toList(),
                        ),
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

class _TagboxSheet extends StatefulWidget {
  final List<MapEntry<String, String>> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onDone;

  const _TagboxSheet({
    required this.options,
    required this.selected,
    required this.onDone,
  });

  @override
  State<_TagboxSheet> createState() => _TagboxSheetState();
}

class _TagboxSheetState extends State<_TagboxSheet> {
  late Set<String> _selected;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.selected);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.options.where((o) {
      if (_search.isEmpty) return true;
      return o.value.toLowerCase().contains(_search.toLowerCase());
    }).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search...',
                        prefixIcon: Icon(Icons.search, size: 20),
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      widget.onDone(_selected);
                      Navigator.pop(context);
                    },
                    child: Text(
                      'Done',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final option = filtered[i];
                  final checked = _selected.contains(option.key);
                  return CheckboxListTile(
                    title: Text(option.value,
                        style: GoogleFonts.inter(fontSize: 15)),
                    value: checked,
                    activeColor: AppColors.accent,
                    dense: true,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(option.key);
                        } else {
                          _selected.remove(option.key);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
