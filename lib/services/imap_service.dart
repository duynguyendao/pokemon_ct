import 'dart:async';
import 'package:enough_mail/enough_mail.dart';
import '../models/otp_entry.dart';
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

class _IdleNewMail {
  final int oldCount;
  final int newCount;

  const _IdleNewMail(this.oldCount, this.newCount);

  bool get hasNewMail => newCount > oldCount;

  MessageSequence toMessageSequence() {
    final first = oldCount + 1;
    final last = newCount;
    return first == last
        ? MessageSequence.fromId(last)
        : MessageSequence.fromRange(first, last);
  }
}

class ImapService {
  static const _connectTimeout = Duration(seconds: 6);

  ImapClient? _client;
  bool _isRunning = false;
  bool _isIdleRunning = false;
  String? _host;
  int? _port;
  String? _username;
  String? _password;
  int? _lastExists;

  final Set<int> _processedUids = {};

  final _otpController = StreamController<OtpEntry>.broadcast();
  Stream<OtpEntry> get otpStream => _otpController.stream;
  bool get isRunning => _isRunning;

  static String normalizePassword(String password) {
    return password.replaceAll(RegExp(r'\s+'), '');
  }

  Future<void> testConnection({
    required String host,
    required int port,
    required String username,
    required String password,
  }) async {
    final client = ImapClient();

    try {
      await _connectClient(client, host, port, username, password);
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
    int maxMessages = 3,
    Duration maxAge = const Duration(minutes: 2),
  }) async {
    final client = ImapClient();
    final stopwatch = Stopwatch()..start();

    try {
      final inbox = await _connectClient(
        client,
        host,
        port,
        username,
        password,
      );

      final otps = <OtpEntry>[];
      final latestSequence = _latestInboxSequence(inbox, maxMessages);

      if (latestSequence != null) {
        _log(
          'FETCH_NOW',
          'Fetching latest $maxMessages from INBOX (${inbox.messagesExists} total)',
        );
        final fetched = await _fetchFullTextMessages(client, latestSequence);

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

      _log(
        'FETCH_NOW',
        'Found ${otps.length} OTP(s) in ${stopwatch.elapsedMilliseconds}ms',
      );
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

  MessageSequence? _latestInboxSequence(Mailbox inbox, int maxMessages) {
    final latest = inbox.messagesExists;
    if (latest <= 0 || maxMessages <= 0) {
      return null;
    }

    final first = latest - maxMessages + 1;
    return MessageSequence.fromRange(first < 1 ? 1 : first, latest);
  }

  Future<void> start({
    required String host,
    required int port,
    required String username,
    required String password,
  }) async {
    if (_isRunning) return;

    _isRunning = true;
    _host = host;
    _port = port;
    _username = username;
    _password = password;
    _log('START', 'Starting IMAP...');

    try {
      await _ensureConnected();

      _log('START', 'Connected OK');

      _startIdleLoop();
    } catch (e) {
      _isRunning = false;
      _log('START', 'Failed: $e');
      rethrow;
    }
  }

  void _startIdleLoop() {
    _isIdleRunning = true;
    unawaited(_runIdleLoop());
  }

  Future<void> _runIdleLoop() async {
    while (_isRunning && _isIdleRunning) {
      try {
        final client = await _ensureConnected();

        _log('IDLE', 'Waiting for mail...');
        final newMail = await _waitForNewMail(client);

        if (!_isRunning || !_isIdleRunning) break;

        if (newMail?.hasNewMail == true) {
          _lastExists = newMail!.newCount;
          _log(
            'IDLE',
            'New mail detected ${newMail.oldCount}->${newMail.newCount}',
          );
          await _fetchNew(client, newMail);
        }
      } catch (e) {
        _log('IDLE', 'Error: $e');
        await _disconnectClient();

        if (_isRunning && _isIdleRunning) {
          await Future.delayed(Duration(seconds: 5));
        }
      }
    }
  }

  Future<_IdleNewMail?> _waitForNewMail(ImapClient idleClient) async {
    final newMail = Completer<_IdleNewMail>();
    final subscription = idleClient.eventBus
        .on<ImapMessagesExistEvent>()
        .listen((event) {
          if (!newMail.isCompleted) {
            newMail.complete(
              _IdleNewMail(event.oldMessagesExists, event.newMessagesExists),
            );
          }
        });

    try {
      await idleClient.idleStart();
      await Future.any([newMail.future, Future.delayed(Duration(seconds: 8))]);
    } finally {
      await subscription.cancel();
      try {
        await idleClient.idleDone();
      } catch (_) {}
    }

    if (newMail.isCompleted) {
      return await newMail.future;
    }

    try {
      final mailbox = await idleClient.noop();
      final newCount = mailbox?.messagesExists;
      final oldCount = _lastExists;
      if (newCount != null && oldCount != null && newCount > oldCount) {
        _log('HEARTBEAT', 'NOOP detected new mail $oldCount->$newCount');
        return _IdleNewMail(oldCount, newCount);
      }

      if (newCount != null) {
        _lastExists = newCount;
      }
      _log('HEARTBEAT', 'NOOP OK');
    } catch (e) {
      _log('HEARTBEAT', 'NOOP failed: $e');
      rethrow;
    }

    return null;
  }

  Future<ImapClient> _ensureConnected() async {
    final existing = _client;
    if (existing != null && existing.isConnected) {
      return existing;
    }

    final host = _host;
    final port = _port;
    final username = _username;
    final password = _password;

    if (host == null || port == null || username == null || password == null) {
      throw StateError('IMAP config is not available for reconnect.');
    }

    await _disconnectClient();
    final client = ImapClient();
    _client = client;
    _log('RECONNECT', 'Connecting...');
    await _connectClient(client, host, port, username, password);
    _log('RECONNECT', 'Connected OK');
    return client;
  }

  Future<void> _disconnectClient() async {
    final client = _client;
    _client = null;
    _lastExists = null;
    if (client == null) {
      return;
    }

    try {
      await client.logout();
    } catch (_) {}
    try {
      await client.disconnect();
    } catch (_) {}
  }

  Future<void> _fetchNew(ImapClient client, _IdleNewMail newMail) async {
    try {
      if (!client.isConnected) return;

      final sequence = newMail.toMessageSequence();
      final messages = await _fetchFullTextMessages(client, sequence);

      final now = DateTime.now();

      for (final msg in messages.messages) {
        final uid = msg.uid ?? 0;
        if (uid > 0 && _processedUids.contains(uid)) continue;

        final msgDate = msg.decodeDate() ?? DateTime.now();
        if (now.difference(msgDate).inHours >= 2) continue;

        final sender = msg.from?.first.email ?? '';
        final recipient = msg.to?.first.email ?? msg.to?.first.toString();
        final subject = msg.decodeSubject() ?? '';
        final body = _decodeBody(msg);

        final otp = extractOtp(sender: sender, subject: subject, body: body);
        if (otp != null && !_otpController.isClosed) {
          if (uid > 0) _processedUids.add(uid);
          _emitOtp(
            otp: otp,
            sender: sender,
            subject: subject,
            recipient: recipient,
            timestamp: msgDate,
          );
        }
      }
    } catch (e) {
      _log('FETCH', 'Error: $e');
    }
  }

  Future<FetchImapResult> _fetchFullTextMessages(
    ImapClient client,
    MessageSequence sequence,
  ) async {
    final stopwatch = Stopwatch()..start();
    final result = await client.fetchMessages(
      sequence,
      '(UID ENVELOPE BODY.PEEK[TEXT])',
    );
    _log('FETCH', 'Text body fetched in ${stopwatch.elapsedMilliseconds}ms');
    return result;
  }

  void _emitOtp({
    required String otp,
    required String sender,
    required String subject,
    required String? recipient,
    required DateTime timestamp,
  }) {
    _log('FETCH', 'OTP: $otp');
    _otpController.add(
      OtpEntry(
        code: otp,
        sender: sender,
        subject: subject,
        recipient: recipient,
        timestamp: timestamp,
      ),
    );
  }

  Future<Mailbox> _connectClient(
    ImapClient client,
    String host,
    int port,
    String username,
    String password,
  ) async {
    final stopwatch = Stopwatch()..start();

    await client.connectToServer(
      host,
      port,
      isSecure: port == 993,
      timeout: _connectTimeout,
    );
    _log('CONNECT', 'Socket ready in ${stopwatch.elapsedMilliseconds}ms');

    await client.login(username, normalizePassword(password));
    _log('CONNECT', 'Login OK in ${stopwatch.elapsedMilliseconds}ms');

    final inbox = await _selectInboxFast(client);
    _lastExists = inbox.messagesExists;
    _log('CONNECT', 'INBOX selected in ${stopwatch.elapsedMilliseconds}ms');
    return inbox;
  }

  Future<bool> _trySelectMailbox(ImapClient client, String mailbox) async {
    try {
      if (mailbox.toUpperCase() == 'INBOX') {
        await _selectInboxFast(client);
      } else {
        await client.selectMailboxByPath(mailbox);
      }
      _log('MAILBOX', 'Selected $mailbox');
      return true;
    } catch (e) {
      _log('MAILBOX', 'Cannot select $mailbox: $e');
      return false;
    }
  }

  Future<Mailbox> _selectInboxFast(ImapClient client) {
    final inbox = Mailbox(
      encodedName: 'INBOX',
      encodedPath: 'INBOX',
      flags: [MailboxFlag.inbox],
      pathSeparator: '/',
    );
    return client.selectMailbox(inbox);
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
    final body =
        message.decodeTextPlainPart() ??
        message.decodeTextHtmlPart() ??
        message.decodeContentText();
    return body ?? '';
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
    await _disconnectClient();
    _host = null;
    _port = null;
    _username = null;
    _password = null;
    _lastExists = null;

    _log('STOP', 'Stopped');
  }

  void dispose() {
    stop();
    _otpController.close();
  }
}
