import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/account.dart';
import '../models/lottery_result_entry.dart';
import '../models/otp_entry.dart';
import '../models/proxy.dart';
import '../providers/app_provider.dart';
import '../utils/app_theme.dart';
import '../utils/device_profiles.dart';

class BrowserScreen extends StatefulWidget {
  final Account account;
  final Proxy? proxy;
  final String? startUrl;
  final bool isRunningAll;
  final VoidCallback? onStopAll;
  final VoidCallback? onSkipCurrent;

  const BrowserScreen({
    super.key,
    required this.account,
    this.proxy,
    this.startUrl,
    this.isRunningAll = false,
    this.onStopAll,
    this.onSkipCurrent,
  });

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final WebViewController _controller;
  late final DeviceProfile _profile;
  bool _loading = true;
  String _currentUrl = '';
  bool _canGoBack = false;
  bool _canGoForward = false;
  String _statusText = '';
  bool _autoFilling = false;
  String? _lastAutoFillUrl;

  // Smart DOM wait completers
  final Map<String, Completer<void>> _domWaitCompleters = {};

  // OTP auto-submit
  bool _otpAutoSubmitting = false;
  String? _lastOtpPageUrl; // tránh trigger lại cùng một URL
  int _otpRetryCount = 0;
  static const int _maxOtpRetries = 3;
  String? _lastSubmittedOtp;

  // Thời điểm bấm ログイン — chỉ lấy OTP gửi SAU thời điểm này
  DateTime? _loginAttemptTime;

  // Lottery result extraction (lotteryResult mode)
  bool _resultChecked = false;
  bool _pendingResultNavigation = false;
  Completer<List<dynamic>>? _extractCompleter;

  // Overlay for status text (above iOS platform WebView)
  OverlayEntry? _statusOverlay;

  // JS để phát hiện field OTP và lỗi trên trang
  static const String _detectOtpFieldJs = '''
(function() {
  var selectors = [
    'input#authCode',
    'input[name="dwfrm_factor2Auth_authCode"]',
    'input[name="passcode"]','input[name="otp"]','input[name="code"]',
    'input[id*="auth"]','input[id*="otp"]','input[id*="passcode"]',
    'input[placeholder*="パスコード"]','input[maxlength="6"]'
  ];
  for (var i = 0; i < selectors.length; i++) {
    if (document.querySelector(selectors[i])) {
      window.FlutterChannel.postMessage('{"type":"otpField","detected":true}');
      break;
    }
  }
  // Phát hiện lỗi xác thực (bao gồm thông báo của Pokémon Center)
  var errorWords = [
    'パスコードの認証に失敗しました',
    'パスコードが正しくありません','パスコードが違',
    '正しくない','無効','期限切れ','incorrect','invalid','expired'
  ];
  var bodyText = document.body ? document.body.innerText : '';
  for (var j = 0; j < errorWords.length; j++) {
    if (bodyText.indexOf(errorWords[j]) >= 0) {
      window.FlutterChannel.postMessage('{"type":"otpError","detected":true}');
      break;
    }
  }
})();
''';

  static const String _extractJs = '''
(function() {
  var items = [];
  var lis = document.querySelectorAll('.comOrderList > li');
  if (lis.length === 0) {
    window.FlutterChannel.postMessage(JSON.stringify({type:'lotteryResults',data:[]}));
    return;
  }
  lis.forEach(function(li) {
    var timeEl = li.querySelector('.time');
    var ttlEl  = li.querySelector('.ttl');
    if (!timeEl || !ttlEl) return;
    var span     = timeEl.querySelector('span');
    var dateText = timeEl.childNodes[0] ? timeEl.childNodes[0].textContent.trim() : '';
    var timeText = span ? span.textContent.trim() : '';
    var won  = li.querySelector('.checkedTxt');
    var lost = li.querySelector('.endTxt');
    items.push({
      title:  ttlEl.textContent.trim(),
      date:   dateText + ' ' + timeText,
      result: won ? '当選' : (lost ? '落選' : '未定'),
    });
  });
  window.FlutterChannel.postMessage(JSON.stringify({type:'lotteryResults',data:items}));
})();
''';

  @override
  void initState() {
    super.initState();
    _profile = randomProfile();
    final p = context.read<AppProvider>();
    final startUrl = widget.startUrl ?? p.loginUrl;
    _initController(startUrl, incognito: p.incognitoMode);

    // Show UA toast after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final shortUa = _shortUaLabel(_profile.userAgent);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.devices, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_profile.name}  •  $shortUa',
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF2A2D3E),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    });
  }

  /// Extracts a short browser label from a full UA string.
  String _shortUaLabel(String ua) {
    final chromeMatch = RegExp(r'Chrome/([\d.]+)').firstMatch(ua);
    if (chromeMatch != null) return 'Chrome ${chromeMatch.group(1)!.split('.').first}';
    final safariMatch = RegExp(r'Version/([\d.]+)').firstMatch(ua);
    if (safariMatch != null) return 'Safari ${safariMatch.group(1)}';
    return ua.length > 30 ? '${ua.substring(0, 30)}…' : ua;
  }

  void _showStatusOverlay(String text) {
    _statusOverlay?.remove();
    _statusOverlay = null;
    if (text.isEmpty) return;

    _statusOverlay = OverlayEntry(
      builder: (_) => Positioned(
        top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.secondary),
              boxShadow: [
                BoxShadow(color: Colors.black.withAlpha(120), blurRadius: 8),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(AppColors.secondary),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_statusOverlay!);
  }

  void _setStatus(String text) {
    if (!mounted) return;
    setState(() => _statusText = text);
    _showStatusOverlay(text);
  }

  // Polls JS until one of [selectors] is found in DOM, or [timeout] ms passes.
  // Uses FlutterChannel with key "__domWait_<token>" to resolve.
  Future<void> _waitForElement(
    List<String> selectors, {
    int timeout = 3000,
    int pollInterval = 100,
  }) async {
    final token = DateTime.now().microsecondsSinceEpoch.toString();
    final completer = Completer<void>();
    _domWaitCompleters[token] = completer;

    final selectorsJs = selectors.map((s) => '"${s.replaceAll('"', '\\"')}"').join(',');
    await _controller.runJavaScript('''
(function() {
  var token = "$token";
  var selectors = [$selectorsJs];
  var maxMs = $timeout;
  var interval = $pollInterval;
  var elapsed = 0;
  function check() {
    for (var i = 0; i < selectors.length; i++) {
      if (document.querySelector(selectors[i])) {
        window.FlutterChannel.postMessage('{"type":"domReady","token":"' + token + '"}');
        return;
      }
    }
    elapsed += interval;
    if (elapsed < maxMs) {
      setTimeout(check, interval);
    } else {
      window.FlutterChannel.postMessage('{"type":"domReady","token":"' + token + '"}');
    }
  }
  check();
})();
''');

    await completer.future.timeout(
      Duration(milliseconds: timeout + 500),
      onTimeout: () {},
    );
    _domWaitCompleters.remove(token);
  }

  @override
  void dispose() {
    _statusOverlay?.remove();
    _statusOverlay = null;
    for (final c in _domWaitCompleters.values) {
      if (!c.isCompleted) c.complete();
    }
    _domWaitCompleters.clear();
    super.dispose();
  }

  bool _isLoginPage(String url) {
    final u = url.toLowerCase();
    return u.contains('/login') &&
        !u.contains('mfa') &&
        !u.contains('auth') &&
        !u.contains('passcode') &&
        !u.contains('otp') &&
        !u.contains('code') &&
        !u.contains('verify') &&
        !u.contains('factor') &&
        !u.contains('2step') &&
        !u.contains('twostep');
  }

  void _initController(String startUrl, {bool incognito = false}) {
    final p = context.read<AppProvider>();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            // Nếu đang ở trang OTP và URL thay đổi → clear status "Đang xác nhận"
            final wasOnOtpPage =
                _lastOtpPageUrl != null && _currentUrl == _lastOtpPageUrl;
            setState(() {
              _currentUrl = url;
              _loading = true;
              if (wasOnOtpPage && url != _lastOtpPageUrl) {
                _otpAutoSubmitting = false;
                _lastOtpPageUrl = null;
              }
            });
            if (wasOnOtpPage && url != _lastOtpPageUrl) {
              _setStatus('✅ OTP xác nhận thành công!');
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted && _statusText.contains('thành công')) {
                  _setStatus('');
                }
              });
              // lotteryResult mode: sau OTP thành công → navigate về trang kết quả
              if (widget.account.mode == AccountMode.lotteryResult &&
                  !_resultChecked) {
                setState(() => _pendingResultNavigation = true);
              }
            }
            if (p.fakeBrowser) {
              _controller.runJavaScript(buildAntiFingerprintScript(_profile));
            }
          },
          onPageFinished: (url) async {
            setState(() {
              _currentUrl = url;
              _loading = false;
            });
            _controller.canGoBack().then((v) => setState(() => _canGoBack = v));
            _controller.canGoForward().then(
              (v) => setState(() => _canGoForward = v),
            );

            if (p.fakeBrowser) {
              await _controller.runJavaScript(
                buildAntiFingerprintScript(_profile),
              );
            }

            // Sau OTP thành công trong lotteryResult mode → điều hướng đến trang kết quả
            if (_pendingResultNavigation &&
                !_resultChecked &&
                p.lotteryResultUrl.isNotEmpty) {
              setState(() => _pendingResultNavigation = false);
              final base = p.lotteryResultUrl.contains('?')
                  ? p.lotteryResultUrl.split('?').first
                  : p.lotteryResultUrl;
              if (!url.startsWith(base)) {
                unawaited(
                  _controller.loadRequest(Uri.parse(p.lotteryResultUrl)),
                );
                return;
              }
              // Đã ở đúng trang → tiếp tục xuống trigger bên dưới
            }

            // Auto-fill email + password trên trang login
            if (_isLoginPage(url) && _lastAutoFillUrl != url && !_autoFilling) {
              _lastAutoFillUrl = url;
              await _waitForElement([
                'input[type="email"]',
                'input[name="email"]',
                'input[name="loginEmail"]',
                'input[id*="email"]',
              ], timeout: 3000);
              await _autoFill(silent: true);
            }

            // Trigger lottery result extraction CHỈ khi đang ở đúng trang result
            // Không dùng !_isLoginPage vì trang trung gian cũng pass điều kiện đó
            // → gây loop: performResultCheck navigate lại → redirect về login lại
            if (mounted &&
                widget.account.mode == AccountMode.lotteryResult &&
                !_resultChecked &&
                p.lotteryResultUrl.isNotEmpty &&
                url.startsWith(
                    p.lotteryResultUrl.contains('?')
                        ? p.lotteryResultUrl.split('?').first
                        : p.lotteryResultUrl)) {
              _resultChecked = true;
              unawaited(_performResultCheck());
            }

            // Dùng JS để phát hiện field OTP — không có 'body' fallback
            await _waitForElement([
              'input#authCode',
              'input[name="dwfrm_factor2Auth_authCode"]',
              'input[name="passcode"]',
              'input[maxlength="6"]',
            ], timeout: 3000);
            if (mounted) {
              await _controller.runJavaScript(_detectOtpFieldJs);
            }
          },
          onWebResourceError: (_) => setState(() => _loading = false),
        ),
      )
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (msg) => _handleJsMessage(msg.message),
      );

    // Luôn xóa cookies trước mỗi phiên để tránh bị flag
    unawaited(WebViewCookieManager().clearCookies());

    _controller.loadRequest(Uri.parse(startUrl));
    setState(() => _currentUrl = startUrl);
  }

  void _handleJsMessage(String message) {
    // DOM element ready signal → resolve pending completer
    if (message.contains('"type":"domReady"')) {
      final tokenMatch = RegExp(r'"token":"([^"]+)"').firstMatch(message);
      if (tokenMatch != null) {
        final token = tokenMatch.group(1)!;
        _domWaitCompleters[token]?.complete();
      }
      return;
    }

    // Lottery result extraction response
    if (message.contains('"type":"lotteryResults"')) {
      try {
        final data = jsonDecode(message) as Map<String, dynamic>;
        final items = (data['data'] as List?) ?? [];
        if (_extractCompleter?.isCompleted == false) {
          _extractCompleter!.complete(items);
        }
      } catch (_) {}
      return;
    }

    // OTP field phát hiện → auto submit
    if (message.contains('"type":"otpField"') &&
        message.contains('"detected":true')) {
      // Chỉ trigger 1 lần cho mỗi URL để tránh spam
      if (!_otpAutoSubmitting && _lastOtpPageUrl != _currentUrl) {
        _lastOtpPageUrl = _currentUrl;
        _otpRetryCount = 0;
        _setStatus('📡 Đang lấy OTP...');
        // Clipboard mode: mở app Mail để user thấy email chứa OTP
        if (context.read<AppProvider>().isClipboardOtpMode) {
          unawaited(_openMailApp());
        }
        unawaited(_autoSubmitOtp());
      }
      return;
    }

    // Phát hiện lỗi OTP → retry
    if (message.contains('"type":"otpError"') &&
        message.contains('"detected":true')) {
      if (_otpAutoSubmitting || _lastOtpPageUrl == _currentUrl) {
        _handleOtpError();
      }
      return;
    }

    // Status feedback từ buildOtpAutoSubmitScript
    if (message.contains('"type":"otpStatus"')) {
      if (message.contains('"status":"filled"')) {
        _setStatus('⌨️ Đã điền OTP...');
      } else if (message.contains('"status":"submitted"')) {
        _setStatus('⏳ Đang xác nhận...');
        // Sau 3s kiểm tra lại xem có lỗi không hoặc đã chuyển trang
        Future.delayed(const Duration(seconds: 3), () {
          if (!mounted) return;
          if (_currentUrl == _lastOtpPageUrl) {
            // Vẫn ở trang OTP → check lỗi
            _controller.runJavaScript(_detectOtpFieldJs);
            setState(() => _otpAutoSubmitting = false);
          } else {
            // Đã chuyển trang → OTP success!
            setState(() {
              _otpAutoSubmitting = false;
              _lastOtpPageUrl = null;
            });
            _setStatus('✅ OTP xác nhận thành công!');
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted && _statusText.contains('thành công')) {
                _setStatus('');
              }
            });
          }
        });
      } else if (message.contains('"status":"noField"')) {
        setState(() => _otpAutoSubmitting = false);
        _setStatus('');
      } else if (message.contains('"status":"noButton"')) {
        setState(() => _otpAutoSubmitting = false);
        _setStatus('⚠️ Không thấy nút 認証する');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _setStatus('');
        });
      }
    }
  }

  String? _getOtpForAccount() => context.read<AppProvider>().latestOtpForEmail(
    widget.account.email,
    after: _loginAttemptTime,
  );

  bool _matchesCurrentAccountOtp(OtpEntry otp, {String? excludeCode}) {
    final recipient = otp.recipient?.toLowerCase().trim() ?? '';
    final target = _normalizeEmail(widget.account.email);
    if (recipient.isNotEmpty && _normalizeEmail(recipient) != target) {
      return false;
    }
    if (_loginAttemptTime != null &&
        otp.timestamp.isBefore(_loginAttemptTime!)) {
      return false;
    }
    return excludeCode == null || otp.code != excludeCode;
  }

  String _normalizeEmail(String email) {
    final trimmed = email.toLowerCase().trim();
    final at = trimmed.lastIndexOf('@');
    if (at <= 0) return trimmed;

    var local = trimmed.substring(0, at);
    final domain = trimmed.substring(at + 1);
    final plus = local.indexOf('+');
    if (plus >= 0) local = local.substring(0, plus);

    if (domain == 'gmail.com' || domain == 'googlemail.com') {
      local = local.replaceAll('.', '');
      return '$local@gmail.com';
    }
    return '$local@$domain';
  }

  Future<String?> _waitForOtpForAccount({
    required Duration timeout,
    String? excludeCode,
  }) async {
    final provider = context.read<AppProvider>();

    if (provider.isClipboardOtpMode) {
      return _waitForOtpFromClipboard(timeout: timeout, excludeCode: excludeCode);
    }

    final existing = _getOtpForAccount();
    if (existing != null && existing != excludeCode) return existing;

    final completer = Completer<String?>();
    StreamSubscription<OtpEntry>? sub;
    Timer? timeoutTimer;
    Timer? statusTimer;
    var elapsedSeconds = 0;

    void finish(String? code) {
      if (completer.isCompleted) return;
      unawaited(sub?.cancel());
      timeoutTimer?.cancel();
      statusTimer?.cancel();
      completer.complete(code);
    }

    void checkCachedOtp() {
      final latest = _getOtpForAccount();
      if (latest != null && latest != excludeCode) finish(latest);
    }

    sub = provider.otpStream.listen((otp) {
      if (!mounted) {
        finish(null);
        return;
      }
      if (_matchesCurrentAccountOtp(otp, excludeCode: excludeCode)) {
        finish(otp.code);
      }
    });

    timeoutTimer = Timer(timeout, () => finish(null));
    statusTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      elapsedSeconds += 5;
      if (mounted && !completer.isCompleted) {
        _setStatus('Cho OTP... $elapsedSeconds/${timeout.inSeconds}s');
      }
    });

    checkCachedOtp();
    return completer.future;
  }

  // MethodChannel để đọc changeCount clipboard mà không đọc nội dung (tránh paste dialog)
  static const _utilsChannel = MethodChannel('com.pokemonct/utils');

  Future<String?> _waitForOtpFromClipboard({
    required Duration timeout,
    String? excludeCode,
  }) async {
    final completer = Completer<String?>();
    final otpRegex = RegExp(r'^\d{6}$');
    int lastChangeCount = -1;

    void finish(String? code) {
      if (completer.isCompleted) return;
      completer.complete(code);
    }

    // Đọc clipboard 1 lần và trả về nếu có OTP hợp lệ (lần đầu khởi động)
    Future<void> readClipboard() async {
      if (completer.isCompleted) return;
      try {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text?.trim() ?? '';
        if (otpRegex.hasMatch(text) && text != excludeCode) {
          finish(text);
        }
      } catch (_) {}
    }

    // Kiểm tra changeCount — KHÔNG đọc nội dung clipboard → không trigger paste dialog
    Future<void> checkChangeCount() async {
      if (completer.isCompleted) return;
      try {
        final count = await _utilsChannel.invokeMethod<int>('clipboardChangeCount') ?? -1;
        if (count != lastChangeCount) {
          lastChangeCount = count;
          await readClipboard(); // Chỉ đọc khi clipboard thực sự thay đổi
        }
      } catch (_) {
        // Fallback nếu channel chưa sẵn sàng: đọc trực tiếp
        await readClipboard();
      }
    }

    // Kiểm tra ngay lần đầu (clipboard có thể đã có OTP từ trước)
    try {
      lastChangeCount = await _utilsChannel.invokeMethod<int>('clipboardChangeCount') ?? -1;
    } catch (_) {}
    await readClipboard();
    if (completer.isCompleted) return completer.future;

    final pollTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => checkChangeCount(),
    );
    final timeoutTimer = Timer(timeout, () => finish(null));
    var elapsedSeconds = 0;
    final statusTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      elapsedSeconds += 5;
      if (mounted && !completer.isCompleted) {
        _setStatus('📋 Chờ clipboard OTP... $elapsedSeconds/${timeout.inSeconds}s');
      }
    });

    final result = await completer.future;
    pollTimer.cancel();
    timeoutTimer.cancel();
    statusTimer.cancel();
    return result;
  }

  Future<void> _autoSubmitOtp() async {
    if (!mounted) return;
    _setStatus('Dang lay OTP...');
    final otp = await _waitForOtpForAccount(
      timeout: const Duration(seconds: 90),
    );
    if (!mounted) return;
    if (otp == null) {
      setState(() => _otpAutoSubmitting = false);
      _setStatus('Khong nhan OTP sau 90s');
      return;
    }

    await _doSubmitOtp(otp);
  }

  Future<void> _doSubmitOtp(String otp) async {
    if (!mounted) return;
    setState(() {
      _otpAutoSubmitting = true;
      _lastSubmittedOtp = otp;
    });
    _setStatus('🔢 Điền OTP: $otp');
    // Xóa clipboard sau khi dùng để tránh lấy nhầm OTP cũ lần sau
    if (context.read<AppProvider>().isClipboardOtpMode) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
    await _controller.runJavaScript(buildOtpAutoSubmitScript(otp));
  }

  void _handleOtpError() async {
    if (_otpRetryCount >= _maxOtpRetries) {
      setState(() => _otpAutoSubmitting = false);
      _setStatus('❌ Sai OTP $_maxOtpRetries lần, dừng lại');
      return;
    }
    _otpRetryCount++;
    _setStatus('Sai OTP, dang cho ma moi... ($_otpRetryCount/$_maxOtpRetries)');

    final newOtp = await _waitForOtpForAccount(
      timeout: const Duration(seconds: 90),
      excludeCode: _lastSubmittedOtp,
    );
    if (!mounted) return;
    if (newOtp != null) {
      await _doSubmitOtp(newOtp);
      return;
    }
    setState(() => _otpAutoSubmitting = false);
    _setStatus('Khong co OTP moi sau 90s');
  }

  Future<void> _performResultCheck() async {
    if (!mounted) return;
    final provider = context.read<AppProvider>();
    final email = widget.account.email;
    final keyword = provider.targetProductName;

    _setStatus('🏆 Đang lấy kết quả lottery...');

    // Đã ở đúng trang khi trigger — chờ page render xong
    await Future.delayed(const Duration(milliseconds: 800));

    // Wait for result list to appear (or timeout)
    await _waitForElement(['.comOrderList', '.comOrderList > li'], timeout: 5000);

    // Run extraction JS
    _extractCompleter = Completer<List<dynamic>>();
    await _controller.runJavaScript(_extractJs);

    List<dynamic> items;
    try {
      items = await _extractCompleter!.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      _setStatus('❌ Không lấy được kết quả');
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) Navigator.of(context).pop();
      return;
    }

    if (items.isEmpty) {
      provider.addLotteryResult(LotteryResultEntry(
        accountEmail: email, productTitle: keyword, time: '', result: '結果なし'));
      _setStatus('⚠️ Không có kết quả trong lottery history');
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final kw = keyword.toLowerCase();
    for (final item in items) {
      final title = ((item['title'] as String?) ?? '').toLowerCase();
      if (kw.isEmpty || title.contains(kw)) {
        final entry = LotteryResultEntry(
          accountEmail: email,
          productTitle: item['title'] as String? ?? '',
          time: item['date'] as String? ?? '',
          result: item['result'] as String? ?? '未定',
        );
        provider.addLotteryResult(entry);
        _setStatus(entry.isWon ? '🎉 当選! ${entry.productTitle}' : '😞 落選 ${entry.productTitle}');
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.of(context).pop();
        return;
      }
    }

    provider.addLotteryResult(LotteryResultEntry(
      accountEmail: email, productTitle: keyword, time: '', result: '対象なし'));
    _setStatus('対象なし — không tìm thấy sản phẩm "$keyword"');
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openMailApp() async {
    try {
      await _utilsChannel.invokeMethod('openMailApp');
    } catch (_) {}
  }

  Future<void> _autoFill({bool silent = false}) async {
    // Reset login timestamp khi bắt đầu lại flow login
    _loginAttemptTime = null;
    setState(() => _autoFilling = true);
    _setStatus('📧 Điền email + password...');
    try {
      await _waitForElement([
        'input[type="email"]',
        'input[name="email"]',
        'input[name="loginEmail"]',
        'input[id*="email"]',
      ], timeout: 3000);
      await _controller.runJavaScript(
        buildAutoFillScript(widget.account.email, widget.account.password),
      );
      _setStatus('🔐 Đang login...');
      await _waitForElement([
        'a.loginBtn',
        'button[type="submit"]',
        'input[type="submit"]',
        'a[role="button"]',
      ], timeout: 2000);

      // Ghi lại thời điểm bấm ログイン — chỉ nhận OTP từ sau thời điểm này
      _loginAttemptTime = DateTime.now();

      await _controller.runJavaScript('''
(function() {
  // Try direct lottery button first
  var lotteryBtn = document.querySelector('a.loginBtn, a.btn.loginBtn');
  if (lotteryBtn) { lotteryBtn.click(); return; }

  // Fallback: search by text
  var btns = Array.from(document.querySelectorAll('button, input[type="submit"], a[role="button"], a.btn'));
  for (var i = 0; i < btns.length; i++) {
    var t = btns[i].textContent || btns[i].value || '';
    if (t.indexOf('ログイン') >= 0 || t.indexOf('送信') >= 0 ||
        t.toLowerCase().indexOf('login') >= 0 || t.toLowerCase().indexOf('sign in') >= 0) {
      btns[i].click(); break;
    }
  }
})();
''');
      // Chờ browser navigate hoặc OTP field xuất hiện (tối đa 3s)
      await _waitForElement([
        'input#authCode',
        'input[name="dwfrm_factor2Auth_authCode"]',
        'input[name="passcode"]',
        'input[maxlength="6"]',
      ], timeout: 3000);
      // Trigger detect để xử lý SPA (OTP field xuất hiện mà không có page navigation)
      if (mounted) await _controller.runJavaScript(_detectOtpFieldJs);
      if (mounted) _setStatus('');
    } catch (_) {
      if (mounted) _setStatus('');
    } finally {
      if (mounted) setState(() => _autoFilling = false);
    }
  }

  void _showProxyInfo() {
    final proxy = widget.proxy;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Thông tin Proxy',
          style: TextStyle(color: Colors.white),
        ),
        content: proxy == null
            ? const Text(
                'Không dùng proxy',
                style: TextStyle(color: AppColors.textSecondary),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow('Host', proxy.host),
                  _infoRow('Port', proxy.port.toString()),
                  if (proxy.username != null) _infoRow('User', proxy.username!),
                  if (proxy.label != null) _infoRow('Label', proxy.label!),
                ],
              ),
        actions: [
          if (proxy != null)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: proxy.proxyUrl));
                Navigator.pop(context);
              },
              child: const Text('Copy URL'),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Text(
          '$label: ',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ],
    ),
  );

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
            Text(
              widget.account.email,
              style: const TextStyle(fontSize: 13, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _currentUrl.length > 45
                  ? '${_currentUrl.substring(0, 45)}...'
                  : _currentUrl,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (widget.isRunningAll) ...[
            if (widget.onSkipCurrent != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warning,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                  ),
                  onPressed: widget.onSkipCurrent,
                  icon: const Icon(Icons.skip_next, size: 16),
                  label: const Text('Skip', style: TextStyle(fontSize: 11)),
                ),
              ),
            if (widget.onStopAll != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                  ),
                  onPressed: widget.onStopAll,
                  icon: const Icon(Icons.stop, size: 16),
                  label: const Text('Stop All', style: TextStyle(fontSize: 11)),
                ),
              ),
          ] else if (widget.proxy != null)
            IconButton(
              icon: const Icon(Icons.vpn_lock, color: AppColors.done, size: 20),
              onPressed: _showProxyInfo,
            ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const LinearProgressIndicator(
              backgroundColor: AppColors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation(AppColors.primary),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        color: AppColors.surfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Quick nav
              Row(
                children: [
                  _urlBtn('Login', p.loginUrl, AppColors.primary),
                  const SizedBox(width: 6),
                  if (p.lotteryUrl.isNotEmpty) ...[
                    _urlBtn('Lottery', p.lotteryUrl, AppColors.secondary),
                    const SizedBox(width: 6),
                  ],
                  if (p.lotteryResultUrl.isNotEmpty)
                    _urlBtn('Result', p.lotteryResultUrl, AppColors.done),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _autoFilling ? null : _autoFill,
                    icon: _autoFilling
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high, size: 14),
                    label: Text(
                      _autoFilling ? '...' : 'Tự điền',
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _autoFilling
                          ? AppColors.card
                          : AppColors.secondary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                    ),
                  ),
                ],
              ),
              // Browser controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios,
                      size: 18,
                      color: _canGoBack
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                    onPressed: _canGoBack ? () => _controller.goBack() : null,
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.arrow_forward_ios,
                      size: 18,
                      color: _canGoForward
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                    onPressed: _canGoForward
                        ? () => _controller.goForward()
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: () {
                      // Reset state khi reload để trigger lại detection
                      setState(() {
                        _lastOtpPageUrl = null;
                        _otpAutoSubmitting = false;
                      });
                      _controller.reload();
                    },
                  ),
                  // OTP display — nhấn để fill + submit thủ công
                  Consumer<AppProvider>(
                    builder: (context, prov, child) {
                      final otp = prov.latestOtpForEmail(
                        widget.account.email,
                        after: _loginAttemptTime,
                      );
                      return GestureDetector(
                        onTap: otp != null ? () => _doSubmitOtp(otp) : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: otp != null
                                ? AppColors.done
                                : AppColors.card,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.sms,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                otp ?? 'OTP',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: otp != null
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontSize: 13,
                                  letterSpacing: otp != null ? 2 : 0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _urlBtn(String label, String url, Color color) => GestureDetector(
    onTap: () {
      if (url.isNotEmpty) {
        setState(() {
          _lastOtpPageUrl = null;
          _otpAutoSubmitting = false;
        });
        _controller.loadRequest(Uri.parse(url));
      }
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
