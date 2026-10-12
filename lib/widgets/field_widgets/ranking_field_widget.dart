import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';

class RankingFieldWidget extends StatefulWidget {
  final String label;
  final List<MapEntry<String, String>> choices;
  final List<String>? initialValue;
  final ValueChanged<List<String>> onChanged;

  const RankingFieldWidget({
    super.key,
    required this.label,
    required this.choices,
    required this.onChanged,
    this.initialValue,
  });

  @override
  State<RankingFieldWidget> createState() => _RankingFieldWidgetState();
}

class _RankingFieldWidgetState extends State<RankingFieldWidget> {
  late List<MapEntry<String, String>> _items;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null && widget.initialValue!.isNotEmpty) {
      // Reorder choices to match initialValue order
      final byKey = {for (var c in widget.choices) c.key: c};
      _items = widget.initialValue!
          .where((k) => byKey.containsKey(k))
          .map((k) => byKey[k]!)
          .toList();
      // Append any choices not in initialValue
      for (final c in widget.choices) {
        if (!_items.any((i) => i.key == c.key)) {
          _items.add(c);
        }
      }
    } else {
      _items = List.from(widget.choices);
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
    widget.onChanged(_items.map((i) => i.key).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: GoogleFonts.inter(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _items.length,
            onReorder: _onReorder,
            itemBuilder: (context, index) {
              final item = _items[index];
              return Container(
                key: ValueKey(item.key),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.borderColor),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ListTile(
                  leading: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  title: Text(
                    item.value,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  trailing: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(
                      Icons.drag_handle,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
