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
  bool _polling = false;

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
    await _closeClient();
    _log('CONNECT', 'Connecting to ${config.host}:${config.port}...');
    final client = ImapClient(isLogEnabled: false);
    try {
      await client.connectToServer(config.host, config.port, isSecure: config.isSecure);
      _log('CONNECT', 'Connected ✓');
      await client.login(config.username, config.password);
      _log('CONNECT', 'Logged in ✓');
      await client.selectMailboxByPath('INBOX');
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
    _log('FETCH', 'Fetching...');
    try {
      // Reuse existing connection if alive (much faster)
      if (_client == null) {
        _log('FETCH', 'No connection, connecting...');
        await _connect();
      }
      return await _poll();
    } catch (e) {
      // Connection dead — reconnect once and retry
      _log('FETCH', 'Connection error ($e), reconnecting...');
      try {
        await _closeClient();
        await _connect();
        return await _poll();
      } catch (e2) {
        _log('FETCH', 'Retry failed: $e2');
        await _closeClient();
        return [];
      }
    }
  }

  Future<List<OtpEntry>> _poll() async {
    if (_polling) {
      _log('POLL', 'Skipped (busy)');
      return [];
    }
    _polling = true;
    final results = <OtpEntry>[];
    try {
      if (_client == null) await _connect();

      final mailbox = await _client!.selectMailboxByPath('INBOX');
      final count = mailbox.messagesExists;
      _log('POLL', 'Messages: $count');
      if (count == 0) return results;

      // Search for recent emails using server-side date filter
      final since = DateTime.now().subtract(const Duration(hours: 1));
      final searchBuilder = SearchQueryBuilder.from(
        '',
        SearchQueryType.allTextHeaders,
        since: since,
      );
      final criteria = searchBuilder.toString();
      _log('POLL', 'Searching: $criteria');

      final searchResult = await _client!.searchMessages(
        searchCriteria: criteria.isEmpty ? 'ALL' : criteria,
      );
      final seq = searchResult.matchingSequence;
      if (seq == null || seq.isEmpty) {
        _log('POLL', 'No recent messages');
        return results;
      }

      final ids = seq.toList();
      // Limit to last 20 to avoid heavy fetch
      final limited = ids.length > 20 ? ids.sublist(ids.length - 20) : ids;
      _log('POLL', 'Fetching ${limited.length} recent messages...');

      final batch = MessageSequence.fromIds(limited);
      final fetchResult = await _client!.fetchMessages(batch, '(BODY.PEEK[])');
      _log('POLL', 'Got ${fetchResult.messages.length} messages');

      final toMarkRead = <int>[];
      for (final msg in fetchResult.messages) {
        final entry = _extractOtp(msg);
        if (entry != null && !_otpController.isClosed) {
          results.add(entry);
          _log('POLL', 'OTP: ${entry.code} → ${entry.recipient}');
          _otpController.add(entry);
          if (msg.sequenceId != null) toMarkRead.add(msg.sequenceId!);
        }
      }
      // Đánh dấu đã đọc
      if (toMarkRead.isNotEmpty) {
        try {
          await _client!.store(
            MessageSequence.fromIds(toMarkRead),
            [r'\Seen'],
            action: StoreAction.add,
          );
          _log('POLL', 'Marked ${toMarkRead.length} as read');
        } catch (e) {
          _log('POLL', 'Mark read error: $e');
        }
      }
    } catch (e) {
      _log('POLL', 'Error: $e');
      await _closeClient();
    } finally {
      _polling = false;
    }
    return results;
  }

  /// Tìm email theo keyword trong subject/body + khoảng thời gian
  Future<List<EmailSearchResult>> searchEmails({
    required ImapConfig config,
    String subjectKeyword = '',
    String bodyKeyword = '',
    DateTime? from,
    DateTime? to,
    int maxMessages = 30,
  }) async {
    final results = <EmailSearchResult>[];

    // Pause poll timer to free connection slot
    final wasRunning = _isRunning;
    _pollTimer?.cancel();
    _pollTimer = null;
    _log('SEARCH', 'Paused poll, closing existing connection...');
    await _closeClient();

    _log('SEARCH', 'Connecting...');
    final client = ImapClient(isLogEnabled: false);
    try {
      await client.connectToServer(config.host, config.port, isSecure: config.isSecure);
      _log('SEARCH', 'Connected ✓');
      await client.login(config.username, config.password);
      _log('SEARCH', 'Logged in ✓');
      await client.selectMailboxByPath('INBOX');
      _log('SEARCH', 'Inbox selected ✓');

      // Build server-side search criteria (date range + keyword)
      final searchBuilder = SearchQueryBuilder.from(
        subjectKeyword,
        SearchQueryType.allTextHeaders,
        since: from,
        before: to?.add(const Duration(days: 1)),
      );
      final criteria = searchBuilder.toString();
      _log('SEARCH', 'Criteria: ${criteria.isEmpty ? "ALL" : criteria}');

      final searchResult = await client.searchMessages(
        searchCriteria: criteria.isEmpty ? 'ALL' : criteria,
      );
      final seq = searchResult.matchingSequence;
      if (seq == null || seq.isEmpty) {
        _log('SEARCH', 'No matches on server');
        return results;
      }

      _log('SEARCH', 'Server matched ${seq.length} emails');

      // Limit to maxMessages, take latest
      final ids = seq.toList();
      final limited = ids.length > maxMessages
          ? ids.sublist(ids.length - maxMessages)
          : ids;

      // Batch fetch (25 per batch)
      const batchSize = 25;
      final fromDate = from ?? DateTime.now().subtract(const Duration(hours: 24));
      final toDate = to ?? DateTime.now();

      for (var i = 0; i < limited.length; i += batchSize) {
        final end = (i + batchSize < limited.length) ? i + batchSize : limited.length;
        final batchIds = MessageSequence.fromIds(limited.sublist(i, end));
        _log('SEARCH', 'Batch ${i ~/ batchSize + 1}: fetching ${end - i} messages...');

        final fetchResult = await client.fetchMessages(batchIds, '(BODY.PEEK[])');
        _log('SEARCH', 'Got ${fetchResult.messages.length}');

        for (final msg in fetchResult.messages.reversed) {
          final msgDate = msg.decodeDate() ?? DateTime.now();
          if (msgDate.isBefore(fromDate) || msgDate.isAfter(toDate)) continue;

          final subject = msg.decodeSubject() ?? '';
          final sender = msg.from?.firstOrNull?.email ?? '';
          final body = msg.decodeTextPlainPart() ?? msg.decodeTextHtmlPart() ?? '';

          // Lọc theo body keyword nếu có
          if (bodyKeyword.isNotEmpty) {
            if (!body.toLowerCase().contains(bodyKeyword.toLowerCase()) &&
                !subject.toLowerCase().contains(bodyKeyword.toLowerCase())) {
              continue;
            }
          }

          final otp = _extractOtpFromText(body) ?? _extractOtpFromText(subject);
          results.add(EmailSearchResult(
            subject: subject.isEmpty ? '(no subject)' : subject,
            sender: sender,
            body: body.length > 500 ? body.substring(0, 500) : body,
            date: msgDate,
            otpFound: otp,
          ));
        }
      }
      _log('SEARCH', '✓ Found ${results.length} matching emails');
    } catch (e) {
      _log('SEARCH', 'ERROR: $e');
      rethrow;
    } finally {
      try {
        await client.logout();
        _log('SEARCH', 'Logged out ✓');
      } catch (_) {}

      // Resume poll timer
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

  /// Lấy địa chỉ email thuần từ chuỗi "Name <email>" hoặc "Hide My Email <email>"
  String _parseEmail(String raw) {
    final match = RegExp(r'<([^>]+@[^>]+)>').firstMatch(raw);
    return (match?.group(1) ?? raw).trim().toLowerCase();
  }

  OtpEntry? _extractOtp(MimeMessage msg) {
    final sender = msg.from?.firstOrNull?.email ?? '';
    final subject = msg.decodeSubject() ?? '';
    final body = msg.decodeTextPlainPart() ?? msg.decodeTextHtmlPart() ?? '';

    // Lấy email người nhận (xử lý cả "Hide My Email <real@email.com>")
    final toRaw = msg.to?.firstOrNull?.toString() ?? '';
    final recipient = _parseEmail(toRaw);

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
            recipient: recipient.isNotEmpty ? recipient : null,
            timestamp: msg.decodeDate() ?? DateTime.now(),
          );
        }
      }
    }

    // Chỉ dùng fallback khi chưa có rule nào
    if (_rules.isEmpty) {
      final fallback = _extractOtpFromText(body) ?? _extractOtpFromText(subject);
      if (fallback != null) {
        return OtpEntry(
          code: fallback,
          sender: sender,
          subject: subject,
          recipient: recipient.isNotEmpty ? recipient : null,
          timestamp: msg.decodeDate() ?? DateTime.now(),
        );
      }
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
