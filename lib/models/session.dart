import 'dart:convert';

class Session {
  final int id;
  final String name;
  final String description;
  final Map<String, dynamic> formConfig;
  final bool isActive;
  final bool isPublic;
  final String createdAt;

  Session({
    required this.id,
    required this.name,
    required this.description,
    required this.formConfig,
    required this.isActive,
    required this.isPublic,
    required this.createdAt,
  });

  /// Reads a row from the local PowerSync `fieldlog_session` SQLite table.
  /// Differences from [fromJson]: `form_config` is a JSON string and needs
  /// decoding; `is_active`/`is_public` are stored as SQLite integers (0/1);
  /// `id` is the PowerSync row id (the Django integer serialised as a string).
  factory Session.fromRow(Map<String, dynamic> row) {
    Map<String, dynamic> formConfig = {};
    try {
      final raw = row['form_config'];
      if (raw != null && raw is String && raw.isNotEmpty) {
        formConfig = jsonDecode(raw) as Map<String, dynamic>;
      }
    } catch (_) {}

    return Session(
      id: int.tryParse(row['id']?.toString() ?? '') ?? 0,
      name: row['name'] as String? ?? '',
      description: row['description'] as String? ?? '',
      formConfig: formConfig,
      isActive: (row['is_active'] as int? ?? 1) == 1,
      isPublic: (row['is_public'] as int? ?? 0) == 1,
      createdAt: row['created_at'] as String? ?? '',
    );
  }

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'],
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      formConfig: json['form_config'] ?? {},
      isActive: json['is_active'] ?? true,
      isPublic: json['is_public'] ?? false,
      createdAt: json['created_at'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'form_config': formConfig,
        'is_active': isActive,
        'is_public': isPublic,
        'created_at': createdAt,
      };

  String get formMode => formConfig['form_mode'] ?? 'formkit';
  bool get trackLocation => formConfig['track_location'] == true;
  List<dynamic> get components {
    final value = formConfig['components'];
    return value is List ? value : [];
  }

  Map<String, dynamic>? get schema {
    final value = formConfig['schema'];
    return value is Map<String, dynamic> ? value : null;
  }
}
