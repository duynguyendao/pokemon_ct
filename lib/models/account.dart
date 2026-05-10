import 'package:uuid/uuid.dart';

/// Chế độ hoạt động khi mở account
enum AccountMode { loginOnly, lottery, lotteryResult, orderStatus }

extension AccountModeExt on AccountMode {
  String get label {
    switch (this) {
      case AccountMode.loginOnly: return 'Login';
      case AccountMode.lottery: return 'Lottery';
      case AccountMode.lotteryResult: return 'Result';
      case AccountMode.orderStatus: return 'Order';
    }
  }

  String get value {
    switch (this) {
      case AccountMode.loginOnly: return 'loginOnly';
      case AccountMode.lottery: return 'lottery';
      case AccountMode.lotteryResult: return 'lotteryResult';
      case AccountMode.orderStatus: return 'orderStatus';
    }
  }

  static AccountMode fromValue(String? v) {
    switch (v) {
      case 'lottery': return AccountMode.lottery;
      case 'lotteryResult': return AccountMode.lotteryResult;
      case 'orderStatus': return AccountMode.orderStatus;
      default: return AccountMode.loginOnly;
    }
  }
}

class Account {
  final String id;
  String email;
  String password;
  String status; // 'todo' | 'done'
  String? group;
  String? proxyId;
  AccountMode mode;
  final DateTime createdAt;
  Map<String, dynamic> presets;

  Account({
    String? id,
    required this.email,
    required this.password,
    this.status = 'todo',
    this.group,
    this.proxyId,
    this.mode = AccountMode.loginOnly,
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
    AccountMode? mode,
    Map<String, dynamic>? presets,
  }) {
    return Account(
      id: id,
      email: email ?? this.email,
      password: password ?? this.password,
      status: status ?? this.status,
      group: group ?? this.group,
      proxyId: proxyId ?? this.proxyId,
      mode: mode ?? this.mode,
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
        'mode': mode.value,
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
        mode: AccountModeExt.fromValue(json['mode'] as String?),
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : null,
        presets: json['presets'] != null
            ? Map<String, dynamic>.from(json['presets'] as Map)
            : null,
      );
}
