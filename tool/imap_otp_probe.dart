import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:pokemon_ct/services/fast_imap_client.dart';
import 'package:pokemon_ct/services/otp_extractor.dart';

Future<void> main(List<String> args) async {
  final opts = _parseArgs(args);
  if (opts.containsKey('help')) {
    _printUsage();
    return;
  }

  final host = opts['host'] ?? 'imap.gmail.com';
  final port = int.tryParse(opts['port'] ?? '') ?? 993;
  final user = opts['user'] ?? Platform.environment['IMAP_USER'] ?? '';
  final password = opts['password'] ?? Platform.environment['IMAP_PASS'] ?? '';
  final minutes = int.tryParse(opts['minutes'] ?? '') ?? 20;
  final maxMessages = int.tryParse(opts['max'] ?? '') ?? 30;
  final watch = opts.containsKey('watch');
  final watchSeconds = int.tryParse(opts['watch'] ?? '') ?? 120;
  final pollSeconds = max(1, int.tryParse(opts['poll'] ?? '') ?? 1);
  final raw = opts.containsKey('raw');

  if (user.isEmpty || password.isEmpty) {
    stderr.writeln('Missing --user/--password or IMAP_USER/IMAP_PASS.');
    _printUsage();
    exitCode = 64;
    return;
  }

  final client = FastImapClient(debugLog: raw ? stdout.writeln : null);
  final seenUids = <int>{};
  var lastUid = 0;

  try {
    stdout.writeln('Connecting $host:$port as $user');
    await client.connect(
      FastImapConfig(
        host: host,
        port: port,
        username: user,
        password: password,
        isSecure: port == 993,
      ),
    );
    final mailbox = await client.selectInbox();
    lastUid = mailbox.uidNext > 1
        ? mailbox.uidNext - 1
        : await client.fetchLastUid();
    stdout.writeln(
      'INBOX selected: messages=${mailbox.exists}, uidNext=${mailbox.uidNext}, '
      'lastUid=$lastUid',
    );

    final recentFound = await _printMessages(
      await client.fetchRecentMessages(maxMessages: maxMessages),
      minutes: minutes,
      seenUids: seenUids,
    );
    if (!watch && recentFound == 0) {
      stdout.writeln('No OTP found in last $minutes minutes.');
    }

    if (!watch) return;

    stdout.writeln('');
    stdout.writeln(
      'Watching for $watchSeconds seconds, poll=${pollSeconds}s...',
    );
    final deadline = DateTime.now().add(Duration(seconds: watchSeconds));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(Duration(seconds: pollSeconds));
      final uids = await client.searchNewUids(lastUid);
      if (uids.isEmpty) continue;

      lastUid = max(lastUid, uids.reduce(max));
      await _printMessages(
        await client.fetchMessagesByUid(uids),
        minutes: minutes,
        seenUids: seenUids,
      );
    }
  } catch (e, st) {
    stderr.writeln('Probe failed: $e');
    if (opts.containsKey('stack')) stderr.writeln(st);
    exitCode = 1;
  } finally {
    await client.logout();
  }
}

Future<int> _printMessages(
  List<FastImapMessage> messages, {
  required int minutes,
  required Set<int> seenUids,
}) async {
  final since = DateTime.now().subtract(Duration(minutes: minutes));
  var found = 0;

  for (final msg in messages.reversed) {
    final uid = msg.uid;
    if (uid != null && !seenUids.add(uid)) continue;
    if (msg.date.isBefore(since)) continue;

    final otp = extractOtpFromText(msg.body) ?? extractOtpFromText(msg.subject);
    if (otp == null) continue;

    found++;
    stdout.writeln('');
    stdout.writeln('OTP FOUND: $otp');
    stdout.writeln('  uid: ${uid ?? '(no uid)'}');
    stdout.writeln('  date: ${msg.date.toIso8601String()}');
    stdout.writeln('  from: ${msg.sender}');
    stdout.writeln('  to: ${msg.recipient}');
    stdout.writeln(
      '  subject: ${msg.subject.isEmpty ? '(no subject)' : msg.subject}',
    );
  }
  return found;
}

Map<String, String> _parseArgs(List<String> args) {
  final opts = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) continue;
    final withoutPrefix = arg.substring(2);
    final eq = withoutPrefix.indexOf('=');
    if (eq >= 0) {
      opts[withoutPrefix.substring(0, eq)] = withoutPrefix.substring(eq + 1);
      continue;
    }
    final key = withoutPrefix;
    if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
      opts[key] = args[++i];
    } else {
      opts[key] = 'true';
    }
  }
  return opts;
}

void _printUsage() {
  stdout.writeln(r'''
Usage:
  dart run tool/imap_otp_probe.dart --user you@gmail.com --password "app password"

Options:
  --host imap.gmail.com     Default: imap.gmail.com
  --port 993                Default: 993
  --minutes 20              Only inspect recent mail in this window
  --max 30                  Number of recent messages to fetch
  --watch 120               Poll new UID mail for this many seconds
  --poll 1                  Watch poll interval in seconds
  --raw                     Print raw IMAP protocol logs

PowerShell without putting password in command history:
  $env:IMAP_USER="you@gmail.com"
  $env:IMAP_PASS="xxxx xxxx xxxx xxxx"
  dart run tool/imap_otp_probe.dart --watch 180
''');
}
