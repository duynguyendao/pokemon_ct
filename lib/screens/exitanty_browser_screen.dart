import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../models/lottery_apply_entry.dart';
import '../providers/app_provider.dart';
import '../services/exitanty_service.dart';
import '../services/discord_service.dart';
import '../utils/app_theme.dart';

class ExitAntyBrowserScreen extends StatefulWidget {
  final Account account;
  final String startUrl;
  final bool isRunningAll;
  final int? accountIndex;
  final int? totalAccounts;
  final VoidCallback? onStopAll;
  final VoidCallback? onSkipCurrent;

  const ExitAntyBrowserScreen({
    super.key,
    required this.account,
    required this.startUrl,
    this.isRunningAll = false,
    this.accountIndex,
    this.totalAccounts,
    this.onStopAll,
    this.onSkipCurrent,
  });

  @override
  State<ExitAntyBrowserScreen> createState() => _ExitAntyBrowserScreenState();
}

class _ExitAntyBrowserScreenState extends State<ExitAntyBrowserScreen> {
  final List<_LogEntry> _logs = [];
  bool _running = false;
  bool _stopRequested = false;
  ExitAntySession? _session;
  late ExitAntyService _svc;

  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    final p = context.read<AppProvider>();
    _svc = ExitAntyService(port: p.exitantyPort, token: p.exitantyToken);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startAutomation());
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    final session = _session;
    if (session != null) {
      unawaited(_svc.deleteSession(session));
    }
    super.dispose();
  }

  void _log(String msg, {_LogLevel level = _LogLevel.info}) {
    if (!mounted) return;
    setState(() => _logs.add(_LogEntry(time: DateTime.now(), message: msg, level: level)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startAutomation() async {
    if (_running) return;
    setState(() {
      _running = true;
      _stopRequested = false;
      _logs.clear();
    });

    final p = context.read<AppProvider>();
    _log('ExitAnty automation started');
    _log('Account: ${widget.account.email}');
    _log('Mode: ${widget.account.mode.label}');

    // 1. Check ExitAnty is running
    _log('Checking ExitAnty at port ${p.exitantyPort}...');
    final alive = await _svc.isRunning();
    if (!alive) {
      _log('ExitAnty not reachable. Open the ExitAnty app first.', level: _LogLevel.error);
      if (mounted) setState(() => _running = false);
      return;
    }
    _log('ExitAnty connected', level: _LogLevel.success);
    if (_shouldStop()) return;

    // 2. Create WebDriver session
    _log('Creating session...');
    _session = await _svc.createSession(
      exitantyOptions: {'exitanty:incognito': p.incognitoMode},
    );
    if (_session == null) {
      _log('Session creation failed', level: _LogLevel.error);
      if (mounted) setState(() => _running = false);
      return;
    }
    _log('Session: ${_session!.sessionId}');
    if (_shouldStop()) { await _cleanup(); return; }

    // 3. Navigate to login
    _log('Navigating to login page...');
    final navOk = await _svc.navigate(_session!, widget.startUrl);
    if (!navOk) {
      _log('Navigation failed', level: _LogLevel.error);
      await _cleanup();
      return;
    }
    _log('Page loading...');
    await _delay(2500);
    if (_shouldStop()) { await _cleanup(); return; }

    // 4. Fill credentials
    _log('Filling login form...');
    await _fillLoginForm(widget.account.email, widget.account.password);
    await _delay(1000);

    // 5. Wait for login to complete (OTP or redirect)
    _log('Waiting for login completion...');
    final loginOk = await _waitForLogin(p);
    if (!loginOk) {
      _log('Login timed out or failed', level: _LogLevel.warning);
      await _cleanup();
      return;
    }
    _log('Logged in', level: _LogLevel.success);
    if (_shouldStop()) { await _cleanup(); return; }

    // 6. Mode-specific automation
    await _runModeTask(p);

    await _cleanup();
    if (mounted) setState(() => _running = false);
    _log('Done', level: _LogLevel.success);
  }

  Future<void> _fillLoginForm(String email, String password) async {
    const script = r'''
(function(email, pass) {
  try {
    var emailEl = document.querySelector('input[type="email"], input[name="email"], input[id*="email"]');
    var passEl  = document.querySelector('input[type="password"]');
    function set(el, v) {
      var nativeInput = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
      nativeInput.set.call(el, v);
      el.dispatchEvent(new Event('input',  {bubbles: true}));
      el.dispatchEvent(new Event('change', {bubbles: true}));
    }
    if (emailEl) set(emailEl, email);
    if (passEl)  set(passEl,  pass);
    var btn = document.querySelector('button[type="submit"], .loginBtn, [class*="login-btn"]');
    if (btn) { btn.click(); return {ok: true}; }
    var form = (emailEl || passEl)?.closest('form');
    if (form) { form.submit(); return {ok: true}; }
    return {ok: false, msg: 'no submit'};
  } catch(e) { return {ok: false, msg: e.message}; }
})(arguments[0], arguments[1])
''';
    final res = await _svc.executeScript(_session!, script, [email, password]);
    final ok = res is Map && res['ok'] == true;
    _log(ok ? 'Credentials submitted' : 'Form fill: ${res ?? "null"}',
        level: ok ? _LogLevel.info : _LogLevel.warning);
  }

  Future<bool> _waitForLogin(AppProvider p) async {
    final deadline = DateTime.now().add(Duration(seconds: p.otpWatchdogSeconds + 30));
    Timer? gasPollTimer;
    String? lastOtpFilled;

    if (p.isGasOtpMode && p.gasScriptUrl.isNotEmpty) {
      _log('OTP mode: GAS polling every 1.5s');
      final loginTimestamp = DateTime.now().millisecondsSinceEpoch;
      gasPollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
        if (_session == null || !mounted || _stopRequested) return;
        final otp = await _fetchGasOtp(p, loginTimestamp);
        if (otp != null && otp != lastOtpFilled) {
          lastOtpFilled = otp;
          _log('OTP (GAS): $otp', level: _LogLevel.success);
          await _fillOtp(otp);
        }
      });
    } else {
      _log('OTP mode: clipboard watch');
    }

    bool success = false;
    while (DateTime.now().isBefore(deadline) && !_stopRequested && mounted) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted || _session == null) break;
      final url = await _svc.getCurrentUrl(_session!);
      if (url == null) continue;

      final onLogin  = url.contains('/login') || url.contains('/signin');
      final onOtp    = url.contains('/passcode') || url.contains('/otp') || url.contains('/verify') || url.contains('/two');

      if (onOtp && p.isClipboardOtpMode) {
        final clip = await Clipboard.getData('text/plain');
        final otp = _extractSixDigit(clip?.text ?? '');
        if (otp != null && otp != lastOtpFilled) {
          lastOtpFilled = otp;
          _log('OTP (clipboard): $otp', level: _LogLevel.success);
          await _fillOtp(otp);
        }
      }

      if (!onLogin && !onOtp) {
        success = true;
        break;
      }
    }

    gasPollTimer?.cancel();
    return success;
  }

  Future<String?> _fetchGasOtp(AppProvider p, int afterMs) async {
    try {
      final uri = Uri.parse(p.gasScriptUrl).replace(queryParameters: {
        'secret': p.gasSecretKey,
        'action': 'getOtp',
        'email': widget.account.email,
        'after': afterMs.toString(),
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      final body = res.body.trim();
      if (res.statusCode == 200 && body.length == 6 && int.tryParse(body) != null) {
        return body;
      }
    } catch (_) {}
    return null;
  }

  String? _extractSixDigit(String text) {
    final m = RegExp(r'\b(\d{6})\b').firstMatch(text);
    return m?.group(1);
  }

  Future<void> _fillOtp(String otp) async {
    const script = r'''
(function(otp) {
  try {
    var inputs = Array.from(document.querySelectorAll('input'));
    var single = inputs.find(function(i) {
      return i.maxLength === 6 || i.name.toLowerCase().includes('otp') ||
             i.id.toLowerCase().includes('otp') || i.id.toLowerCase().includes('passcode');
    });
    function set(el, v) {
      var desc = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
      desc.set.call(el, v);
      el.dispatchEvent(new Event('input', {bubbles: true}));
    }
    var sixInputs = inputs.filter(function(i) { return i.maxLength === 1; });
    if (sixInputs.length === 6) {
      otp.split('').forEach(function(d, i) { set(sixInputs[i], d); });
      return 'split';
    }
    if (single) {
      set(single, otp);
      var btn = single.closest('form')?.querySelector('button[type="submit"]') ||
                document.querySelector('.btn-verify, .confirm-btn, button[type="submit"]');
      if (btn) btn.click();
      return 'single';
    }
    return 'none';
  } catch(e) { return e.message; }
})(arguments[0])
''';
    await _svc.executeScript(_session!, script, [otp]);
  }

  Future<void> _runModeTask(AppProvider p) async {
    switch (widget.account.mode) {
      case AccountMode.loginOnly:
        _log('Login only — done');
        return;

      case AccountMode.lottery:
        _log('Navigating to lottery page...');
        await _svc.navigate(_session!, p.lotteryUrl);
        await _delay(2500);
        await _doLotteryApply(p);
        return;

      case AccountMode.lotteryResult:
        _log('Navigating to lottery result...');
        await _svc.navigate(_session!, p.lotteryResultUrl);
        await _delay(2500);
        await _doLotteryResult();
        return;

      case AccountMode.orderStatus:
        _log('Navigating to order history...');
        await _svc.navigate(_session!, p.orderHistoryUrl);
        await _delay(2500);
        await _doOrderStatus();
        return;
    }
  }

  Future<void> _doLotteryApply(AppProvider p) async {
    final keywords = p.lotteryApplyKeywords.where((k) => k.isNotEmpty).toList();
    if (keywords.isEmpty) {
      _log('No keywords configured — skipping', level: _LogLevel.warning);
      return;
    }
    _log('Searching lottery items for: ${keywords.join(", ")}');

    const findScript = r'''
(function(kws) {
  var items = Array.from(document.querySelectorAll('.waresUl li, .lotteryItem, li'));
  var matched = items.find(function(li) {
    var text = li.textContent?.toLowerCase() || '';
    return kws.some(function(k) { return text.includes(k.toLowerCase()); });
  });
  if (!matched) return null;
  var name = matched.querySelector('.waresName, h3, h4')?.textContent?.trim() || matched.textContent?.trim().slice(0, 60);
  var imgEl = matched.querySelector('img');
  var imgUrl = imgEl ? (imgEl.src || imgEl.getAttribute('data-src') || '') : '';
  var btn = matched.querySelector('a, button');
  if (btn) btn.click();
  return {name: name, imgUrl: imgUrl};
})(arguments[0])
''';
    final found = await _svc.executeScript(_session!, findScript, [keywords]);
    if (found == null) {
      _log('No matching lottery item', level: _LogLevel.warning);
      return;
    }
    final title = (found['name'] as String? ?? '').trim();
    final imgUrl = (found['imgUrl'] as String? ?? '').trim();
    _log('Found: $title', level: _LogLevel.success);
    await _delay(1500);

    // Submit apply
    const applyScript = r'''
(function() {
  var btn = document.querySelector('.lotteryApplyBtn, button[class*="apply"], input[type="radio"]');
  if (btn) { btn.click(); }
  var submit = document.querySelector('button[type="submit"], .submit-btn');
  if (submit) { submit.click(); return true; }
  return false;
})()
''';
    await _svc.executeScript(_session!, applyScript);
    await _delay(2000);

    const checkScript = r'''
(function() {
  var ok  = document.querySelector('.successMsg, [class*="success"], .complete');
  var err = document.querySelector('.errorMsg, [class*="error"]');
  return {ok: !!ok, errMsg: err?.textContent?.trim()};
})()
''';
    final check = await _svc.executeScript(_session!, checkScript);
    final applied = check is Map && check['ok'] == true;
    if (applied) {
      _log('Applied successfully!', level: _LogLevel.success);
      p.addLotteryApplyResult(LotteryApplyEntry(
        accountEmail: widget.account.email,
        productTitle: title,
        time: DateTime.now().toIso8601String(),
        status: '応募成功',
      ));
      if (p.discordWebhookUrl.isNotEmpty) {
        unawaited(DiscordService.sendLotterySuccess(
          webhookUrl: p.discordWebhookUrl,
          email: widget.account.email,
          productTitle: title,
          imageUrl: imgUrl.isNotEmpty ? imgUrl : null,
        ));
      }
    } else {
      final err = check is Map ? check['errMsg'] : null;
      _log('Apply result unclear${err != null ? ": $err" : ""}', level: _LogLevel.warning);
    }
  }

  Future<void> _doLotteryResult() async {
    _log('Reading lottery results...');
    const script = r'''
(function() {
  var rows = Array.from(document.querySelectorAll('tr, .resultRow'));
  return rows.slice(0, 15).map(function(r) { return r.textContent?.replace(/\s+/g,' ').trim(); })
             .filter(function(t) { return t.length > 2; });
})()
''';
    final rows = await _svc.executeScript(_session!, script);
    if (rows is List && rows.isNotEmpty) {
      _log('${rows.length} rows found:');
      for (final r in rows.take(8)) {
        _log('  ${r.toString().trim()}');
      }
    } else {
      _log('No result rows', level: _LogLevel.warning);
    }
  }

  Future<void> _doOrderStatus() async {
    _log('Reading order list...');
    const script = r'''
(function() {
  var orders = Array.from(document.querySelectorAll('.orderItem, tr'));
  return orders.slice(0, 10).map(function(o) {
    return o.textContent?.replace(/\s+/g,' ').trim();
  }).filter(function(t) { return t.length > 2; });
})()
''';
    final rows = await _svc.executeScript(_session!, script);
    if (rows is List && rows.isNotEmpty) {
      _log('${rows.length} orders:');
      for (final r in rows.take(5)) {
        _log('  ${r.toString().trim()}');
      }
    } else {
      _log('No orders found', level: _LogLevel.warning);
    }
  }

  bool _shouldStop() {
    if (_stopRequested || !mounted) {
      if (mounted) setState(() => _running = false);
      return true;
    }
    return false;
  }

  Future<void> _cleanup() async {
    final session = _session;
    _session = null;
    if (session != null) await _svc.deleteSession(session);
    if (mounted) setState(() => _running = false);
  }

  Future<void> _delay(int ms) async {
    if (_stopRequested || !mounted) return;
    await Future.delayed(Duration(milliseconds: ms));
  }

  void _requestStop() {
    setState(() => _stopRequested = true);
    _log('Stop requested', level: _LogLevel.warning);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceVariant,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ExitAnty',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.account.email,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (widget.isRunningAll && widget.accountIndex != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Center(
                child: Text(
                  '${widget.accountIndex}/${widget.totalAccounts}',
                  style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          if (widget.onSkipCurrent != null)
            TextButton(
              onPressed: widget.onSkipCurrent,
              child: const Text('Skip', style: TextStyle(color: AppColors.warning, fontSize: 12)),
            ),
          if (widget.onStopAll != null)
            TextButton(
              onPressed: widget.onStopAll,
              child: const Text('Stop All', style: TextStyle(color: AppColors.error, fontSize: 12)),
            ),
          if (_running)
            TextButton(
              onPressed: _requestStop,
              child: const Text('Stop', style: TextStyle(color: AppColors.error)),
            )
          else
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
        ],
      ),
      body: Column(
        children: [
          // Status strip
          Container(
            color: AppColors.surfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _running ? AppColors.done : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _running ? 'Running — ${widget.account.mode.label}' : 'Idle',
                  style: TextStyle(
                    color: _running ? AppColors.done : AppColors.textSecondary,
                    fontSize: 12, fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  'port ${p.exitantyPort}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Console log
          Expanded(
            child: _logs.isEmpty
                ? const Center(
                    child: Text('Waiting...', style: TextStyle(color: AppColors.textSecondary)),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _logs.length,
                    itemBuilder: (_, i) => _LogRow(entry: _logs[i]),
                  ),
          ),
          // Controls
          SafeArea(
            child: Container(
              color: AppColors.surfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _running ? AppColors.error : AppColors.secondary,
                      ),
                      onPressed: _running ? _requestStop : _startAutomation,
                      icon: Icon(_running ? Icons.stop : Icons.replay, size: 18),
                      label: Text(_running ? 'Stop' : 'Re-run'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _logs.isEmpty ? null : () => setState(() => _logs.clear()),
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Clear'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _LogLevel { info, success, warning, error }

class _LogEntry {
  final DateTime time;
  final String message;
  final _LogLevel level;
  const _LogEntry({required this.time, required this.message, required this.level});
}

class _LogRow extends StatelessWidget {
  final _LogEntry entry;
  const _LogRow({super.key, required this.entry});

  Color get _color {
    switch (entry.level) {
      case _LogLevel.success: return AppColors.done;
      case _LogLevel.warning: return AppColors.warning;
      case _LogLevel.error:   return AppColors.error;
      case _LogLevel.info:    return Colors.white70;
    }
  }

  String get _prefix {
    switch (entry.level) {
      case _LogLevel.success: return '[OK]  ';
      case _LogLevel.warning: return '[WARN]';
      case _LogLevel.error:   return '[ERR] ';
      case _LogLevel.info:    return '[----]';
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = entry.time.hour.toString().padLeft(2, '0');
    final m = entry.time.minute.toString().padLeft(2, '0');
    final s = entry.time.second.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, height: 1.4),
          children: [
            TextSpan(
              text: '$h:$m:$s ',
              style: const TextStyle(color: AppColors.textSecondary, fontFamily: 'monospace'),
            ),
            TextSpan(
              text: '$_prefix ',
              style: TextStyle(color: _color, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
            ),
            TextSpan(
              text: entry.message,
              style: TextStyle(color: _color, fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}
