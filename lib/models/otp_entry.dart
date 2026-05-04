import 'package:uuid/uuid.dart';

class OtpEntry {
  final String id;
  final String code;
  final String? sender;
  final String? subject;
  final String? recipient; // email người nhận (To field)
  final DateTime timestamp;

  OtpEntry({
    String? id,
    required this.code,
    this.sender,
    this.subject,
    this.recipient,
    DateTime? timestamp,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  bool get isRecent => DateTime.now().difference(timestamp).inMinutes < 5;

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'sender': sender,
        'subject': subject,
        'recipient': recipient,
        'timestamp': timestamp.toIso8601String(),
      };

  factory OtpEntry.fromJson(Map<String, dynamic> json) => OtpEntry(
        id: json['id'] as String?,
        code: json['code'] as String,
        sender: json['sender'] as String?,
        subject: json['subject'] as String?,
        recipient: json['recipient'] as String?,
        timestamp: json['timestamp'] != null
            ? DateTime.parse(json['timestamp'] as String)
            : null,
      );
}
