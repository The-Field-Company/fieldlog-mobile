class TallyComponent {
  final String key;
  final String label;
  final String type;
  final String? image;
  final List<TallyComponent> children;

  TallyComponent({
    required this.key,
    required this.label,
    required this.type,
    this.image,
    this.children = const [],
  });

  bool get isGroup => type == 'group';

  factory TallyComponent.fromJson(Map<String, dynamic> json) {
    final childrenJson = json['children'] as List<dynamic>?;
    return TallyComponent(
      key: json['key'] ?? '',
      label: json['label'] ?? '',
      type: json['type'] ?? 'tally',
      image: json['image'],
      children: childrenJson
              ?.map((c) => TallyComponent.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
