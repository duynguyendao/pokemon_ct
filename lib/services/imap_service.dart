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
      await _selectSearchMailbox(client);

      final keyword = subjectKeyword.isNotEmpty ? subjectKeyword : bodyKeyword;
      var searchResult = await _searchByDateAndKeyword(
        client,
        keyword: keyword,
        from: from,
        to: to,
      );
      var sequence = searchResult.matchingSequence;

      if ((sequence == null || sequence.isEmpty) && keyword.isNotEmpty) {
        _log(
          'SEARCH',
          'Keyword search empty, falling back to date-only search',
        );
        searchResult = await _searchByDateAndKeyword(
          client,
          from: from,
          to: to,
        );
        sequence = searchResult.matchingSequence;
      }

      if (sequence == null || sequence.isEmpty) {
        _log('SEARCH', 'No messages found on server');
        return [];
      }

      final ids = sequence.toList().reversed.take(80).toList();
      _log(
        'SEARCH',
        'Server matched ${sequence.length}, fetching ${ids.length}',
      );

      final results = <ImapEmailResult>[];
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
              message.from?.first.email ?? message.from?.first.toString() ?? '';
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
              otpFound: _extractOtp(sender, subject, body),
            ),
          );

          if (results.length >= maxMessages) {
            break;
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
    int maxMessages = 50,
    Duration maxAge = const Duration(minutes: 10),
  }) async {
    final client = ImapClient();

    try {
      await _connectClient(client, host, port, username, password);
      await _selectSearchMailbox(client);

      final since = DateTime.now().subtract(maxAge);
      final searchResult = await _searchByDateAndKeyword(client, from: since);
      final sequence = searchResult.matchingSequence;

      if (sequence == null || sequence.isEmpty) {
        return [];
      }

      final ids = sequence.toList().reversed.take(maxMessages).toList();
      final fetched = await client.fetchMessages(
        MessageSequence.fromIds(ids),
        '(BODY.PEEK[])',
      );
      final otps = <OtpEntry>[];

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
        if (!_matchesFilter(sender, subject, recipient ?? '', body)) {
          continue;
        }

        final otp = _extractOtp(sender, subject, body);
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

      final searchResult = await _client.uidSearchMessages(
        searchCriteria: 'UNSEEN',
      );
      final unreadMessages = searchResult.matchingSequence;

      if (unreadMessages == null || unreadMessages.isEmpty) {
        return;
      }

      _log('FETCH', 'Found ${unreadMessages.length} unseen email(s)');

      final messages = await _client.uidFetchMessages(
        unreadMessages,
        '(UID FLAGS BODY.PEEK[])',
      );

      final now = DateTime.now();

      for (final msg in messages.messages) {
        final uid = msg.uid ?? 0;
        if (uid > 0 && !_processedUids.add(uid)) continue;

        // Check age
        final msgDate = msg.decodeDate() ?? DateTime.now();
        if (now.difference(msgDate).inMinutes > 2) continue;

        final sender = msg.from?.first.email ?? '';
        final recipient = msg.to?.first.email ?? msg.to?.first.toString();
        final subject = msg.decodeSubject() ?? '';
        final body = _decodeBody(msg);

        // Match filter
        if (!_matchesFilter(sender, subject, recipient ?? '', body)) continue;

        // Extract OTP
        final otp = _extractOtp(sender, subject, body);
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

  Future<void> _selectSearchMailbox(ImapClient client) async {
    for (final folder in const ['[Gmail]/All Mail', 'INBOX']) {
      try {
        await client.selectMailboxByPath(folder);
        _log('MAILBOX', 'Selected $folder');
        return;
      } catch (_) {}
    }

    await client.selectInbox();
    _log('MAILBOX', 'Selected INBOX fallback');
  }

  Future<SearchImapResult> _searchByDateAndKeyword(
    ImapClient client, {
    String keyword = '',
    DateTime? from,
    DateTime? to,
  }) {
    final builder = SearchQueryBuilder.from(
      keyword,
      SearchQueryType.allTextHeaders,
      since: from,
      before: to?.add(const Duration(days: 1)),
    );
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

  bool _matchesFilter(
    String sender,
    String subject,
    String recipient,
    String body,
  ) {
    if (_rules.isEmpty) return true;

    for (final rule in _rules) {
      var matches = false;
      final pattern = rule.pattern.toLowerCase();

      switch (rule.type) {
        case FilterType.sender:
          matches = sender.toLowerCase().contains(pattern);
          break;
        case FilterType.subject:
          matches = subject.toLowerCase().contains(pattern);
          break;
        case FilterType.recipient:
          matches = recipient.toLowerCase().contains(pattern);
          break;
        case FilterType.body:
          matches = body.toLowerCase().contains(pattern);
          break;
        case FilterType.regex:
          try {
            final regex = RegExp(rule.pattern, caseSensitive: false);
            matches = regex.hasMatch('$sender\n$recipient\n$subject\n$body');
          } catch (_) {}
          break;
      }

      if (matches) return true;
    }

    return false;
  }

  String? _extractOtp(String sender, String subject, String body) {
    for (final rule in _rules) {
      final otp = rule.extractOtp(body) ?? rule.extractOtp(subject);
      if (otp != null) return otp;
    }

    final match = RegExp(r'\b\d{6}\b').firstMatch('$subject\n$body');
    return match?.group(0);
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
