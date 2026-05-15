import 'package:uuid/uuid.dart';

enum SnapshotType { lottery, order, shipping }

extension SnapshotTypeExt on SnapshotType {
  String get label {
    switch (this) {
      case SnapshotType.lottery: return 'Lottery';
      case SnapshotType.order: return 'Order';
      case SnapshotType.shipping: return 'Shipping';
    }
  }

  static SnapshotType fromValue(String? v) {
    switch (v) {
      case 'order': return SnapshotType.order;
      case 'shipping': return SnapshotType.shipping;
      default: return SnapshotType.lottery;
    }
  }
}

class ResultSnapshot {
  final String id;
  final DateTime createdAt;
  final SnapshotType type;
  final String keyword;
  final List<Map<String, dynamic>> entries;

  ResultSnapshot({
    String? id,
    DateTime? createdAt,
    required this.type,
    required this.keyword,
    required this.entries,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  int get count => entries.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'type': type.name,
        'keyword': keyword,
        'entries': entries,
      };

  factory ResultSnapshot.fromJson(Map<String, dynamic> json) => ResultSnapshot(
        id: json['id'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : null,
        type: SnapshotTypeExt.fromValue(json['type'] as String?),
        keyword: json['keyword'] as String? ?? '',
        entries: (json['entries'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
}
