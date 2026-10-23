import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fieldlog_mobile/app_typography.dart';
import '../models/tally_component.dart';
import '../theme/app_colors.dart';

typedef _ImagePlaceholderBuilder = Widget Function(BuildContext, String);
typedef _ImageErrorBuilder = Widget Function(BuildContext, String, Object?);

class _NetworkIcon extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final _ImagePlaceholderBuilder placeholder;
  final _ImageErrorBuilder errorWidget;

  const _NetworkIcon({
    required this.url,
    required this.fit,
    required this.placeholder,
    required this.errorWidget,
  });

  bool get _isSvg => url.toLowerCase().split('?').first.endsWith('.svg');

  @override
  State<_NetworkIcon> createState() => _NetworkIconState();
}

class _NetworkIconState extends State<_NetworkIcon> {
  Future<File>? _fileFuture;

  @override
  void initState() {
    super.initState();
    if (widget._isSvg) {
      _fileFuture = DefaultCacheManager().getSingleFile(widget.url);
    }
  }

  @override
  void didUpdateWidget(covariant _NetworkIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget._isSvg && oldWidget.url != widget.url) {
      _fileFuture = DefaultCacheManager().getSingleFile(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget._isSvg) {
      return CachedNetworkImage(
        imageUrl: widget.url,
        fit: widget.fit,
        placeholder: widget.placeholder,
        errorWidget: widget.errorWidget,
      );
    }
    return FutureBuilder<File>(
      future: _fileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.placeholder(context, widget.url);
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return widget.errorWidget(context, widget.url, snapshot.error);
        }
        return SvgPicture.file(snapshot.data!, fit: widget.fit);
      },
    );
  }
}

class TallyRenderer extends StatefulWidget {
  final List<dynamic> components;
  final void Function(Map<String, dynamic> data) onTap;
  final Map<String, int> initialCounts;

  const TallyRenderer({
    super.key,
    required this.components,
    required this.onTap,
    this.initialCounts = const {},
  });

  @override
  State<TallyRenderer> createState() => _TallyRendererState();
}

class _TallyRendererState extends State<TallyRenderer> {
  TallyComponent? _activeGroup;
  final Map<String, int> _counts = {};

  @override
  void initState() {
    super.initState();
    _counts.addAll(widget.initialCounts);
  }

  List<TallyComponent> get _parsed => widget.components
      .map((c) => TallyComponent.fromJson(c as Map<String, dynamic>))
      .toList();

  List<TallyComponent> get _currentItems {
    if (_activeGroup != null) {
      return _activeGroup!.children;
    }
    return _parsed.where((c) => !c.isGroup || c.children.isNotEmpty).toList();
  }

  void _handleTap(TallyComponent item) {
    setState(() {
      _counts[item.key] = (_counts[item.key] ?? 0) + 1;
    });
    final data = <String, dynamic>{
      'tally_key': item.key,
      'tally_label': item.label,
      'count': 1,
      'timestamp': DateTime.now().toIso8601String(),
    };
    if (_activeGroup != null) {
      data['tally_group'] = _activeGroup!.key;
    }
    widget.onTap(data);
  }

  @override
  Widget build(BuildContext context) {
    final items = _currentItems;

    return Column(
      children: [
        // Group breadcrumb
        if (_activeGroup != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: GestureDetector(
              onTap: () => setState(() => _activeGroup = null),
              child: Row(
                children: [
                  const Icon(
                    Icons.arrow_back_ios,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _activeGroup!.label,
                    style: AppTypography.textStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.0,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              if (item.isGroup) {
                return _GroupCard(
                  item: item,
                  onTap: () => setState(() => _activeGroup = item),
                );
              }
              return _TallyCard(
                item: item,
                count: _counts[item.key] ?? 0,
                onTap: () => _handleTap(item),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TallyCard extends StatefulWidget {
  final TallyComponent item;
  final int count;
  final VoidCallback onTap;

  const _TallyCard({
    required this.item,
    required this.count,
    required this.onTap,
  });

  @override
  State<_TallyCard> createState() => _TallyCardState();
}

class _TallyCardState extends State<_TallyCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  bool _showPlus = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _handleTap() {
    _animController.forward().then((_) => _animController.reverse());
    setState(() => _showPlus = true);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _showPlus = false);
    });
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final tapped = _showPlus;

    return ScaleTransition(
      scale: _scaleAnim,
      child: GestureDetector(
        onTap: _handleTap,
        child: Container(
          decoration: BoxDecoration(
            color: tapped ? AppColors.accent : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: tapped ? AppColors.accent : AppColors.borderColor,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: widget.item.image != null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: _NetworkIcon(
                                  url: widget.item.image!,
                                  fit: BoxFit.contain,
                                  placeholder: (context, url) => const Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => Icon(
                                    Icons.image_not_supported_outlined,
                                    color: tapped
                                        ? Colors.white70
                                        : AppColors.textTertiary,
                                    size: 32,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.item.label,
                              style: AppTypography.textStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: tapped
                                    ? Colors.white
                                    : AppColors.textPrimary,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        )
                      : Text(
                          widget.item.label,
                          style: AppTypography.textStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: tapped
                                ? Colors.white
                                : AppColors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                ),
              ),
              // Count badge
              if (widget.count > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: tapped ? Colors.white : AppColors.accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        '${widget.count}',
                        style: AppTypography.textStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: tapped ? AppColors.accent : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              // +1 overlay
              if (tapped)
                Positioned.fill(
                  child: Center(
                    child: Text(
                      '+1',
                      style: AppTypography.textStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
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

class _GroupCard extends StatelessWidget {
  final TallyComponent item;
  final VoidCallback onTap;

  const _GroupCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (item.image != null) ...[
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _NetworkIcon(
                        url: item.image!,
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => const Icon(
                          Icons.folder_outlined,
                          color: AppColors.accent,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ] else ...[
                  const Icon(
                    Icons.folder_outlined,
                    color: AppColors.accent,
                    size: 28,
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        item.label,
                        style: AppTypography.textStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppColors.accent,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
