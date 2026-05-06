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

/// Polling-based IMAP service.
///
/// Strategy:
///   1. Login once, keep one connection alive across all polls
///   2. Every 2s: SELECT/NOOP and check if INBOX message count grew (cheap)
///   3. If grew: fetch only the new range, parse, dedupe by UID, emit OTP
///   4. Every 4 minutes: send NOOP heartbeat to keep NAT/Gmail from dropping
///   5. On any error: tear down + reconnect on next tick
///
/// Why poll over IDLE here:
///   - On 4G/5G, NAT can silently kill an idle TCP socket after ~30s with no
///     keepalive. IDLE notification gets lost; reconnect adds latency.
///   - 2s poll has worst-case 2s latency, IDLE has best-case ~1s but variable.
///   - Simpler code path = fewer race conditions.
class ImapService {
  static const _connectTimeout = Duration(seconds: 6);
  static const _pollInterval = Duration(seconds: 2);
  static const _heartbeatInterval = Duration(minutes: 4);
  static const _maxOtpAge = Duration(minutes: 5);

  ImapClient? _client;
  bool _isRunning = false;
  String? _host;
  int? _port;
  String? _username;
  String? _password;

  int? _lastExists;
  Timer? _pollTimer;
  DateTime? _lastHeartbeat;
  bool _polling = false;

  final Set<int> _processedUids = {};

  final _otpController = StreamController<OtpEntry>.broadcast();
  Stream<OtpEntry> get otpStream => _otpController.stream;
  bool get isRunning => _isRunning;

  static String normalizePassword(String password) {
    return password.replaceAll(RegExp(r'\s+'), '');
  }

  // ─── Public API ────────────────────────────────────────────────────────

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
    _processedUids.clear();
    _log('START', 'Starting IMAP poll loop ($_pollInterval)...');

    try {
      await _ensureConnected();
      _log('START', 'Initial connect OK, mailbox has $_lastExists messages');
      _lastHeartbeat = DateTime.now();
      _startPollTimer();
    } catch (e) {
      _isRunning = false;
      _log('START', 'Failed: $e');
      rethrow;
    }
  }

  Future<void> stop() async {
    _isRunning = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _disconnectClient();
    _host = null;
    _port = null;
    _username = null;
    _password = null;
    _lastExists = null;
    _lastHeartbeat = null;
    _log('STOP', 'Stopped');
  }

  void dispose() {
    stop();
    _otpController.close();
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

  /// One-shot fetch of latest N messages, used by manual "fetch now" UI.
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
        client, host, port, username, password,
      );
      final results = <OtpEntry>[];
      final sequence = _latestSequenceFromCount(
        inbox.messagesExists,
        maxMessages,
      );

      if (sequence != null) {
        final fetched = await _fetchFullText(client, sequence);
        for (final msg in fetched.messages) {
          final entry = _parseMessage(msg, maxAge: maxAge);
          if (entry != null) {
            results.add(entry);
            if (!_otpController.isClosed) _otpController.add(entry);
          }
        }
      }
      _log('FETCH_NOW', '${results.length} OTP(s) in ${stopwatch.elapsedMilliseconds}ms');
      return results;
    } finally {
      try { await client.logout(); } catch (_) {}
      try { await client.disconnect(); } catch (_) {}
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
      if (!await _trySelectInbox(client)) return results;

      final criteria = _buildSearchCriteria(
        subjectKeyword: subjectKeyword,
        bodyKeyword: bodyKeyword,
        from: from,
        to: to,
      );
      final search = await client.searchMessages(searchCriteria: criteria);
      final sequence = search.matchingSequence;
      if (sequence == null || sequence.isEmpty) return results;

      final ids = sequence.toList().reversed.take(maxMessages).toList();
      const batchSize = 20;
      for (var i = 0; i < ids.length; i += batchSize) {
        final end = (i + batchSize < ids.length) ? i + batchSize : ids.length;
        final batch = MessageSequence.fromIds(ids.sublist(i, end));
        final fetched = await client.fetchMessages(batch, '(BODY.PEEK[])');

        for (final msg in fetched.messages) {
          final subject = msg.decodeSubject() ?? '(No Subject)';
          final sender = msg.from?.first.email ?? '';
          final body = _decodeBody(msg);
          final date = msg.decodeDate() ?? DateTime.now();

          if (!_messageMatches(
            subject: subject,
            body: body,
            subjectKeyword: subjectKeyword,
            bodyKeyword: bodyKeyword,
          )) {
            continue;
          }

          results.add(ImapEmailResult(
            subject: subject,
            sender: sender,
            body: _preview(body),
            date: date,
            otpFound: extractOtp(sender: sender, subject: subject, body: body),
          ));
          if (results.length >= maxMessages) break;
        }
        if (results.length >= maxMessages) break;
      }
      return results;
    } finally {
      try { await client.logout(); } catch (_) {}
      try { await client.disconnect(); } catch (_) {}
    }
  }

  // ─── Polling loop ──────────────────────────────────────────────────────

  void _startPollTimer() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _tick());
  }

  Future<void> _tick() async {
    if (!_isRunning || _polling) return;
    _polling = true;
    try {
      final client = await _ensureConnected();

      // Heartbeat NOOP every 4 min keeps NAT alive + Gmail from idling us
      final now = DateTime.now();
      final lastBeat = _lastHeartbeat;
      if (lastBeat == null ||
          now.difference(lastBeat) > _heartbeatInterval) {
        _lastHeartbeat = now;
      }

      // Cheap NOOP — server reports current message count
      final mailbox = await client.noop().timeout(
        const Duration(seconds: 4),
      );
      final newCount = mailbox?.messagesExists;
      final oldCount = _lastExists;

      if (newCount == null) return;

      if (oldCount == null) {
        _lastExists = newCount;
        return;
      }

      if (newCount > oldCount) {
        _log('POLL', 'New mail $oldCount -> $newCount');
        final sequence = MessageSequence.fromRange(oldCount + 1, newCount);
        _lastExists = newCount;
        await _fetchAndEmit(client, sequence);
      } else if (newCount < oldCount) {
        // mail was deleted — just resync count
        _lastExists = newCount;
      }
    } catch (e) {
      _log('POLL', 'Error: $e — reconnect on next tick');
      await _disconnectClient();
    } finally {
      _polling = false;
    }
  }

  Future<void> _fetchAndEmit(
    ImapClient client,
    MessageSequence sequence,
  ) async {
    try {
      final result = await _fetchFullText(client, sequence);
      for (final msg in result.messages) {
        final entry = _parseMessage(msg, maxAge: _maxOtpAge);
        if (entry != null && !_otpController.isClosed) {
          _otpController.add(entry);
        }
      }
    } catch (e) {
      _log('FETCH', 'Error: $e');
    }
  }

  OtpEntry? _parseMessage(MimeMessage msg, {required Duration maxAge}) {
    final uid = msg.uid ?? 0;
    if (uid > 0 && _processedUids.contains(uid)) return null;

    final date = msg.decodeDate() ?? DateTime.now();
    if (DateTime.now().difference(date) > maxAge) return null;

    final sender = msg.from?.first.email ?? '';
    final recipient = msg.to?.first.email;
    final subject = msg.decodeSubject() ?? '';
    final body = _decodeBody(msg);

    final otp = extractOtp(sender: sender, subject: subject, body: body);
    if (otp == null) return null;

    if (uid > 0) _processedUids.add(uid);
    _log('FETCH', 'OTP: $otp (uid=$uid)');

    return OtpEntry(
      code: otp,
      sender: sender,
      subject: subject,
      recipient: recipient,
      timestamp: date,
    );
  }

  // ─── Connection management ─────────────────────────────────────────────

  Future<ImapClient> _ensureConnected() async {
    final existing = _client;
    if (existing != null && existing.isConnected) return existing;

    final host = _host;
    final port = _port;
    final username = _username;
    final password = _password;
    if (host == null || port == null || username == null || password == null) {
      throw StateError('IMAP config not available for reconnect.');
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
    if (client == null) return;
    try { await client.logout(); } catch (_) {}
    try { await client.disconnect(); } catch (_) {}
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
      host, port,
      isSecure: port == 993,
      timeout: _connectTimeout,
    );
    _log('CONNECT', 'Socket ${stopwatch.elapsedMilliseconds}ms');

    await client.login(username, normalizePassword(password));
    _log('CONNECT', 'Login ${stopwatch.elapsedMilliseconds}ms');

    final inbox = await _selectInboxFast(client);
    _lastExists = inbox.messagesExists;
    _log('CONNECT', 'INBOX selected ${stopwatch.elapsedMilliseconds}ms');
    return inbox;
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

  Future<bool> _trySelectInbox(ImapClient client) async {
    try {
      await _selectInboxFast(client);
      return true;
    } catch (e) {
      _log('MAILBOX', 'Cannot select INBOX: $e');
      return false;
    }
  }

  // ─── Fetching & parsing ────────────────────────────────────────────────

  Future<FetchImapResult> _fetchFullText(
    ImapClient client,
    MessageSequence sequence,
  ) async {
    final sw = Stopwatch()..start();
    final result = await client.fetchMessages(
      sequence,
      '(UID ENVELOPE BODY.PEEK[TEXT])',
    );
    _log('FETCH', 'Body fetched in ${sw.elapsedMilliseconds}ms');
    return result;
  }

  MessageSequence? _latestSequenceFromCount(int latest, int maxMessages) {
    if (latest <= 0 || maxMessages <= 0) return null;
    final first = latest - maxMessages + 1;
    return MessageSequence.fromRange(first < 1 ? 1 : first, latest);
  }

  String _buildSearchCriteria({
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
    if (from != null) builder.add(SearchTermSince(from));
    if (to != null) {
      builder.add(SearchTermBefore(to.add(const Duration(days: 1))));
    }
    final criteria = builder.toString();
    return criteria.isEmpty ? 'ALL' : criteria;
  }

  bool _messageMatches({
    required String subject,
    required String body,
    required String subjectKeyword,
    required String bodyKeyword,
  }) {
    final s = subject.toLowerCase();
    final b = body.toLowerCase();
    final sw = subjectKeyword.toLowerCase().split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);
    final bw = bodyKeyword.toLowerCase().split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);
    return sw.every(s.contains) && bw.every(b.contains);
  }

  String _decodeBody(MimeMessage message) {
    return message.decodeTextPlainPart() ??
        message.decodeTextHtmlPart() ??
        message.decodeContentText() ??
        '';
  }

  String _preview(String body) {
    final c = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return c.length > 800 ? c.substring(0, 800) : c;
  }

  // ─── OTP extraction ────────────────────────────────────────────────────

  String? extractOtp({
    required String sender,
    required String subject,
    required String body,
  }) {
    final text = '${_normalizeDigits(subject)}\n${_normalizeDigits(body)}';

    final compact = RegExp(r'(^|[^\d])(\d{6})(?!\d)').firstMatch(text);
    if (compact != null) return compact.group(2);

    final spaced = RegExp(r'(^|[^\d])((\d[\s\-_.]*){6})(?!\d)').firstMatch(text);
    if (spaced != null) {
      final digits = RegExp(r'\d')
          .allMatches(spaced.group(2) ?? '')
          .map((m) => m.group(0)!)
          .join();
      if (digits.length == 6) return digits;
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
}
