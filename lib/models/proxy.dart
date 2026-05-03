import 'package:uuid/uuid.dart';

class Proxy {
  final String id;
  String host;
  int port;
  String? username;
  String? password;
  String? label;
  int usageCount;
  DateTime? lastUsed;
  bool enabled;

  Proxy({
    String? id,
    required this.host,
    required this.port,
    this.username,
    this.password,
    this.label,
    this.usageCount = 0,
    this.lastUsed,
    this.enabled = true,
  }) : id = id ?? const Uuid().v4();

  String get displayLabel => label?.isNotEmpty == true ? label! : '$host:$port';

  String get proxyUrl {
    if (username != null && password != null) {
      return 'http://$username:$password@$host:$port';
    }
    return 'http://$host:$port';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'label': label,
        'usageCount': usageCount,
        'lastUsed': lastUsed?.toIso8601String(),
        'enabled': enabled,
      };

  factory Proxy.fromJson(Map<String, dynamic> json) => Proxy(
        id: json['id'] as String?,
        host: json['host'] as String,
        port: json['port'] as int,
        username: json['username'] as String?,
        password: json['password'] as String?,
        label: json['label'] as String?,
        usageCount: json['usageCount'] as int? ?? 0,
        lastUsed: json['lastUsed'] != null
            ? DateTime.parse(json['lastUsed'] as String)
            : null,
        enabled: json['enabled'] as bool? ?? true,
      );

  Proxy copyWith({
    String? host,
    int? port,
    String? username,
    String? password,
    String? label,
    int? usageCount,
    DateTime? lastUsed,
    bool? enabled,
  }) =>
      Proxy(
        id: id,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        password: password ?? this.password,
        label: label ?? this.label,
        usageCount: usageCount ?? this.usageCount,
        lastUsed: lastUsed ?? this.lastUsed,
        enabled: enabled ?? this.enabled,
      );
}
