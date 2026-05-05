import 'dart:async';
import 'package:enough_mail/enough_mail.dart';
import '../models/otp_entry.dart';
import '../models/filter_rule.dart';
import 'debug_service.dart';

void _log(String tag, String msg) {
  debugService.log('[IMAP:$tag] $msg');
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

  void setRules(List<FilterRule> rules) {
    _rules = rules.where((r) => r.enabled).toList();
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
      await _client.connectToServer(host, port, isSecure: true);
      await _client.login(username, password);
      await _client.selectInbox();

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
          await idleClient.connectToServer(host, port, isSecure: true);
          await idleClient.login(username, password);
          await idleClient.selectInbox();
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
        final subject = msg.decodeSubject() ?? '';
        final body =
            msg.decodeTextPlainPart() ?? msg.decodeTextHtmlPart() ?? '';

        // Match filter
        if (!_matchesFilter(sender, subject)) continue;

        // Extract OTP
        final otp = _extractOtp(sender, subject, body);
        if (otp != null && !_otpController.isClosed) {
          _log('FETCH', 'OTP: $otp');
          _otpController.add(
            OtpEntry(
              code: otp,
              sender: sender,
              subject: subject,
              timestamp: msgDate,
            ),
          );
        }
      }
    } catch (e) {
      _log('FETCH', 'Error: $e');
    }
  }

  bool _matchesFilter(String sender, String subject) {
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
        case FilterType.regex:
          try {
            matches = RegExp(
              rule.pattern,
              caseSensitive: false,
            ).hasMatch(subject);
          } catch (_) {}
          break;
        default:
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
    return null;
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
