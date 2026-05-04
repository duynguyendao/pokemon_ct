import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:enough_mail/enough_mail.dart';

class FastImapConfig {
  final String host;
  final int port;
  final String username;
  final String password;
  final bool isSecure;
  final Duration connectTimeout;
  final Duration commandTimeout;

  const FastImapConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.isSecure = true,
    this.connectTimeout = const Duration(seconds: 20),
    this.commandTimeout = const Duration(seconds: 20),
  });
}

class FastMailboxState {
  final int exists;
  final int uidNext;

  const FastMailboxState({required this.exists, required this.uidNext});
}

class FastImapMessage {
  final int? uid;
  final DateTime date;
  final String sender;
  final String recipient;
  final String subject;
  final String body;
  final String raw;

  const FastImapMessage({
    required this.uid,
    required this.date,
    required this.sender,
    required this.recipient,
    required this.subject,
    required this.body,
    required this.raw,
  });
}

class FastImapException implements Exception {
  final String message;

  const FastImapException(this.message);

  @override
  String toString() => message;
}

class FastImapClient {
  static const _defaultBodyBytes = 64 * 1024;

  final void Function(String line)? debugLog;

  Socket? _socket;
  StreamSubscription<String>? _lineSub;
  final _lines = Queue<String>();
  final _waiters = Queue<Completer<String>>();
  Object? _lineError;
  bool _closed = true;
  int _tagCounter = 0;

  FastImapClient({this.debugLog});

  Future<void> connect(FastImapConfig config) async {
    await close();
    _closed = false;
    _lineError = null;
    _lines.clear();
    _tagCounter = 0;

    final socket = config.isSecure
        ? await SecureSocket.connect(
            config.host,
            config.port,
          ).timeout(config.connectTimeout)
        : await Socket.connect(
            config.host,
            config.port,
          ).timeout(config.connectTimeout);
    _socket = socket;
    _lineSub = socket
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(_onLine, onError: _onError, onDone: _onDone);

    final greeting = await _readLine(timeout: config.connectTimeout);
    if (!greeting.startsWith('* OK') && !greeting.startsWith('* PREAUTH')) {
      throw FastImapException('Unexpected IMAP greeting: $greeting');
    }

    if (!greeting.startsWith('* PREAUTH')) {
      await _command(
        'LOGIN ${_quote(config.username)} ${_quote(config.password)}',
        timeout: config.commandTimeout,
      );
    }
  }

  Future<FastMailboxState> selectInbox() async {
    final lines = await _command('SELECT "INBOX"');
    return _parseMailboxState(lines);
  }

  Future<int> fetchLastUid() async {
    final state = await selectInbox();
    if (state.exists <= 0) return 0;

    final lines = await _command(
      'FETCH ${state.exists} (UID)',
      timeout: const Duration(seconds: 8),
    );
    return _parseUid(lines.join('\n')) ??
        (state.uidNext > 1 ? state.uidNext - 1 : 0);
  }

  Future<List<int>> searchNewUids(int lastSeenUid) async {
    final criteria = lastSeenUid > 0 ? 'UID ${lastSeenUid + 1}:*' : 'RECENT';
    final lines = await _command(
      'UID SEARCH $criteria',
      timeout: const Duration(seconds: 8),
    );
    final uids = <int>[];
    for (final line in lines) {
      if (!line.toUpperCase().startsWith('* SEARCH')) continue;
      final parts = line
          .substring('* SEARCH'.length)
          .trim()
          .split(RegExp(r'\s+'));
      for (final part in parts) {
        final uid = int.tryParse(part);
        if (uid != null && uid > lastSeenUid) uids.add(uid);
      }
    }
    uids.sort();
    return uids;
  }

  Future<List<FastImapMessage>> fetchMessagesByUid(
    List<int> uids, {
    int maxBodyBytes = _defaultBodyBytes,
  }) async {
    if (uids.isEmpty) return const [];
    final lines = await _command(
      'UID FETCH ${_uidSet(uids)} '
      '(UID INTERNALDATE BODY.PEEK[]<0.$maxBodyBytes>)',
      timeout: const Duration(seconds: 20),
    );
    return _parseFetchMessages(lines);
  }

  Future<List<FastImapMessage>> fetchRecentMessages({
    int maxMessages = 30,
    int maxBodyBytes = _defaultBodyBytes,
  }) async {
    final state = await selectInbox();
    if (state.exists <= 0) return const [];

    final count = maxMessages < 1 ? 1 : maxMessages;
    final start = state.exists - count + 1;
    final rangeStart = start < 1 ? 1 : start;
    final lines = await _command(
      'FETCH $rangeStart:* (UID INTERNALDATE BODY.PEEK[]<0.$maxBodyBytes>)',
      timeout: const Duration(seconds: 25),
    );
    final messages = _parseFetchMessages(lines);
    messages.sort((a, b) => (a.uid ?? 0).compareTo(b.uid ?? 0));
    return messages;
  }

  Future<bool> idleUntilNewMail(Duration timeout) async {
    final tag = _nextTag();
    await _write('$tag IDLE\r\n');

    while (true) {
      final line = await _readLine(timeout: const Duration(seconds: 8));
      if (line.startsWith('+')) break;
      if (line.startsWith('$tag ')) {
        if (_isOk(line)) return false;
        throw FastImapException('IDLE failed: $line');
      }
    }

    try {
      while (true) {
        final line = await _readLine(timeout: timeout);
        final upper = line.toUpperCase();
        if (upper.startsWith('* BYE')) {
          throw FastImapException('IMAP server closed IDLE: $line');
        }
        if (RegExp(
          r'^\* \d+ (EXISTS|RECENT)$',
          caseSensitive: false,
        ).hasMatch(line)) {
          await _finishIdle(tag);
          return true;
        }
        if (line.startsWith('$tag ')) {
          if (_isOk(line)) return false;
          throw FastImapException('IDLE failed: $line');
        }
      }
    } on TimeoutException {
      await _finishIdle(tag);
      return false;
    }
  }

  Future<void> logout() async {
    if (_socket == null) return;
    try {
      await _command('LOGOUT', timeout: const Duration(seconds: 5));
    } catch (_) {
      // Closing the socket is enough when the server is already gone.
    }
    await close();
  }

  Future<void> close() async {
    _closed = true;
    final sub = _lineSub;
    final socket = _socket;
    _lineSub = null;
    _socket = null;
    _lineError = const FastImapException('IMAP connection closed');
    _failWaiters(_lineError!);
    if (sub != null) {
      try {
        await sub.cancel();
      } catch (_) {}
    }
    if (socket != null) {
      try {
        socket.destroy();
      } catch (_) {}
    }
    _lines.clear();
  }

  void _onLine(String line) {
    debugLog?.call('< $line');
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete(line);
      return;
    }
    _lines.add(line);
  }

  void _onError(Object error) {
    _lineError = error;
    _failWaiters(error);
  }

  void _onDone() {
    _closed = true;
    _lineError ??= const FastImapException('IMAP connection closed');
    _failWaiters(_lineError!);
  }

  void _failWaiters(Object error) {
    while (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      if (!waiter.isCompleted) waiter.completeError(error);
    }
  }

  Future<String> _readLine({required Duration timeout}) {
    if (_lines.isNotEmpty) return Future.value(_lines.removeFirst());
    final error = _lineError;
    if (error != null) return Future.error(error);
    if (_closed) {
      return Future.error(const FastImapException('IMAP connection closed'));
    }

    final waiter = Completer<String>();
    _waiters.add(waiter);
    return waiter.future.timeout(
      timeout,
      onTimeout: () {
        _waiters.remove(waiter);
        throw TimeoutException('IMAP response timeout', timeout);
      },
    );
  }

  Future<List<String>> _command(String command, {Duration? timeout}) async {
    final tag = _nextTag();
    await _write('$tag $command\r\n');
    final lines = <String>[];
    final wait = timeout ?? const Duration(seconds: 20);
    while (true) {
      final line = await _readLine(timeout: wait);
      lines.add(line);
      if (!line.startsWith('$tag ')) continue;
      if (_isOk(line)) return lines;
      throw FastImapException('$command failed: $line');
    }
  }

  Future<void> _finishIdle(String tag) async {
    await _write('DONE\r\n');
    while (true) {
      final line = await _readLine(timeout: const Duration(seconds: 8));
      if (!line.startsWith('$tag ')) continue;
      if (_isOk(line)) return;
      throw FastImapException('IDLE DONE failed: $line');
    }
  }

  Future<void> _write(String data) async {
    final socket = _socket;
    if (socket == null) {
      throw const FastImapException('IMAP connection is not open');
    }
    debugLog?.call('> ${data.trimRight()}');
    socket.write(data);
    await socket.flush();
  }

  String _nextTag() {
    _tagCounter += 1;
    return 'A${_tagCounter.toString().padLeft(4, '0')}';
  }

  bool _isOk(String line) =>
      RegExp(r'^A\d{4} OK\b', caseSensitive: false).hasMatch(line);

  String _quote(String value) {
    final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }

  String _uidSet(List<int> uids) {
    final sorted = [...uids]..sort();
    return sorted.join(',');
  }

  FastMailboxState _parseMailboxState(List<String> lines) {
    var exists = 0;
    var uidNext = 0;
    for (final line in lines) {
      final existsMatch = RegExp(
        r'^\* (\d+) EXISTS',
        caseSensitive: false,
      ).firstMatch(line);
      if (existsMatch != null) {
        exists = int.tryParse(existsMatch.group(1) ?? '') ?? exists;
      }

      final uidNextMatch = RegExp(
        r'\[UIDNEXT (\d+)\]',
        caseSensitive: false,
      ).firstMatch(line);
      if (uidNextMatch != null) {
        uidNext = int.tryParse(uidNextMatch.group(1) ?? '') ?? uidNext;
      }
    }
    return FastMailboxState(exists: exists, uidNext: uidNext);
  }

  List<FastImapMessage> _parseFetchMessages(List<String> lines) {
    final blocks = <List<String>>[];
    List<String>? current;
    final fetchStart = RegExp(r'^\* \d+ FETCH\b', caseSensitive: false);
    final tagged = RegExp(r'^A\d{4} (OK|NO|BAD)\b', caseSensitive: false);

    for (final line in lines) {
      if (tagged.hasMatch(line)) {
        if (current != null) {
          blocks.add(current);
          current = null;
        }
        continue;
      }

      if (fetchStart.hasMatch(line)) {
        if (current != null) blocks.add(current);
        current = [line];
        continue;
      }

      current?.add(line);
    }
    if (current != null) blocks.add(current);

    final messages = <FastImapMessage>[];
    for (final block in blocks) {
      final message = _parseFetchBlock(block);
      if (message != null) messages.add(message);
    }
    return messages;
  }

  FastImapMessage? _parseFetchBlock(List<String> block) {
    if (block.isEmpty) return null;
    final firstLine = block.first;
    final uid = _parseUid(block.join('\n'));
    final internalDate = _parseInternalDate(firstLine);

    final rawLines = block.skip(1).toList();
    while (rawLines.isNotEmpty && rawLines.last.trim() == ')') {
      rawLines.removeLast();
    }
    final raw = rawLines.join('\r\n').trimRight();
    if (raw.isEmpty) return null;

    try {
      final mime = MimeMessage.parseFromText(raw);
      final plain = mime.decodeTextPlainPart();
      final html = mime.decodeTextHtmlPart();
      final subject =
          mime.decodeSubject() ?? _headerValue(raw, 'subject') ?? '';
      final body = _bodyText(plain, html, raw);
      return FastImapMessage(
        uid: uid,
        date: mime.decodeDate() ?? internalDate ?? DateTime.now(),
        sender: _firstAddress(
          mime.from,
        ).ifEmpty(_parseEmail(_headerValue(raw, 'from') ?? '')),
        recipient: _firstAddress(
          mime.to,
        ).ifEmpty(_parseEmail(_headerValue(raw, 'to') ?? '')),
        subject: subject,
        body: body,
        raw: raw,
      );
    } catch (_) {
      return FastImapMessage(
        uid: uid,
        date: internalDate ?? DateTime.now(),
        sender: _parseEmail(_headerValue(raw, 'from') ?? ''),
        recipient: _parseEmail(_headerValue(raw, 'to') ?? ''),
        subject: _headerValue(raw, 'subject') ?? '',
        body: raw,
        raw: raw,
      );
    }
  }

  int? _parseUid(String text) {
    final match = RegExp(
      r'\bUID (\d+)\b',
      caseSensitive: false,
    ).firstMatch(text);
    return int.tryParse(match?.group(1) ?? '');
  }

  DateTime? _parseInternalDate(String line) {
    final match = RegExp(
      r'INTERNALDATE "(\d{1,2})-([A-Za-z]{3})-(\d{4}) (\d{2}):(\d{2}):(\d{2}) ([+-])(\d{2})(\d{2})"',
      caseSensitive: false,
    ).firstMatch(line);
    if (match == null) return null;

    final month = const {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    }[match.group(2)!.toLowerCase()];
    if (month == null) return null;

    final localAsUtc = DateTime.utc(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
    final sign = match.group(7) == '-' ? -1 : 1;
    final offsetMinutes =
        sign * (int.parse(match.group(8)!) * 60 + int.parse(match.group(9)!));
    return localAsUtc.subtract(Duration(minutes: offsetMinutes)).toLocal();
  }

  String _firstAddress(List<MailAddress>? addresses) {
    if (addresses == null || addresses.isEmpty) return '';
    return addresses.first.email.trim().toLowerCase();
  }

  String _parseEmail(String raw) {
    final match = RegExp(r'<([^>]+@[^>]+)>').firstMatch(raw);
    final email = match?.group(1) ?? raw;
    return email.trim().toLowerCase();
  }

  String? _headerValue(String raw, String name) {
    final target = name.toLowerCase();
    final lines = raw.split(RegExp(r'\r?\n'));
    String? value;
    var collecting = false;

    for (final line in lines) {
      if (line.isEmpty) break;
      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (collecting && value != null) value = '$value ${line.trim()}';
        continue;
      }

      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      if (collecting) break;

      collecting = line.substring(0, colon).toLowerCase() == target;
      if (collecting) value = line.substring(colon + 1).trim();
    }

    return value;
  }

  String _bodyText(String? plain, String? html, String raw) {
    if (plain != null && plain.trim().isNotEmpty) return plain;
    if (html != null && html.trim().isNotEmpty) {
      return html
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>');
    }
    return raw;
  }
}

extension _StringEmptyFallback on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
