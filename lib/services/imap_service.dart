import 'dart:async';
import 'package:enough_mail/enough_mail.dart';
import '../models/otp_entry.dart';
import '../models/filter_rule.dart';
import 'debug_service.dart';

void _log(String tag, String msg) {
  debugService.log('[IMAP:$tag] $msg');
}

class ImapEmailResult {
  final String subject;
  final String sender;
  final String body;
  final DateTime date;
  final String? otpFound;

  const ImapEmailResult({
    required this.subject,
    required this.sender,
    required this.body,
    required this.date,
    this.otpFound,
  });
}

class ImapService {
  late ImapClient _client;
  ImapClient? _idleClient;
  bool _isRunning = false;
  bool _isIdleRunning = false;
  Timer? _heartbeatTimer;

  final Set<int> _processedUids = {};
  List<FilterRule> _rules = [];

  final _otpController = StreamController<OtpEntry>.broadcast();
  Stream<OtpEntry> get otpStream => _otpController.stream;
  bool get isRunning => _isRunning;

  static String normalizePassword(String password) {
    return password.replaceAll(RegExp(r'\s+'), '');
  }

  void setRules(List<FilterRule> rules) {
    _rules = rules.where((r) => r.enabled).toList();
  }

  Future<void> testConnection({
    required String host,
    required int port,
    required String username,
    required String password,
  }) async {
    final client = ImapClient();

    try {
      await client.connectToServer(host, port, isSecure: port == 993);
      await client.login(username, normalizePassword(password));
      await client.selectInbox();
      _log('TEST', 'Connected OK');
      await client.logout();
    } catch (e) {
      _log('TEST', 'Failed: $e');
      rethrow;
    } finally {
      try {
        await client.disconnect();
      } catch (_) {}
    }
  }

  Future<List<ImapEmailResult>> searchEmails({
    required String host,
    required int port,
    required String username,
    required String password,
    String subjectKeyword = '',
    String bodyKeyword = '',
    DateTime? from,
    DateTime? to,
    int maxMessages = 20,
  }) async {
    final client = ImapClient();

    try {
      await _connectClient(client, host, port, username, password);
      final results = <ImapEmailResult>[];

      for (final mailbox in const ['INBOX']) {
        if (results.length >= maxMessages ||
            !await _trySelectMailbox(client, mailbox)) {
          break;
        }

        final searchResult = await _searchForMessages(
          client,
          subjectKeyword: subjectKeyword,
          bodyKeyword: bodyKeyword,
          from: from,
          to: to,
        );
        final sequence = searchResult.matchingSequence;

        if (sequence == null || sequence.isEmpty) {
          _log('SEARCH', 'No messages found in $mailbox');
          continue;
        }

        final fetchLimit = _fetchLimitFor(maxMessages - results.length);
        final ids = sequence.toList().reversed.take(fetchLimit).toList();
        _log(
          'SEARCH',
          '$mailbox matched ${sequence.length}, fetching ${ids.length}',
        );

        const batchSize = 20;

        for (
          var i = 0;
          i < ids.length && results.length < maxMessages;
          i += batchSize
        ) {
          final end = (i + batchSize < ids.length) ? i + batchSize : ids.length;
          final batch = MessageSequence.fromIds(ids.sublist(i, end));
          final fetched = await client.fetchMessages(batch, '(BODY.PEEK[])');

          for (final message in fetched.messages) {
            final subject = message.decodeSubject() ?? '(No Subject)';
            final sender =
                message.from?.first.email ??
                message.from?.first.toString() ??
                '';
            final body = _decodeBody(message);
            final date = message.decodeDate() ?? DateTime.now();

            if (!_messageMatches(
              subject: subject,
              body: body,
              subjectKeyword: subjectKeyword,
              bodyKeyword: bodyKeyword,
            )) {
              continue;
            }

            results.add(
              ImapEmailResult(
                subject: subject,
                sender: sender,
                body: _preview(body),
                date: date,
                otpFound: extractOtp(
                  sender: sender,
                  subject: subject,
                  body: body,
                ),
              ),
            );

            if (results.length >= maxMessages) {
              break;
            }
          }
        }
      }

      _log('SEARCH', 'Returned ${results.length} messages');
      return results;
    } finally {
      try {
        await client.logout();
      } catch (_) {}
      try {
        await client.disconnect();
      } catch (_) {}
    }
  }

  Future<List<OtpEntry>> fetchRecentOtps({
    required String host,
    required int port,
    required String username,
    required String password,
    int maxMessages = 80,
    Duration maxAge = const Duration(hours: 2),
  }) async {
    final client = ImapClient();

    try {
      await _connectClient(client, host, port, username, password);

      final otps = <OtpEntry>[];
      for (final mailbox in const ['INBOX']) {
        if (otps.isNotEmpty || !await _trySelectMailbox(client, mailbox)) {
          break;
        }

        final since = DateTime.now().subtract(maxAge);
        final searchResult = await _searchForMessages(client, from: since);
        final sequence = searchResult.matchingSequence;

        if (sequence == null || sequence.isEmpty) {
          continue;
        }

        final ids = sequence.toList().reversed.take(maxMessages).toList();
        _log(
          'FETCH_NOW',
          '$mailbox matched ${sequence.length}, fetching ${ids.length}',
        );
        final fetched = await client.fetchMessages(
          MessageSequence.fromIds(ids),
          '(BODY.PEEK[])',
        );

        for (final message in fetched.messages) {
          final sender =
              message.from?.first.email ?? message.from?.first.toString() ?? '';
          final recipient =
              message.to?.first.email ?? message.to?.first.toString();
          final subject = message.decodeSubject() ?? '';
          final body = _decodeBody(message);
          final date = message.decodeDate() ?? DateTime.now();

          if (DateTime.now().difference(date) > maxAge) {
            continue;
          }

          final otp = extractOtp(sender: sender, subject: subject, body: body);
          if (otp == null) {
            continue;
          }

          final entry = OtpEntry(
            code: otp,
            sender: sender,
            subject: subject,
            recipient: recipient,
            timestamp: date,
          );
          otps.add(entry);

          if (!_otpController.isClosed) {
            _otpController.add(entry);
          }
        }
      }

      _log('FETCH_NOW', 'Found ${otps.length} OTP(s)');
      return otps;
    } finally {
      try {
        await client.logout();
      } catch (_) {}
      try {
        await client.disconnect();
      } catch (_) {}
    }
  }

  Future<void> start({
    required String host,
    required int port,
    required String username,
    required String password,
  }) async {
    if (_isRunning) return;

    _isRunning = true;
    _log('START', 'Starting IMAP...');

    try {
      _client = ImapClient();
      await _connectClient(_client, host, port, username, password);

      _log('START', 'Connected OK');

      _startHeartbeat();
      _startIdleLoop(host, port, username, password);
    } catch (e) {
      _isRunning = false;
      _log('START', 'Failed: $e');
      rethrow;
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(Duration(minutes: 4), (_) async {
      if (!_isRunning || !_client.isConnected) return;
      try {
        await _client.noop();
      } catch (e) {
        _log('HEARTBEAT', 'Error: $e');
      }
    });
  }

  void _startIdleLoop(String host, int port, String username, String password) {
    _isIdleRunning = true;
    unawaited(_runIdleLoop(host, port, username, password));
  }

  Future<void> _runIdleLoop(
    String host,
    int port,
    String username,
    String password,
  ) async {
    while (_isRunning && _isIdleRunning) {
      try {
        var idleClient = _idleClient;
        if (idleClient == null || !idleClient.isConnected) {
          idleClient = ImapClient();
          _idleClient = idleClient;
          await _connectClient(idleClient, host, port, username, password);
          _log('IDLE', 'Connected');
        }

        _log('IDLE', 'Waiting for mail...');
        final hasNewMail = await _waitForNewMail(idleClient);

        if (!_isRunning || !_isIdleRunning) break;

        if (hasNewMail) {
          _log('IDLE', 'New mail detected');
          await _fetchNew();
        }
      } catch (e) {
        _log('IDLE', 'Error: $e');
        try {
          await _idleClient?.disconnect();
        } catch (_) {}

        if (_isRunning && _isIdleRunning) {
          await Future.delayed(Duration(seconds: 5));
        }
      }
    }
  }

  Future<bool> _waitForNewMail(ImapClient idleClient) async {
    final newMail = Completer<void>();
    final subscription = idleClient.eventBus
        .on<ImapMessagesExistEvent>()
        .listen((_) {
          if (!newMail.isCompleted) {
            newMail.complete();
          }
        });

    try {
      await idleClient.idleStart();
      await Future.any([newMail.future, Future.delayed(Duration(minutes: 9))]);
    } finally {
      await subscription.cancel();
      try {
        await idleClient.idleDone();
      } catch (_) {}
    }

    return newMail.isCompleted;
  }

  Future<void> _fetchNew() async {
    try {
      if (!_client.isConnected) return;

      await _trySelectMailbox(_client, 'INBOX');
      final searchResult = await _searchForMessages(
        _client,
        from: DateTime.now().subtract(const Duration(hours: 2)),
      );
      final recentMessages = searchResult.matchingSequence;

      if (recentMessages == null || recentMessages.isEmpty) {
        return;
      }

      final recentIds = recentMessages.toList().reversed.take(30).toList();
      _log('FETCH', 'Found ${recentIds.length} recent email(s)');

      final messages = await _client.fetchMessages(
        MessageSequence.fromIds(recentIds),
        '(UID BODY.PEEK[])',
      );

      final now = DateTime.now();

      for (final msg in messages.messages) {
        final uid = msg.uid ?? 0;
        if (uid > 0 && !_processedUids.add(uid)) continue;

        // Check age
        final msgDate = msg.decodeDate() ?? DateTime.now();
        if (now.difference(msgDate).inHours >= 2) continue;

        final sender = msg.from?.first.email ?? '';
        final recipient = msg.to?.first.email ?? msg.to?.first.toString();
        final subject = msg.decodeSubject() ?? '';
        final body = _decodeBody(msg);

        final otp = extractOtp(sender: sender, subject: subject, body: body);
        if (otp != null && !_otpController.isClosed) {
          _log('FETCH', 'OTP: $otp');
          _otpController.add(
            OtpEntry(
              code: otp,
              sender: sender,
              subject: subject,
              recipient: recipient,
              timestamp: msgDate,
            ),
          );
        }
      }
    } catch (e) {
      _log('FETCH', 'Error: $e');
    }
  }

  Future<void> _connectClient(
    ImapClient client,
    String host,
    int port,
    String username,
    String password,
  ) async {
    await client.connectToServer(host, port, isSecure: port == 993);
    await client.login(username, normalizePassword(password));
    await client.selectInbox();
  }

  Future<bool> _trySelectMailbox(ImapClient client, String mailbox) async {
    try {
      await client.selectMailboxByPath(mailbox);
      _log('MAILBOX', 'Selected $mailbox');
      return true;
    } catch (e) {
      _log('MAILBOX', 'Cannot select $mailbox: $e');
      return false;
    }
  }

  Future<SearchImapResult> _searchForMessages(
    ImapClient client, {
    String subjectKeyword = '',
    String bodyKeyword = '',
    DateTime? from,
    DateTime? to,
  }) {
    final builder = SearchQueryBuilder.from('', SearchQueryType.subject);
    if (subjectKeyword.trim().isNotEmpty) {
      builder.add(SearchTermSubject(subjectKeyword.trim()));
    }
    if (bodyKeyword.trim().isNotEmpty) {
      builder.add(SearchTermBody(bodyKeyword.trim()));
    }
    if (from != null) {
      builder.add(SearchTermSince(from));
    }
    if (to != null) {
      builder.add(SearchTermBefore(to.add(const Duration(days: 1))));
    }

    final criteria = builder.toString();
    _log('SEARCH', 'Criteria: ${criteria.isEmpty ? 'ALL' : criteria}');

    return client.searchMessages(
      searchCriteria: criteria.isEmpty ? 'ALL' : criteria,
    );
  }

  bool _messageMatches({
    required String subject,
    required String body,
    required String subjectKeyword,
    required String bodyKeyword,
  }) {
    final searchableSubject = subject.toLowerCase();
    final searchableBody = body.toLowerCase();
    final subjectWords = subjectKeyword
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty);
    final bodyWords = bodyKeyword
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty);

    final subjectMatches = subjectWords.every(searchableSubject.contains);
    final bodyMatches = bodyWords.every(searchableBody.contains);

    return subjectMatches && bodyMatches;
  }

  String _decodeBody(MimeMessage message) {
    return message.decodeTextPlainPart() ?? message.decodeTextHtmlPart() ?? '';
  }

  String _preview(String body) {
    final collapsed = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return collapsed.length > 800 ? collapsed.substring(0, 800) : collapsed;
  }

  int _fetchLimitFor(int desiredResults) {
    if (desiredResults <= 0) {
      return 0;
    }
    final limit = desiredResults * 8;
    if (limit < 20) {
      return 20;
    }
    return limit > 60 ? 60 : limit;
  }

  String? extractOtp({
    required String sender,
    required String subject,
    required String body,
  }) {
    final normalizedSubject = _normalizeDigits(subject);
    final normalizedBody = _normalizeDigits(body);

    for (final rule in _rules) {
      final otp =
          rule.extractOtp(normalizedBody) ?? rule.extractOtp(normalizedSubject);
      if (otp != null) return otp;
    }

    final text = '$normalizedSubject\n$normalizedBody';

    final compactMatch = RegExp(r'(^|[^\d])(\d{6})(?!\d)').firstMatch(text);
    if (compactMatch != null) {
      return compactMatch.group(2);
    }

    final spacedMatch = RegExp(
      r'(^|[^\d])((\d[\s\-_.]*){6})(?!\d)',
    ).firstMatch(text);
    if (spacedMatch != null) {
      final digits = RegExp(r'\d')
          .allMatches(spacedMatch.group(2) ?? '')
          .map((match) => match.group(0)!)
          .join();
      if (digits.length == 6) {
        return digits;
      }
    }

    return null;
  }

  String _normalizeDigits(String text) {
    const fullWidthZero = 0xff10;
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (rune >= fullWidthZero && rune <= fullWidthZero + 9) {
        buffer.writeCharCode(0x30 + rune - fullWidthZero);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  Future<void> stop() async {
    _isRunning = false;
    _isIdleRunning = false;
    _heartbeatTimer?.cancel();

    try {
      await _client.logout();
    } catch (_) {}

    try {
      await _idleClient?.disconnect();
    } catch (_) {}

    _log('STOP', 'Stopped');
  }

  void dispose() {
    stop();
    _otpController.close();
  }
}
