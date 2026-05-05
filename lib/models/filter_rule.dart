import 'package:uuid/uuid.dart';

enum FilterType { sender, subject, recipient, body, regex }

class FilterRule {
  final String id;
  FilterType type;
  String pattern;
  String? extractPattern;
  bool enabled;

  FilterRule({
    String? id,
    required this.type,
    required this.pattern,
    this.extractPattern,
    this.enabled = true,
  }) : id = id ?? const Uuid().v4();

  String get typeLabel {
    switch (type) {
      case FilterType.sender:
        return 'Sender';
      case FilterType.subject:
        return 'Subject';
      case FilterType.recipient:
        return 'Recipient';
      case FilterType.body:
        return 'Body';
      case FilterType.regex:
        return 'Regex';
    }
  }

  String? extractOtp(String text) {
    // Try extract pattern first
    if (extractPattern?.isNotEmpty == true) {
      try {
        final match = RegExp(extractPattern!).firstMatch(text);
        if (match != null) {
          return match.group(1) ?? match.group(0);
        }
      } catch (_) {}
    }

    // Fallback: extract 6-digit OTP
    final otpPattern = RegExp(r'\b[0-9]{6}\b');
    final match = otpPattern.firstMatch(text);
    return match?.group(0);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'pattern': pattern,
    'extractPattern': extractPattern,
    'enabled': enabled,
  };

  factory FilterRule.fromJson(Map<String, dynamic> json) => FilterRule(
    id: json['id'] as String?,
    type: FilterType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => FilterType.sender,
    ),
    pattern: json['pattern'] as String,
    extractPattern: json['extractPattern'] as String?,
    enabled: json['enabled'] as bool? ?? true,
  );

  FilterRule copyWith({
    FilterType? type,
    String? pattern,
    String? extractPattern,
    bool? enabled,
  }) => FilterRule(
    id: id,
    type: type ?? this.type,
    pattern: pattern ?? this.pattern,
    extractPattern: extractPattern ?? this.extractPattern,
    enabled: enabled ?? this.enabled,
  );
}
