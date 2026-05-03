import 'dart:async';
import 'package:enough_mail/enough_mail.dart';
import '../models/otp_entry.dart';
import '../models/filter_rule.dart';

class ImapConfig {
  final String host;
  final int port;
  final String username;
  final String password;
  final bool isSecure;
  final int pollIntervalSeconds;

  const ImapConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.isSecure = true,
    this.pollIntervalSeconds = 30,
  });
}

class ImapService {
  ImapClient? _client;
  Timer? _pollTimer;
  ImapConfig? _config;
  List<FilterRule> _rules = [];
  bool _isRunning = false;

  final _otpController = StreamController<OtpEntry>.broadcast();
  Stream<OtpEntry> get otpStream => _otpController.stream;

  bool get isRunning => _isRunning;

  void setRules(List<FilterRule> rules) {
    _rules = rules.where((r) => r.enabled).toList();
  }

  Future<void> start(ImapConfig config) async {
    await stop();
    _config = config;
    _isRunning = true;
    await _connect();
    _pollTimer = Timer.periodic(
      Duration(seconds: config.pollIntervalSeconds),
      (_) => _poll(),
    );
  }

  Future<void> stop() async {
    _isRunning = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    try {
      await _client?.logout();
    } catch (_) {}
    _client = null;
  }

  Future<void> _connect() async {
    final config = _config!;
    _client = ImapClient(isLogEnabled: false);
    await _client!.connectToServer(
      config.host,
      config.port,
      isSecure: config.isSecure,
    );
    await _client!.login(config.username, config.password);
    await _client!.selectInbox();
  }

  Future<List<OtpEntry>> fetchNow() async {
    if (_config == null) return [];
    try {
      if (_client == null || !_isRunning) {
        await _connect();
      }
      return await _poll();
    } catch (_) {
      return [];
    }
  }

  Future<List<OtpEntry>> _poll() async {
    final results = <OtpEntry>[];
    try {
      if (_client == null) await _connect();

      // Get inbox message count then fetch last 15 messages
      final mailbox = await _client!.selectInbox();
      final count = mailbox.messagesExists;
      if (count == 0) return results;

      final start = count > 15 ? count - 14 : 1;
      final sequence = MessageSequence.fromRange(start, count);
      final fetchResult = await _client!.fetchMessages(
        sequence,
        'ENVELOPE BODY.PEEK[TEXT]',
      );

      final cutoff = DateTime.now().subtract(const Duration(minutes: 10));
      for (final msg in fetchResult.messages) {
        final msgDate = msg.decodeDate();
        if (msgDate != null && msgDate.isBefore(cutoff)) continue;

        final entry = _extractOtp(msg);
        if (entry != null && !_otpController.isClosed) {
          results.add(entry);
          _otpController.add(entry);
        }
      }
    } catch (_) {
      _client = null;
    }
    return results;
  }

  OtpEntry? _extractOtp(MimeMessage msg) {
    final sender = msg.from?.firstOrNull?.email ?? '';
    final subject = msg.decodeSubject() ?? '';
    final body = msg.decodeTextPlainPart() ?? msg.decodeTextHtmlPart() ?? '';

    for (final rule in _rules) {
      bool matches = false;
      switch (rule.type) {
        case FilterType.sender:
          matches = sender.toLowerCase().contains(rule.pattern.toLowerCase());
          break;
        case FilterType.subject:
          matches = subject.toLowerCase().contains(rule.pattern.toLowerCase());
          break;
        case FilterType.regex:
          try {
            matches = RegExp(rule.pattern, caseSensitive: false).hasMatch(body) ||
                RegExp(rule.pattern, caseSensitive: false).hasMatch(subject);
          } catch (_) {}
          break;
      }

      if (matches) {
        final otp = rule.extractOtp(body) ?? rule.extractOtp(subject);
        if (otp != null) {
          return OtpEntry(
            code: otp,
            sender: sender,
            subject: subject,
            timestamp: msg.decodeDate() ?? DateTime.now(),
          );
        }
      }
    }

    // Fallback: 6-digit code
    final fallback = RegExp(r'\b(\d{6})\b').firstMatch(body) ??
        RegExp(r'\b(\d{6})\b').firstMatch(subject);
    if (fallback != null) {
      return OtpEntry(
        code: fallback.group(1)!,
        sender: sender,
        subject: subject,
        timestamp: msg.decodeDate() ?? DateTime.now(),
      );
    }

    return null;
  }

  Future<bool> testConnection(ImapConfig config) async {
    final client = ImapClient(isLogEnabled: false);
    try {
      await client.connectToServer(
        config.host,
        config.port,
        isSecure: config.isSecure,
      );
      await client.login(config.username, config.password);
      await client.logout();
      return true;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    stop();
    _otpController.close();
  }
}
