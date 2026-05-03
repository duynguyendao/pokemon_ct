import 'dart:async';
import 'package:enough_mail/enough_mail.dart';
import '../models/otp_entry.dart';
import '../models/filter_rule.dart';
import 'debug_service.dart';

void _log(String tag, String msg) {
  debugService.log('[IMAP:$tag] $msg');
}

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

class EmailSearchResult {
  final String subject;
  final String sender;
  final String body;
  final DateTime date;
  final String? otpFound;

  const EmailSearchResult({
    required this.subject,
    required this.sender,
    required this.body,
    required this.date,
    this.otpFound,
  });
}

class ImapService {
  ImapClient? _client;
  Timer? _pollTimer;
  ImapConfig? _config;
  List<FilterRule> _rules = [];
  bool _isRunning = false;
  bool _polling = false; // prevent concurrent polls

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
    await _closeClient();
  }

  // Properly close connection and free the slot
  Future<void> _closeClient() async {
    final old = _client;
    _client = null;
    if (old != null) {
      try {
        await old.logout();
        _log('CONNECT', 'Disconnected ✓');
      } catch (_) {}
    }
  }

  Future<void> _connect() async {
    final config = _config!;
    // Always close existing before opening a new one
    await _closeClient();
    _log('CONNECT', 'Connecting to ${config.host}:${config.port}...');
    final client = ImapClient(isLogEnabled: false);
    try {
      await client.connectToServer(config.host, config.port, isSecure: config.isSecure);
      _log('CONNECT', 'Connected ✓');
      await client.login(config.username, config.password);
      _log('CONNECT', 'Logged in ✓');
      await client.selectInbox();
      _log('CONNECT', 'Inbox selected ✓');
      _client = client;
    } catch (e) {
      _log('CONNECT', 'Error: $e');
      try { await client.logout(); } catch (_) {}
      rethrow;
    }
  }

  Future<List<OtpEntry>> fetchNow() async {
    if (_config == null) return [];
    try {
      if (_client == null) await _connect();
      return await _poll();
    } catch (_) {
      return [];
    }
  }

  Future<List<OtpEntry>> _poll() async {
    // Skip if already polling (timer fires while previous poll still running)
    if (_polling) {
      _log('POLL', 'Skipped (previous poll still running)');
      return [];
    }
    _polling = true;
    final results = <OtpEntry>[];
    try {
      if (_client == null) await _connect();

      final mailbox = await _client!.selectInbox();
      final count = mailbox.messagesExists;
      _log('POLL', 'Messages: $count');
      if (count == 0) return results;

      final start = (count > 20 ? count - 19 : 1);
      final sequence = MessageSequence.fromRange(start, count);
      _log('POLL', 'Fetching $start-$count...');

      final fetchResult = await _client!.fetchMessages(sequence, 'ENVELOPE BODY[]');
      _log('POLL', 'Got ${fetchResult.messages.length} messages');

      final cutoff = DateTime.now().subtract(const Duration(hours: 1));
      for (final msg in fetchResult.messages) {
        final msgDate = msg.decodeDate();
        if (msgDate != null && msgDate.isBefore(cutoff)) continue;

        final entry = _extractOtp(msg);
        if (entry != null && !_otpController.isClosed) {
          results.add(entry);
          _log('POLL', 'OTP: ${entry.code}');
          _otpController.add(entry);
        }
      }
    } catch (e) {
      _log('POLL', 'Error: $e');
      // Properly close the broken connection
      await _closeClient();
    } finally {
      _polling = false;
    }
    return results;
  }

  /// Tìm email. Tạm dừng poll khi search để tránh "too many connections"
  Future<List<EmailSearchResult>> searchEmails({
    required ImapConfig config,
    String subjectKeyword = '',
    DateTime? from,
    DateTime? to,
    int maxMessages = 20,
  }) async {
    final results = <EmailSearchResult>[];

    // Pause poll timer and close existing connection to free the slot
    final wasRunning = _isRunning;
    _pollTimer?.cancel();
    _pollTimer = null;
    _log('SEARCH', 'Paused poll timer, closing existing connection...');
    await _closeClient();

    _log('SEARCH', 'Connecting for search...');
    final client = ImapClient(isLogEnabled: false);
    try {
      await client.connectToServer(config.host, config.port, isSecure: config.isSecure);
      _log('SEARCH', 'Connected ✓');
      await client.login(config.username, config.password);
      _log('SEARCH', 'Logged in ✓');
      final mailbox = await client.selectInbox();
      _log('SEARCH', 'Inbox selected ✓');
      final count = mailbox.messagesExists;
      _log('SEARCH', 'Total messages: $count');
      if (count == 0) return results;

      final fetchCount = count < maxMessages ? count : maxMessages;
      final startSeq = count - fetchCount + 1;
      final sequence = MessageSequence.fromRange(startSeq, count);
      _log('SEARCH', 'Fetching $startSeq-$count ($fetchCount messages)...');
      final fetchResult = await client.fetchMessages(sequence, 'ENVELOPE BODY[]');
      _log('SEARCH', 'Fetched ${fetchResult.messages.length} messages');

      final fromDate = from ?? DateTime.now().subtract(const Duration(hours: 24));
      final toDate = to ?? DateTime.now();

      for (final msg in fetchResult.messages.reversed) {
        final msgDate = msg.decodeDate() ?? DateTime.now();
        if (msgDate.isBefore(fromDate) || msgDate.isAfter(toDate)) continue;

        final subject = msg.decodeSubject() ?? '';
        final sender = msg.from?.firstOrNull?.email ?? '';
        final body = msg.decodeTextPlainPart() ?? msg.decodeTextHtmlPart() ?? '';

        if (subjectKeyword.isNotEmpty &&
            !subject.toLowerCase().contains(subjectKeyword.toLowerCase()) &&
            !body.toLowerCase().contains(subjectKeyword.toLowerCase())) {
          continue;
        }

        final otp = _extractOtpFromText(body) ?? _extractOtpFromText(subject);
        results.add(EmailSearchResult(
          subject: subject.isEmpty ? '(no subject)' : subject,
          sender: sender,
          body: body.length > 300 ? body.substring(0, 300) : body,
          date: msgDate,
          otpFound: otp,
        ));
      }
      _log('SEARCH', 'Found ${results.length} matching emails');
    } catch (e) {
      _log('SEARCH', 'ERROR: $e');
      rethrow;
    } finally {
      try {
        await client.logout();
        _log('SEARCH', 'Logged out ✓');
      } catch (_) {}

      // Resume poll timer if it was running
      if (wasRunning && _config != null) {
        _log('SEARCH', 'Resuming poll timer...');
        _pollTimer = Timer.periodic(
          Duration(seconds: _config!.pollIntervalSeconds),
          (_) => _poll(),
        );
      }
    }
    return results;
  }

  String? _extractOtpFromText(String text) {
    final patterns = [
      r'【パスコード】\s*(\d{6})',
      r'(?:パスコード|コード)[:：\s]+(\d{6})',
      r'\b(\d{6})\b',
    ];
    for (final p in patterns) {
      try {
        final m = RegExp(p).firstMatch(text);
        if (m != null) return m.group(1) ?? m.group(0);
      } catch (_) {}
    }
    return null;
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

    final fallback = _extractOtpFromText(body) ?? _extractOtpFromText(subject);
    if (fallback != null) {
      return OtpEntry(
        code: fallback,
        sender: sender,
        subject: subject,
        timestamp: msg.decodeDate() ?? DateTime.now(),
      );
    }
    return null;
  }

  Future<bool> testConnection(ImapConfig config) async {
    _log('TEST', 'Testing ${config.host}:${config.port}...');
    final client = ImapClient(isLogEnabled: false);
    try {
      await client.connectToServer(config.host, config.port, isSecure: config.isSecure);
      _log('TEST', 'Connected ✓');
      await client.login(config.username, config.password);
      _log('TEST', 'Logged in ✓');
      await client.logout();
      _log('TEST', 'OK ✓');
      return true;
    } catch (e) {
      _log('TEST', 'Failed: $e');
      try { await client.logout(); } catch (_) {}
      return false;
    }
  }

  void dispose() {
    stop();
    _otpController.close();
  }
}
