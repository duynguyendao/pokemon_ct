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
    this.pollIntervalSeconds = 5,
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
  // ── Operations client (fetch / search / mark-read) ─────────────────────────
  ImapClient? _client;
  bool _polling = false;
  int _lastSeenUid = 0; // tracks highest UID processed — only fetch newer

  // ── IDLE client (dedicated push listener) ──────────────────────────────────
  ImapClient? _idleClient;
  bool _idleRunning = false;

  // ── Shared ────────────────────────────────────────────────────────────────
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

  // ── Start / Stop ──────────────────────────────────────────────────────────

  Future<void> start(ImapConfig config) async {
    await stop();
    _config = config;
    _isRunning = true;

    await _connect();
    _startIdleLoop(); // push: fires _pollNew() the moment mail arrives

    // Fallback poll every pollIntervalSeconds in case of IDLE gaps
    _pollTimer = Timer.periodic(
      Duration(seconds: config.pollIntervalSeconds),
      (_) => _pollNew(),
    );
  }

  Future<void> stop() async {
    _isRunning = false;
    _idleRunning = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _closeIdleClient();
    await _closeClient();
  }

  // ── Operations client ─────────────────────────────────────────────────────

  Future<void> _closeClient() async {
    final old = _client;
    _client = null;
    if (old != null) {
      try { await old.logout(); } catch (_) {}
    }
  }

  Future<void> _connect() async {
    final config = _config!;
    await _closeClient();
    _log('CONNECT', 'Connecting ${config.host}:${config.port}...');
    final client = ImapClient(isLogEnabled: false);
    try {
      await client.connectToServer(config.host, config.port, isSecure: config.isSecure);
      await client.login(config.username, config.password);
      await client.selectMailboxByPath('INBOX');
      _client = client;
      _log('CONNECT', 'Ready ✓');
      // Snapshot current max UID so we only process truly new mail
      await _initLastSeenUid();
    } catch (e) {
      _log('CONNECT', 'Error: $e');
      try { await client.logout(); } catch (_) {}
      rethrow;
    }
  }

  // Reconnect without touching _lastSeenUid — preserves OTP detection continuity
  Future<void> _reconnect() async {
    final config = _config!;
    await _closeClient();
    _log('RECONNECT', 'Reconnecting (UID preserved: $_lastSeenUid)...');
    final client = ImapClient(isLogEnabled: false);
    try {
      await client.connectToServer(config.host, config.port, isSecure: config.isSecure);
      await client.login(config.username, config.password);
      await client.selectMailboxByPath('INBOX');
      _client = client;
      _log('RECONNECT', 'OK ✓');
    } catch (e) {
      _log('RECONNECT', 'Error: $e');
      try { await client.logout(); } catch (_) {}
      rethrow;
    }
  }

  // Record current max UID — next poll will only fetch UIDs above this
  Future<void> _initLastSeenUid() async {
    try {
      final result = await _client!.uidSearchMessages(searchCriteria: 'ALL');
      final uids = result.matchingSequence?.toList() ?? [];
      _lastSeenUid = uids.isNotEmpty ? uids.last : 0;
      _log('CONNECT', 'Last UID: $_lastSeenUid');
    } catch (e) {
      _log('CONNECT', 'UID init error: $e — will use SINCE fallback');
      _lastSeenUid = 0;
    }
  }

  // ── Core fetch: only new UIDs (like PC server's "UID lastUid+1:*") ─────────

  Future<List<OtpEntry>> _pollNew() async {
    if (_polling) { _log('POLL', 'Skipped (busy)'); return []; }
    _polling = true;
    final results = <OtpEntry>[];
    try {
      if (_client == null) await _reconnect(); // preserves _lastSeenUid
      await _client!.selectMailboxByPath('INBOX');

      // Build search: UID after last seen, or last 5 min if no UID yet
      final String searchCrit;
      if (_lastSeenUid > 0) {
        searchCrit = 'UID ${_lastSeenUid + 1}:*';
      } else {
        const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        final d = DateTime.now().subtract(const Duration(minutes: 5));
        searchCrit = 'SINCE ${d.day}-${months[d.month - 1]}-${d.year}';
      }
      _log('POLL', 'Search: $searchCrit');

      // UID search returns actual UIDs
      final searchResult = await _client!.uidSearchMessages(searchCriteria: searchCrit);
      final uids = searchResult.matchingSequence?.toList() ?? [];

      // Filter: only UIDs strictly above last seen
      final newUids = _lastSeenUid > 0
          ? uids.where((u) => u > _lastSeenUid).toList()
          : uids;

      if (newUids.isEmpty) {
        _log('POLL', 'No new messages');
        return results;
      }
      _log('POLL', 'Fetching ${newUids.length} new UIDs: $newUids');

      // UID fetch — isUidSequence: true so enough_mail uses "UID FETCH"
      final seq = MessageSequence.fromIds(newUids, isUid: true);
      final fetchResult = await _client!.fetchMessages(seq, '(BODY.PEEK[])');
      _log('POLL', 'Got ${fetchResult.messages.length}');

      // Track highest UID processed
      if (uids.isNotEmpty) _lastSeenUid = uids.reduce((a, b) => a > b ? a : b);

      final toMarkRead = <int>[];
      for (final msg in fetchResult.messages) {
        final entry = _extractOtp(msg);
        if (entry != null && !_otpController.isClosed) {
          results.add(entry);
          _log('POLL', 'OTP ${entry.code} → ${entry.recipient}');
          _otpController.add(entry);
          if (msg.uid != null) toMarkRead.add(msg.uid!);
        }
      }
      if (toMarkRead.isNotEmpty) {
        try {
          await _client!.store(
            MessageSequence.fromIds(toMarkRead, isUid: true),
            [r'\Seen'],
            action: StoreAction.add,
          );
        } catch (_) {}
      }
    } catch (e) {
      _log('POLL', 'Error: $e');
      await _closeClient();
    } finally {
      _polling = false;
    }
    return results;
  }

  Future<List<OtpEntry>> fetchNow() async {
    if (_config == null) return [];
    _log('FETCH', 'Manual fetch...');
    try {
      if (_client == null) await _reconnect();
      return await _pollNew();
    } catch (e) {
      _log('FETCH', 'Error ($e), reconnecting...');
      try {
        await _reconnect();
        return await _pollNew();
      } catch (e2) {
        _log('FETCH', 'Retry failed: $e2');
        await _closeClient();
        return [];
      }
    }
  }

  // ── IMAP IDLE (server push) ───────────────────────────────────────────────
  //
  // Dedicated second connection stays in IMAP IDLE.
  // Server fires ImapMessagesExistEvent the instant new mail arrives.
  // We exit IDLE → call _pollNew() → re-enter IDLE.
  // Detection latency: sub-second from Gmail receiving the email.

  void _startIdleLoop() {
    _idleRunning = true;
    _runIdleLoop();
  }

  Future<void> _closeIdleClient() async {
    final old = _idleClient;
    _idleClient = null;
    if (old != null) {
      try { await old.idleDone(); } catch (_) {}
      try { await old.logout(); } catch (_) {}
    }
  }

  Future<void> _connectIdleClient() async {
    final config = _config!;
    await _closeIdleClient();
    _log('IDLE', 'Connecting...');
    final client = ImapClient(isLogEnabled: false);
    await client.connectToServer(config.host, config.port, isSecure: config.isSecure);
    await client.login(config.username, config.password);
    await client.selectMailboxByPath('INBOX');
    _idleClient = client;
    _log('IDLE', 'Ready ✓');
  }

  Future<void> _runIdleLoop() async {
    while (_isRunning && _idleRunning) {
      StreamSubscription<ImapMessagesExistEvent>? existsSub;
      StreamSubscription<ImapConnectionLostEvent>? lostSub;
      Timer? keepaliveTimer;

      try {
        if (_idleClient == null) await _connectIdleClient();

        final signal = Completer<bool>(); // true = new mail, false = keepalive/lost

        existsSub = _idleClient!.eventBus
            .on<ImapMessagesExistEvent>()
            .listen((event) {
          _log('IDLE', '⚡ Push: ${event.newMessagesExists} msgs');
          if (!signal.isCompleted) signal.complete(true);
        });

        lostSub = _idleClient!.eventBus
            .on<ImapConnectionLostEvent>()
            .listen((_) {
          _log('IDLE', 'Connection lost');
          if (!signal.isCompleted) signal.complete(false);
        });

        // Restart IDLE every 25 min — servers drop IDLE at 30 min
        keepaliveTimer = Timer(const Duration(minutes: 25), () {
          if (!signal.isCompleted) signal.complete(false);
        });

        _log('IDLE', 'Entering IDLE...');
        final idleFuture = _idleClient!.idleStart();
        final hasNewMail = await signal.future;

        existsSub.cancel();
        lostSub.cancel();
        keepaliveTimer.cancel();

        try { await _idleClient!.idleDone(); } catch (_) {}
        try { await idleFuture.timeout(const Duration(seconds: 5)); } catch (_) {}

        if (!hasNewMail) {
          // Connection lost or keepalive — reconnect idle client
          final old = _idleClient;
          _idleClient = null;
          if (old != null) {
            try { await old.logout(); } catch (_) {}
          }
          if (_isRunning) await Future.delayed(const Duration(seconds: 2));
          continue;
        }

        // New mail — trigger UID-based fetch immediately
        _log('IDLE', 'Triggering pollNew...');
        _pollNew(); // unawaited

      } catch (e) {
        existsSub?.cancel();
        lostSub?.cancel();
        keepaliveTimer?.cancel();
        _log('IDLE', 'Error: $e — retry in 5s...');
        final old = _idleClient;
        _idleClient = null;
        if (old != null) {
          try { await old.idleDone(); } catch (_) {}
          try { await old.logout(); } catch (_) {}
        }
        if (_isRunning) await Future.delayed(const Duration(seconds: 5));
      }
    }
    _log('IDLE', 'Loop stopped');
  }

  // ── Email Search (own temporary connection) ───────────────────────────────

  Future<List<EmailSearchResult>> searchEmails({
    required ImapConfig config,
    String subjectKeyword = '',
    String bodyKeyword = '',
    DateTime? from,
    DateTime? to,
    int maxMessages = 30,
  }) async {
    final results = <EmailSearchResult>[];

    final wasRunning = _isRunning;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _closeClient();

    final client = ImapClient(isLogEnabled: false);
    try {
      await client.connectToServer(config.host, config.port, isSecure: config.isSecure);
      await client.login(config.username, config.password);
      await client.selectMailboxByPath('INBOX');
      _log('SEARCH', 'Connected ✓');

      final criteria = SearchQueryBuilder.from(
        subjectKeyword, SearchQueryType.allTextHeaders,
        since: from,
        before: to?.add(const Duration(days: 1)),
      ).toString();

      final searchResult = await client.searchMessages(
        searchCriteria: criteria.isEmpty ? 'ALL' : criteria,
      );
      final seq = searchResult.matchingSequence;
      if (seq == null || seq.isEmpty) {
        _log('SEARCH', 'No matches');
        return results;
      }

      final ids = seq.toList();
      final limited = ids.length > maxMessages ? ids.sublist(ids.length - maxMessages) : ids;
      _log('SEARCH', 'Fetching ${limited.length} messages...');

      const batchSize = 25;
      final fromDate = from ?? DateTime.now().subtract(const Duration(hours: 24));
      final toDate = to ?? DateTime.now();

      for (var i = 0; i < limited.length; i += batchSize) {
        final end = (i + batchSize < limited.length) ? i + batchSize : limited.length;
        final fetchResult = await client.fetchMessages(
          MessageSequence.fromIds(limited.sublist(i, end)),
          '(BODY.PEEK[])',
        );
        for (final msg in fetchResult.messages.reversed) {
          final msgDate = msg.decodeDate() ?? DateTime.now();
          if (msgDate.isBefore(fromDate) || msgDate.isAfter(toDate)) continue;
          final subject = msg.decodeSubject() ?? '';
          final sender = msg.from?.firstOrNull?.email ?? '';
          final body = msg.decodeTextPlainPart() ?? msg.decodeTextHtmlPart() ?? '';
          if (bodyKeyword.isNotEmpty &&
              !body.toLowerCase().contains(bodyKeyword.toLowerCase()) &&
              !subject.toLowerCase().contains(bodyKeyword.toLowerCase())) { continue; }
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
      _log('SEARCH', '✓ ${results.length} emails');
    } catch (e) {
      _log('SEARCH', 'ERROR: $e');
      rethrow;
    } finally {
      try { await client.logout(); } catch (_) {}
      if (wasRunning && _config != null) {
        _pollTimer = Timer.periodic(
          Duration(seconds: _config!.pollIntervalSeconds),
          (_) => _pollNew(),
        );
      }
    }
    return results;
  }

  // ── OTP Extraction ────────────────────────────────────────────────────────

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

  String _parseEmail(String raw) {
    final match = RegExp(r'<([^>]+@[^>]+)>').firstMatch(raw);
    return (match?.group(1) ?? raw).trim().toLowerCase();
  }

  OtpEntry? _extractOtp(MimeMessage msg) {
    final sender = msg.from?.firstOrNull?.email ?? '';
    final subject = msg.decodeSubject() ?? '';
    final body = msg.decodeTextPlainPart() ?? msg.decodeTextHtmlPart() ?? '';
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

  // ── Misc ──────────────────────────────────────────────────────────────────

  Future<bool> testConnection(ImapConfig config) async {
    _log('TEST', 'Testing ${config.host}:${config.port}...');
    final client = ImapClient(isLogEnabled: false);
    try {
      await client.connectToServer(config.host, config.port, isSecure: config.isSecure);
      await client.login(config.username, config.password);
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
