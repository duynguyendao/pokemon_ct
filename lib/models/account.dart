import 'package:uuid/uuid.dart';

class Account {
  final String id;
  String email;
  String password;
  String status; // 'todo' | 'done'
  String? group;
  String? proxyId;
  final DateTime createdAt;
  Map<String, dynamic> presets;

  Account({
    String? id,
    required this.email,
    required this.password,
    this.status = 'todo',
    this.group,
    this.proxyId,
    DateTime? createdAt,
    Map<String, dynamic>? presets,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        presets = presets ?? {};

  Account copyWith({
    String? email,
    String? password,
    String? status,
    String? group,
    String? proxyId,
    Map<String, dynamic>? presets,
  }) {
    return Account(
      id: id,
      email: email ?? this.email,
      password: password ?? this.password,
      status: status ?? this.status,
      group: group ?? this.group,
      proxyId: proxyId ?? this.proxyId,
      createdAt: createdAt,
      presets: presets ?? Map.from(this.presets),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'password': password,
        'status': status,
        'group': group,
        'proxyId': proxyId,
        'createdAt': createdAt.toIso8601String(),
        'presets': presets,
      };

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as String?,
        email: json['email'] as String,
        password: json['password'] as String,
        status: json['status'] as String? ?? 'todo',
        group: json['group'] as String?,
        proxyId: json['proxyId'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : null,
        presets: json['presets'] != null
            ? Map<String, dynamic>.from(json['presets'] as Map)
            : null,
      );
}
