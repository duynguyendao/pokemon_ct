import 'dart:async';
import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
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

  if (user.isEmpty || password.isEmpty) {
    stderr.writeln('Missing --user/--password or IMAP_USER/IMAP_PASS.');
    _printUsage();
    exitCode = 64;
    return;
  }

  final client = ImapClient(
    isLogEnabled: opts.containsKey('raw'),
    defaultResponseTimeout: const Duration(seconds: 25),
  );
  final seenUids = <int>{};

  try {
    stdout.writeln('Connecting $host:$port as $user');
    await client
        .connectToServer(host, port, isSecure: port == 993)
        .timeout(const Duration(seconds: 20));
    await client.login(user, password).timeout(const Duration(seconds: 25));
    final mailbox = await client
        .selectMailboxByPath('INBOX')
        .timeout(const Duration(seconds: 25));
    stdout.writeln(
      'INBOX selected: messages=${mailbox.messagesExists}, '
      'recent=${mailbox.messagesRecent}, uidNext=${mailbox.uidNext}',
    );

    final deadline = DateTime.now().add(Duration(seconds: watchSeconds));
    do {
      final found = await _fetchAndPrintRecentOtps(
        client,
        minutes: minutes,
        maxMessages: maxMessages,
        seenUids: seenUids,
      );
      if (!watch && found == 0) {
        stdout.writeln('No OTP found in last $minutes minutes.');
      }
      if (!watch) break;

      await Future<void>.delayed(const Duration(seconds: 2));
    } while (DateTime.now().isBefore(deadline));
  } catch (e, st) {
    stderr.writeln('Probe failed: $e');
    if (opts.containsKey('stack')) stderr.writeln(st);
    exitCode = 1;
  } finally {
    try {
      await client.logout();
    } catch (_) {}
  }
}

Future<int> _fetchAndPrintRecentOtps(
  ImapClient client, {
  required int minutes,
  required int maxMessages,
  required Set<int> seenUids,
}) async {
  await client
      .selectMailboxByPath('INBOX')
      .timeout(const Duration(seconds: 25));
  final since = DateTime.now().subtract(Duration(minutes: minutes));
  final fetchResult = await client.fetchRecentMessages(
    messageCount: maxMessages,
    criteria: '(UID ENVELOPE BODY.PEEK[])',
    responseTimeout: const Duration(seconds: 25),
  );

  var found = 0;
  for (final msg in fetchResult.messages.reversed) {
    final uid = msg.uid;
    if (uid != null && !seenUids.add(uid)) continue;

    final date = msg.decodeDate() ?? DateTime.now();
    if (date.isBefore(since)) continue;

    final subject = msg.decodeSubject() ?? '';
    final body = msg.decodeTextPlainPart() ?? msg.decodeTextHtmlPart() ?? '';
    final otp = extractOtpFromText(body) ?? extractOtpFromText(subject);
    if (otp == null) continue;

    found++;
    stdout.writeln('');
    stdout.writeln('OTP FOUND: $otp');
    stdout.writeln('  uid: ${uid ?? '(no uid)'}');
    stdout.writeln('  date: ${date.toIso8601String()}');
    stdout.writeln('  from: ${_addressesToText(msg.from)}');
    stdout.writeln('  to: ${_addressesToText(msg.to)}');
    stdout.writeln('  subject: ${subject.isEmpty ? '(no subject)' : subject}');
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

String _addressesToText(List<MailAddress>? addresses) {
  if (addresses == null || addresses.isEmpty) return '';
  return addresses.map((a) => a.email).whereType<String>().join(', ');
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
  --watch 120               Poll for this many seconds
  --raw                     Print enough_mail protocol logs

PowerShell without putting password in command history:
  $env:IMAP_USER="you@gmail.com"
  $env:IMAP_PASS="xxxx xxxx xxxx xxxx"
  dart run tool/imap_otp_probe.dart --watch 180
''');
}
