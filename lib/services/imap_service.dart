import 'dart:async';
import 'dart:math';

import '../models/filter_rule.dart';
import '../models/otp_entry.dart';
import 'debug_service.dart';
import 'fast_imap_client.dart';
import 'otp_extractor.dart';

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
    this.pollIntervalSeconds = 5,
  });

  FastImapConfig toFastConfig() => FastImapConfig(
    host: host,
    port: port,
    username: username,
    password: password,
    isSecure: isSecure,
  );
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
  static const _maxOtpMessageAge = Duration(minutes: 2);
  static const _startupRecentMessages = 3;
  static const _searchRecentFloor = 3;

  FastImapClient? _client;
  FastImapClient? _idleClient;
  Future<List<OtpEntry>>? _pollFuture;
  Timer? _pollTimer;
  ImapConfig? _config;
  List<FilterRule> _rules = [];
  bool _isRunning = false;
  bool _idleRunning = false;
  int _lastSeenUid = 0;
  final _processedUids = <int>{};
  Future<void> _clientQueue = Future<void>.value();

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
    _processedUids.clear();

    try {
      await _connect(resetLastUid: true);
    } catch (_) {
      _isRunning = false;
      await _closeIdleClient();
      await _closeClient();
      rethrow;
    }

    _startIdleLoop();
    unawaited(_scanRecentForOtp(maxMessages: _startupRecentMessages));
    _pollTimer = Timer.periodic(
      Duration(seconds: config.pollIntervalSeconds),
      (_) => _pollNew(),
    );
    unawaited(_pollNew());
  }

  Future<void> stop() async {
    _isRunning = false;
    _idleRunning = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _closeIdleClient();
    await _closeClient();
  }

  Future<void> _closeClient() async {
    final old = _client;
    _client = null;
    if (old != null) {
      try {
        await old.logout();
      } catch (_) {
        await old.close();
      }
    }
  }

  Future<void> _closeIdleClient() async {
    final old = _idleClient;
    _idleClient = null;
    if (old != null) {
      await old.close();
    }
  }

  Future<void> _connect({required bool resetLastUid}) async {
    final config = _config!;
    await _closeClient();
    _log('CONNECT', 'Connecting ${config.host}:${config.port}...');
    final client = FastImapClient();
    try {
      await client.connect(config.toFastConfig());
      final mailbox = await client.selectInbox();
      _client = client;
      if (resetLastUid) {
        _lastSeenUid = mailbox.uidNext > 1
            ? mailbox.uidNext - 1
            : await client.fetchLastUid();
        _log('CONNECT', 'Ready OK, lastUid=$_lastSeenUid');
      } else {
        _log('RECONNECT', 'Ready OK, lastUid=$_lastSeenUid');
      }
    } catch (e) {
      _log('CONNECT', 'Error: $e');
      await client.close();
      rethrow;
    }
  }

  Future<void> _reconnect() async {
    _log('RECONNECT', 'Reconnecting, keep lastUid=$_lastSeenUid...');
    await _connect(resetLastUid: false);
  }

  Future<List<OtpEntry>> _pollNew() {
    final inFlight = _pollFuture;
    if (inFlight != null) return inFlight;

    final future = _pollNewImpl();
    _pollFuture = future;
    future.whenComplete(() {
      if (identical(_pollFuture, future)) _pollFuture = null;
    });
    return future;
  }

  Future<List<OtpEntry>> _pollNewImpl() async {
    return _runClientOp(() async {
      final sw = Stopwatch()..start();
      try {
        if (_client == null) await _reconnect();
        final uids = await _client!.searchNewUids(_lastSeenUid);
        if (uids.isEmpty) {
          _log('POLL', 'No new UID (${sw.elapsedMilliseconds}ms)');
          return const [];
        }

        _log('POLL', 'Fetching ${uids.length} UID(s): $uids');
        final messages = await _client!.fetchMessagesByUid(uids);
        _lastSeenUid = max(_lastSeenUid, uids.reduce(max));
        _log('POLL', 'Fetched in ${sw.elapsedMilliseconds}ms');
        return _emitOtpFromMessages(messages, source: 'POLL');
      } catch (e) {
        _log('POLL', 'Error: $e');
        await _closeClient();
        return const [];
      }
    });
  }

  Future<T> _runClientOp<T>(Future<T> Function() action) {
    final previous = _clientQueue;
    final completer = Completer<T>();
    _clientQueue = completer.future.then<void>((_) {}, onError: (_) {});

    unawaited(
      previous.whenComplete(() async {
        try {
          completer.complete(await action());
        } catch (e, st) {
          completer.completeError(e, st);
        }
      }),
    );
    return completer.future;
  }

  Future<List<OtpEntry>> _scanRecentForOtp({required int maxMessages}) async {
    return _runClientOp(() async {
      final sw = Stopwatch()..start();
      try {
        if (_client == null) await _reconnect();
        _log('RECENT', 'Scanning last $maxMessages message(s)...');
        final messages = await _client!.fetchRecentMessages(
          maxMessages: maxMessages,
        );
        final maxUid = messages
            .map((m) => m.uid ?? 0)
            .fold<int>(_lastSeenUid, (a, b) => max(a, b));
        _lastSeenUid = max(_lastSeenUid, maxUid);
        _log('RECENT', 'Scanned in ${sw.elapsedMilliseconds}ms');
        return _emitOtpFromMessages(messages, source: 'RECENT');
      } catch (e) {
        _log('RECENT', 'Error: $e');
        await _closeClient();
        return const [];
      }
    });
  }

  List<OtpEntry> _emitOtpFromMessages(
    List<FastImapMessage> messages, {
    required String source,
  }) {
    final results = <OtpEntry>[];
    final now = DateTime.now();

    for (final message in messages) {
      final uid = message.uid;
      if (uid != null && !_processedUids.add(uid)) continue;

      final age = now.difference(message.date);
      if (age > _maxOtpMessageAge) {
        _log(source, 'Skip stale UID ${uid ?? '-'} (${age.inSeconds}s old)');
        continue;
      }

      final entry = _extractOtp(message);
      if (entry == null || _otpController.isClosed) continue;

      results.add(entry);
      _log(source, 'OTP ${entry.code} -> ${entry.recipient ?? '(unknown)'}');
      _otpController.add(entry);
    }

    if (results.isEmpty) _log(source, 'No OTP in fresh messages');
    return results;
  }

  Future<List<OtpEntry>> fetchNow() async {
    if (_config == null) return const [];
    _log('FETCH', 'Manual fetch...');
    final results = await _pollNew();
    if (results.isNotEmpty) return results;

    return _scanRecentForOtp(maxMessages: _startupRecentMessages);
  }

  void _startIdleLoop() {
    _idleRunning = true;
    unawaited(_runIdleLoop());
  }

  Future<void> _connectIdleClient() async {
    final config = _config!;
    await _closeIdleClient();
    _log('IDLE', 'Connecting...');
    final client = FastImapClient();
    await client.connect(config.toFastConfig());
    await client.selectInbox();
    _idleClient = client;
    _log('IDLE', 'Ready OK');
  }

  Future<void> _runIdleLoop() async {
    while (_isRunning && _idleRunning) {
      try {
        if (_idleClient == null) await _connectIdleClient();
        _log('IDLE', 'Waiting for new mail...');
        final hasNewMail = await _idleClient!.idleUntilNewMail(
          const Duration(minutes: 9),
        );
        if (!_isRunning || !_idleRunning) break;

        if (hasNewMail) {
          _log('IDLE', 'Push received');
          await _pollNew();
        }
      } catch (e) {
        _log('IDLE', 'Error: $e');
        await _closeIdleClient();
        if (_isRunning && _idleRunning) {
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      }
    }
    _log('IDLE', 'Loop stopped');
  }

  Future<List<EmailSearchResult>> searchEmails({
    required ImapConfig config,
    String subjectKeyword = '',
    String bodyKeyword = '',
    DateTime? from,
    DateTime? to,
    int maxMessages = 30,
  }) async {
    final client = FastImapClient();
    final results = <EmailSearchResult>[];
    final fromDate = from ?? DateTime.now().subtract(const Duration(hours: 24));
    final toDate = to != null
        ? to.add(const Duration(days: 1))
        : DateTime.now().add(const Duration(minutes: 5));
    final subjectNeedle = subjectKeyword.trim().toLowerCase();
    final bodyNeedle = bodyKeyword.trim().toLowerCase();

    try {
      _log('SEARCH', 'Connecting...');
      await client.connect(config.toFastConfig());
      final fetchCount = max(maxMessages, _searchRecentFloor);
      _log('SEARCH', 'Fetching last $fetchCount message(s)...');
      final messages = await client.fetchRecentMessages(
        maxMessages: fetchCount,
      );

      for (final message in messages.reversed) {
        if (results.length >= maxMessages) break;
        if (message.date.isBefore(fromDate) || message.date.isAfter(toDate)) {
          continue;
        }

        final subjectLower = message.subject.toLowerCase();
        final bodyLower = message.body.toLowerCase();
        if (subjectNeedle.isNotEmpty && !subjectLower.contains(subjectNeedle)) {
          continue;
        }
        if (bodyNeedle.isNotEmpty &&
            !bodyLower.contains(bodyNeedle) &&
            !subjectLower.contains(bodyNeedle)) {
          continue;
        }

        final otp =
            extractOtpFromText(message.body) ??
            extractOtpFromText(message.subject);
        final body = message.body.length > 500
            ? message.body.substring(0, 500)
            : message.body;
        results.add(
          EmailSearchResult(
            subject: message.subject.isEmpty ? '(no subject)' : message.subject,
            sender: message.sender,
            body: body,
            date: message.date,
            otpFound: otp,
          ),
        );
      }
      _log('SEARCH', 'OK ${results.length} email(s)');
    } catch (e) {
      _log('SEARCH', 'ERROR: $e');
      rethrow;
    } finally {
      await client.logout();
    }
    return results;
  }

  OtpEntry? _extractOtp(FastImapMessage message) {
    final sender = message.sender;
    final subject = message.subject;
    final body = message.body;
    final recipient = message.recipient;

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
            final re = RegExp(rule.pattern, caseSensitive: false);
            matches = re.hasMatch(body) || re.hasMatch(subject);
          } catch (_) {}
          break;
      }

      if (!matches) continue;
      final otp = rule.extractOtp(body) ?? rule.extractOtp(subject);
      if (otp != null) {
        return OtpEntry(
          code: otp,
          sender: sender,
          subject: subject,
          recipient: recipient.isNotEmpty ? recipient : null,
        );
      }
    }

    final fallback = extractOtpFromText(body) ?? extractOtpFromText(subject);
    if (fallback == null) return null;
    if (_rules.isNotEmpty) {
      _log('POLL', 'OTP fallback matched without rule match');
    }
    return OtpEntry(
      code: fallback,
      sender: sender,
      subject: subject,
      recipient: recipient.isNotEmpty ? recipient : null,
    );
  }

  Future<bool> testConnection(ImapConfig config) async {
    _log('TEST', 'Testing ${config.host}:${config.port}...');
    final client = FastImapClient();
    try {
      await client.connect(config.toFastConfig());
      await client.selectInbox();
      await client.logout();
      _log('TEST', 'OK');
      return true;
    } catch (e) {
      _log('TEST', 'Failed: $e');
      await client.close();
      return false;
    }
  }

  void dispose() {
    stop();
    _otpController.close();
  }
}
