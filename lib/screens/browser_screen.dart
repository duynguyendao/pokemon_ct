import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/account.dart';
import '../models/lottery_result_entry.dart';
import '../models/order_status_entry.dart';
import '../models/otp_entry.dart';
import '../models/proxy.dart';
import '../providers/app_provider.dart';
import '../services/shortcut_service.dart';
import '../utils/app_theme.dart';
import '../utils/device_profiles.dart';

class BrowserScreen extends StatefulWidget {
  final Account account;
  final Proxy? proxy;
  final String? startUrl;
  final bool isRunningAll;
  final int? accountIndex;   // 1-based, null khi mở đơn lẻ
  final int? totalAccounts;
  final VoidCallback? onStopAll;
  final VoidCallback? onSkipCurrent;

  const BrowserScreen({
    super.key,
    required this.account,
    this.proxy,
    this.startUrl,
    this.isRunningAll = false,
    this.accountIndex,
    this.totalAccounts,
    this.onStopAll,
    this.onSkipCurrent,
  });

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final WebViewController _controller;
  late DeviceProfile _profile; // mutable — đổi khi bị captcha
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

  // Đã vượt qua trang OTP ít nhất 1 lần → cho phép captcha recovery sau OTP
  bool _passedOtpPage = false;

  // Sau システムエラー hậu OTP → navigate đến startUrl rồi check có phải login page không
  bool _checkLoginAfterOtpError = false;

  // Lottery result extraction (lotteryResult mode)
  bool _resultChecked = false;
  bool _pendingResultNavigation = false;
  Completer<List<dynamic>>? _extractCompleter;

  // Order status extraction (orderStatus mode)
  bool _orderStatusChecked = false;
  bool _pendingOrderStatusNavigation = false;
  Completer<List<dynamic>>? _orderStatusCompleter;

  // reCAPTCHA / blocked page recovery
  int _captchaRetryCount = 0;
  static const int _maxCaptchaRetries = 5;

  // OTP page freeze watchdog (30s sau submit mà trang không chuyển)
  Timer? _otpFreezeTimer;
  int _otpFreezeRetryCount = 0;
  static const int _maxOtpFreezeRetries = 3;

  // Page freeze watchdog toàn cục — 30s không có navigation nào → recover
  Timer? _pageFreezeTimer;
  static const Duration _pageFreezeDuration = Duration(seconds: 30);

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

  static const String _orderStatusExtractJs = '''
(function() {
  var orders = document.querySelectorAll('.comOrderList > li');
  if (orders.length === 0) {
    window.FlutterChannel.postMessage(JSON.stringify({type:'orderStatusResult',data:[]}));
    return;
  }
  var result = [];
  orders.forEach(function(li) {
    var ttlEl = li.querySelector('.rBox .ttl') || li.querySelector('.ttl');
    var numEl = li.querySelector('.number span');
    var timeEl = li.querySelector('p.time');

    // Detect status: ưu tiên li.finish trong txtList
    var statusEl = li.querySelector('.txtList li.finish');
    var status = statusEl ? statusEl.textContent.trim() : '';

    // Nếu không tìm thấy li.finish, kiểm tra キャンセル済み trong vùng subBox/receiptBox
    if (!status) {
      var subBox = li.querySelector('.subBox') || li;
      var subText = subBox.textContent || '';
      if (subText.indexOf('キャンセル済み') >= 0) status = 'キャンセル済み';
    }

    // Nếu comReceiptBox có class cancel → キャンセル済み
    var receiptBox = li.querySelector('.comReceiptBox');
    if (receiptBox && (receiptBox.classList.contains('cancel') || receiptBox.classList.contains('cancelled'))) {
      status = 'キャンセル済み';
    }

    result.push({
      title: ttlEl ? ttlEl.textContent.trim() : '',
      orderNum: numEl ? numEl.textContent.trim() : '',
      status: status,
      time: timeEl ? timeEl.textContent.trim() : ''
    });
  });
  window.FlutterChannel.postMessage(JSON.stringify({type:'orderStatusResult',data:result}));
})();
''';

  // Phát hiện reCAPTCHA challenge / trang bị block.
  // CHỈ trigger khi có challenge dialog THẬT (puzzle 9 ô) hoặc error message rõ ràng.
  // Pokemon Center load reCAPTCHA badge bình thường (invisible v3) → KHÔNG được trigger
  // chỉ vì có iframe recaptcha trên trang.
  static const String _captchaDetectJs = '''
(function() {
  // Bỏ qua nếu đang ở trang OTP
  var otpSels = ['input#authCode','input[name="dwfrm_factor2Auth_authCode"]','input[maxlength="6"]','input[name="passcode"]'];
  for (var i = 0; i < otpSels.length; i++) {
    if (document.querySelector(otpSels[i])) return;
  }

  // CHALLENGE DIALOG (puzzle/checkbox visible) — KHÔNG phải badge ẩn
  // Phân biệt: challenge iframe có size lớn (>200px), badge chỉ ~60-256px
  // và badge thường có style transform/opacity/visibility = hidden
  var challengeIframes = document.querySelectorAll('iframe[src*="recaptcha"], iframe[src*="hcaptcha"], iframe[src*="captcha"]');
  for (var i = 0; i < challengeIframes.length; i++) {
    var f = challengeIframes[i];
    if (f.offsetParent === null) continue;
    var r = f.getBoundingClientRect();
    // Challenge dialog kích thước lớn (>= 250px cả 2 chiều). Badge chỉ ~60×60 hoặc 256×60
    if (r.width >= 250 && r.height >= 250) {
      window.FlutterChannel.postMessage('{"type":"captchaError","reason":"challenge-dialog"}');
      return;
    }
  }
  // Challenge UI elements (puzzle, image select, audio)
  var chUI = document.querySelector('.rc-imageselect, .rc-audiochallenge, .recaptcha-checkbox-checked, .hcaptcha-checkbox-checked');
  if (chUI && chUI.offsetParent !== null) {
    window.FlutterChannel.postMessage('{"type":"captchaError","reason":"challenge-ui"}');
    return;
  }

  var loginForm = document.querySelector('input[type="email"], input[name="loginEmail"], input[name="email"]');
  var onLoginPage = loginForm && loginForm.offsetParent !== null;
  var text = document.body ? document.body.innerText : '';

  // CRITICAL keywords — luôn check kể cả trên login page
  // (reCAPTCHA/bot detection/server-block messages — không phải lỗi login bình thường)
  var criticalKws = [
    'reCAPTCHA 認証失敗','reCAPTCHA認証','reCAPTCHAの認証',
    '認証に失敗','認証失敗しました',
    'ロボットではありません','アクセスが一時的に制限',
    // Login error sau khi click → server block (đặc trưng cho bot detection)
    '時間をおいてから再度','時間をおいてから','時間をおいて再度',
  ];
  for (var k = 0; k < criticalKws.length; k++) {
    if (text.indexOf(criticalKws[k]) >= 0) {
      window.FlutterChannel.postMessage(JSON.stringify({type:'captchaError',reason:criticalKws[k]}));
      return;
    }
  }

  // Trang login → skip generic error keywords (có thể là lỗi login bình thường)
  if (onLoginPage) return;

  // Generic error messages (chỉ check ngoài trang login/OTP)
  var kws = [
    'エラーが発生しました','エラー発生しました','システムエラー',
    'ただいまメンテナンス','しばらくしてから',
    'しばらく時間','お時間をおいて','ご不便をおかけ',
  ];
  for (var j = 0; j < kws.length; j++) {
    if (text.indexOf(kws[j]) >= 0) {
      window.FlutterChannel.postMessage(JSON.stringify({type:'captchaError',reason:kws[j]}));
      return;
    }
  }
})();
''';

  @override
  void initState() {
    super.initState();
    _profile = randomProfile();
    final p = context.read<AppProvider>();
    final startUrl = widget.startUrl ?? p.loginUrl;
    unawaited(_initController(startUrl, incognito: p.incognitoMode));

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
    _otpFreezeTimer?.cancel();
    _pageFreezeTimer?.cancel();
    for (final c in _domWaitCompleters.values) {
      if (!c.isCompleted) c.complete();
    }
    _domWaitCompleters.clear();
    super.dispose();
  }

  /// Reset 30s page-freeze watchdog. Gọi mỗi lần có navigation hoặc activity.
  /// Khi timer cháy → trang đứng 30s không có gì xảy ra → full recover.
  void _resetPageFreezeWatchdog() {
    _pageFreezeTimer?.cancel();
    if (!mounted) return;
    _pageFreezeTimer = Timer(_pageFreezeDuration, () {
      if (!mounted) return;
      // Đang trong các flow đã extract xong → không recover (đã pop screen rồi)
      if (_resultChecked || _orderStatusChecked) return;
      // Đã đạt max captcha retries → skip
      if (_captchaRetryCount >= _maxCaptchaRetries) return;
      _setStatus('⏰ Trang đứng 30s — auto recover...');
      unawaited(_recoverAndRetry());
    });
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

  Future<void> _initController(String startUrl, {bool incognito = false}) async {
    final p = context.read<AppProvider>();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_profile.userAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            // Có navigation → reset 30s freeze watchdog
            _resetPageFreezeWatchdog();
            // Nếu đang ở trang OTP và URL thay đổi → clear status "Đang xác nhận"
            final wasOnOtpPage =
                _lastOtpPageUrl != null && _currentUrl == _lastOtpPageUrl;
            setState(() {
              _currentUrl = url;
              _loading = true;
              if (wasOnOtpPage && url != _lastOtpPageUrl) {
                _otpAutoSubmitting = false;
                _lastOtpPageUrl = null;
                _passedOtpPage = true;
              }
            });
            if (wasOnOtpPage && url != _lastOtpPageUrl) {
              // OTP xác nhận thành công — cancel freeze watchdog
              _otpFreezeTimer?.cancel();
              _otpFreezeTimer = null;
              _otpFreezeRetryCount = 0;
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
              // orderStatus mode: sau OTP thành công → navigate về trang order history
              if (widget.account.mode == AccountMode.orderStatus &&
                  !_orderStatusChecked) {
                setState(() => _pendingOrderStatusNavigation = true);
              }
            }
            if (p.fakeBrowser) {
              _controller.runJavaScript(buildAntiFingerprintScript(_profile));
            }
          },
          onPageFinished: (url) async {
            // Reset freeze watchdog mỗi khi page load xong
            _resetPageFreezeWatchdog();
            setState(() {
              _currentUrl = url;
              _loading = false;
            });

            // Sau システムエラー hậu OTP: navigate đến startUrl xong → check
            // Case A: KHÔNG phải login page (session còn) → để flow tiếp tục
            // Case B: LÀ login page → trigger full recover (clear+5G+reload+autofill)
            if (_checkLoginAfterOtpError) {
              setState(() => _checkLoginAfterOtpError = false);
              if (_isLoginPage(url)) {
                _setStatus('🔁 Session mất — full recover...');
                unawaited(_recoverAndRetry());
                return;
              }
              // Case A: session OK → fall through để các flow lottery/orderStatus tự xử lý
            }

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

            // Sau OTP thành công trong orderStatus mode → điều hướng đến trang order history
            if (_pendingOrderStatusNavigation &&
                !_orderStatusChecked &&
                p.orderHistoryUrl.isNotEmpty) {
              setState(() => _pendingOrderStatusNavigation = false);
              final base = p.orderHistoryUrl.contains('?')
                  ? p.orderHistoryUrl.split('?').first
                  : p.orderHistoryUrl;
              if (!url.startsWith(base)) {
                unawaited(
                  _controller.loadRequest(Uri.parse(p.orderHistoryUrl)),
                );
                return;
              }
            }

            // Block images nếu được bật
            if (p.blockImages && mounted) {
              unawaited(_controller.runJavaScript('''
(function(){
  if(document.getElementById('__bi__'))return;
  var s=document.createElement('style');
  s.id='__bi__';
  s.textContent='img,picture,video{visibility:hidden!important;height:0!important;width:0!important;}[style*="background-image"]{background-image:none!important;}';
  document.head&&document.head.appendChild(s);
})();
'''));
            }

            // Auto-fill email + password trên trang login
            // _loginAttemptTime != null nghĩa là đã click login rồi → không fill lại để tránh loop
            if (_isLoginPage(url) && _lastAutoFillUrl != url && !_autoFilling && _loginAttemptTime == null) {
              _lastAutoFillUrl = url;
              await _waitForElement([
                'input[type="email"]',
                'input[name="email"]',
                'input[name="loginEmail"]',
                'input[id*="email"]',
              ], timeout: 3000);
              // Re-check: handler khác có thể đã bắt đầu fill hoặc login đã được click
              if (!mounted || _autoFilling || _loginAttemptTime != null) return;
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

            // Trigger order status extraction khi đang ở trang order history
            if (mounted &&
                widget.account.mode == AccountMode.orderStatus &&
                !_orderStatusChecked &&
                p.orderHistoryUrl.isNotEmpty &&
                url.startsWith(
                    p.orderHistoryUrl.contains('?')
                        ? p.orderHistoryUrl.split('?').first
                        : p.orderHistoryUrl)) {
              _orderStatusChecked = true;
              unawaited(_performOrderStatusCheck());
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
              // Phát hiện reCAPTCHA / trang bị block (chạy sau OTP detect)
              await _controller.runJavaScript(_captchaDetectJs);
            }
          },
          onWebResourceError: (_) => setState(() => _loading = false),
        ),
      )
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (msg) => _handleJsMessage(msg.message),
      );

    // FRESH SESSION — clear toàn bộ và verify
    await _wipeAllSessionData(showStatus: true);
    if (!mounted) return;

    await _controller.loadRequest(Uri.parse(startUrl));
    if (mounted) setState(() => _currentUrl = startUrl);
  }

  /// Xóa SẠCH cookies + localStorage + sessionStorage + IndexedDB + CacheStorage
  /// + Service Workers. Có verify từng bước và hiển thị status để user biết.
  Future<void> _wipeAllSessionData({bool showStatus = true}) async {
    if (showStatus) _setStatus('🧹 Đang xóa cookies + storage + cache...');

    // 1. Cookies qua API (HTTP layer)
    try { await WebViewCookieManager().clearCookies(); } catch (_) {}
    if (!mounted) return;

    // 2. Load about:blank để có JS context riêng
    try {
      await _controller.loadRequest(Uri.parse('about:blank'));
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
    } catch (_) {}

    // 3. Wipe storage + verify
    try {
      final res = await _controller.runJavaScriptReturningResult('''
(function(){
  var before = {ls: 0, ss: 0, idb: 0, cs: 0, sw: 0};
  var after  = {ls: 0, ss: 0, idb: 0, cs: 0, sw: 0};
  try { before.ls = localStorage.length; localStorage.clear(); after.ls = localStorage.length; } catch(e){}
  try { before.ss = sessionStorage.length; sessionStorage.clear(); after.ss = sessionStorage.length; } catch(e){}
  // IndexedDB
  try {
    if (indexedDB && indexedDB.databases) {
      indexedDB.databases().then(function(dbs){
        before.idb = dbs.length;
        dbs.forEach(function(db){try{indexedDB.deleteDatabase(db.name);}catch(e){}});
      });
    }
  } catch(e){}
  // CacheStorage
  try {
    if (window.caches && caches.keys) {
      caches.keys().then(function(ks){
        before.cs = ks.length;
        ks.forEach(function(k){caches.delete(k);});
      });
    }
  } catch(e){}
  // Service Workers
  try {
    if (navigator.serviceWorker && navigator.serviceWorker.getRegistrations) {
      navigator.serviceWorker.getRegistrations().then(function(regs){
        before.sw = regs.length;
        regs.forEach(function(r){try{r.unregister();}catch(e){}});
      });
    }
  } catch(e){}
  return JSON.stringify(before);
})()
''');
      // Result có thể là string JSON với escape, parse cẩn thận
      var raw = res.toString();
      if (raw.startsWith('"') && raw.endsWith('"')) {
        raw = raw.substring(1, raw.length - 1).replaceAll(r'\"', '"');
      }
      try {
        final stats = jsonDecode(raw) as Map<String, dynamic>;
        final ls = stats['ls'] ?? 0;
        final ss = stats['ss'] ?? 0;
        final idb = stats['idb'] ?? 0;
        final cs = stats['cs'] ?? 0;
        final sw = stats['sw'] ?? 0;
        if (showStatus) {
          _setStatus(
            '✅ Đã xóa: cookies + LS:$ls + SS:$ss + IDB:$idb + Cache:$cs + SW:$sw',
          );
        }
      } catch (_) {
        if (showStatus) _setStatus('✅ Đã xóa cookies + storage + cache');
      }
      // Đợi 1.5s để user kịp đọc
      await Future.delayed(const Duration(milliseconds: 1500));
    } catch (_) {
      if (showStatus) _setStatus('⚠️ Clear một phần — tiếp tục anyway');
      await Future.delayed(const Duration(milliseconds: 500));
    }
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

    // Order status extraction response
    if (message.contains('"type":"orderStatusResult"')) {
      try {
        final data = jsonDecode(message) as Map<String, dynamic>;
        final items = (data['data'] as List?) ?? [];
        if (_orderStatusCompleter?.isCompleted == false) {
          _orderStatusCompleter!.complete(items);
        }
      } catch (_) {}
      return;
    }

    // OTP field phát hiện → auto submit
    if (message.contains('"type":"otpField"') &&
        message.contains('"detected":true')) {
      // Login thành công → reset captcha retry counter
      _captchaRetryCount = 0;
      // Chỉ trigger 1 lần cho mỗi URL để tránh spam
      if (!_otpAutoSubmitting && _lastOtpPageUrl != _currentUrl) {
        _lastOtpPageUrl = _currentUrl;
        _otpRetryCount = 0;
        _otpFreezeRetryCount = 0; // Reset freeze counter cho trang OTP mới
        _setStatus('📡 Đang lấy OTP...');
        // Clipboard mode: mở app Mail để user thấy email chứa OTP
        if (context.read<AppProvider>().isClipboardOtpMode) {
          unawaited(_openMailApp());
        }
        unawaited(_autoSubmitOtp());
      }
      return;
    }

    // reCAPTCHA / trang bị block → clear cookies + đổi UA + 5G + retry
    if (message.contains('"type":"captchaError"')) {
      if (!_otpAutoSubmitting && !_resultChecked && !_orderStatusChecked) {
        // Trang lỗi sau OTP → relogin nhẹ, không clear cookie
        if (_passedOtpPage) {
          unawaited(_reloginAfterOtpError());
          return;
        }
        if (_captchaRetryCount < _maxCaptchaRetries) {
          unawaited(_recoverAndRetry());
        } else {
          _setStatus('❌ reCAPTCHA $_maxCaptchaRetries lần liên tiếp — skip account');
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) _skipCurrentAccount();
          });
        }
      }
      return;
    }

    // Phát hiện lỗi OTP → cancel freeze watchdog + retry
    if (message.contains('"type":"otpError"') &&
        message.contains('"detected":true')) {
      _otpFreezeTimer?.cancel();
      _otpFreezeTimer = null;
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
        // Sau 5s kiểm tra lỗi OTP nếu trang chưa chuyển (không reset state)
        Future.delayed(const Duration(seconds: 5), () {
          if (!mounted || _currentUrl != _lastOtpPageUrl) return;
          _controller.runJavaScript(_detectOtpFieldJs);
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

    // Watchdog: nếu trang không chuyển sau 60s kể từ khi submit → kiểm tra session
    _otpFreezeTimer?.cancel();
    _otpFreezeTimer = Timer(const Duration(seconds: 60), () {
      if (!mounted) return;
      if (_currentUrl == _lastOtpPageUrl) {
        unawaited(_handleOtpFreeze());
      }
    });
  }

  void _handleOtpError() async {
    _otpFreezeTimer?.cancel();
    _otpFreezeTimer = null;

    if (_otpRetryCount >= _maxOtpRetries) {
      setState(() => _otpAutoSubmitting = false);
      _setStatus('❌ Sai OTP $_maxOtpRetries lần — skip account');
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) _skipCurrentAccount();
      return;
    }
    _otpRetryCount++;
    final otpUrl = _lastOtpPageUrl;
    _setStatus('⚠️ Sai OTP — reload trang + chờ mã mới... ($_otpRetryCount/$_maxOtpRetries)');

    setState(() => _otpAutoSubmitting = false);

    // Reload OTP page để tránh submit lại mã cũ vào form đã có lỗi
    // Giữ _lastOtpPageUrl nguyên để tránh _autoSubmitOtp tự trigger
    if (otpUrl != null) {
      await _controller.loadRequest(Uri.parse(otpUrl));
      await _waitForElement([
        'input#authCode',
        'input[name="dwfrm_factor2Auth_authCode"]',
        'input[name="passcode"]',
        'input[maxlength="6"]',
      ], timeout: 5000);
    }

    if (!mounted) return;
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
    _setStatus('❌ Không nhận OTP mới sau 90s — skip account');
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) _skipCurrentAccount();
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

  Future<void> _performOrderStatusCheck() async {
    if (!mounted) return;
    final provider = context.read<AppProvider>();
    final email = widget.account.email;
    final keyword = provider.targetProductName;

    _setStatus('📦 Đang kiểm tra tình trạng order...');

    await Future.delayed(const Duration(milliseconds: 800));

    await _waitForElement(['.comOrderList', '.comOrderList > li'], timeout: 5000);

    _orderStatusCompleter = Completer<List<dynamic>>();
    await _controller.runJavaScript(_orderStatusExtractJs);

    List<dynamic> items;
    try {
      items = await _orderStatusCompleter!.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      _setStatus('❌ Không lấy được tình trạng order');
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) Navigator.of(context).pop();
      return;
    }

    if (items.isEmpty) {
      provider.addOrderStatusResult(OrderStatusEntry(
        accountEmail: email, productTitle: keyword,
        orderNum: '', status: '対象なし', time: ''));
      _setStatus('⚠️ Không có order nào trong lịch sử');
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final kw = keyword.toLowerCase();
    for (final item in items) {
      final title = ((item['title'] as String?) ?? '').toLowerCase();
      if (kw.isEmpty || title.contains(kw)) {
        final status = item['status'] as String? ?? '';
        final entry = OrderStatusEntry(
          accountEmail: email,
          productTitle: item['title'] as String? ?? '',
          orderNum: item['orderNum'] as String? ?? '',
          status: status.isNotEmpty ? status : 'エラー',
          time: item['time'] as String? ?? '',
        );
        provider.addOrderStatusResult(entry);
        final icon = entry.isShipped ? '🚚' : entry.isPreparing ? '📦' : '📋';
        _setStatus('$icon ${entry.status} — ${entry.productTitle}');
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.of(context).pop();
        return;
      }
    }

    provider.addOrderStatusResult(OrderStatusEntry(
      accountEmail: email, productTitle: keyword,
      orderNum: '', status: '対象なし', time: ''));
    _setStatus('対象なし — không tìm thấy order "$keyword"');
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) Navigator.of(context).pop();
  }

  /// reCAPTCHA / block detected: clear cookies → đổi profile → 5G → retry login
  Future<void> _recoverAndRetry() async {
    if (!mounted) return;
    // Cancel freeze watchdog — recovery sẽ tự navigate → onPageStarted reset lại
    _pageFreezeTimer?.cancel();
    _pageFreezeTimer = null;
    _captchaRetryCount++;
    // Capture context-dependent values trước await
    final p = context.read<AppProvider>();
    _setStatus('🛡️ reCAPTCHA detected — reset lần $_captchaRetryCount/$_maxCaptchaRetries...');

    // Chờ 3s để trang hiển thị lỗi xong trước khi reset (user-requested)
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    // 1. Xóa SẠCH tất cả + verify + hiển thị status
    await _wipeAllSessionData(showStatus: true);
    if (!mounted) return;

    // 2. Đổi sang device profile mới (đảm bảo KHÁC profile cũ) + apply UA
    final newProfile = randomProfile(except: _profile);
    setState(() {
      _profile = newProfile;
      _lastAutoFillUrl = null;
      _lastOtpPageUrl = null;
      _otpAutoSubmitting = false;
      _loginAttemptTime = null;
      _passedOtpPage = false;
    });
    await _controller.setUserAgent(_profile.userAgent);

    // 3. Đổi 5G nếu được bật
    if (p.shortcut5gEnabled) {
      _setStatus('⚡ Đổi 5G...');
      await ShortcutService.triggerShortcut('5G');
      await Future.delayed(const Duration(seconds: 5));
    } else {
      await Future.delayed(const Duration(seconds: 3));
    }

    if (!mounted) return;

    // 4. Random delay thêm 1-4s để tránh pattern bot (giả lập hành vi người dùng)
    final extraMs = 1000 + (DateTime.now().millisecond % 3000);
    await Future.delayed(Duration(milliseconds: extraMs));
    if (!mounted) return;

    // 5. Reload URL ban đầu (startUrl) — không phải luôn loginUrl
    _setStatus('🔃 Login lại...');
    final target = widget.startUrl ?? p.loginUrl;
    await _controller.loadRequest(Uri.parse(target));
  }

  /// Sau システムエラー hậu OTP — đợi 2s, navigate đến startUrl, rồi check:
  /// - Nếu KHÔNG về trang login (session OK) → để flow tiếp tục bình thường
  /// - Nếu VỀ trang login → trigger full recover (clear+5G+reload+autofill)
  Future<void> _reloginAfterOtpError() async {
    if (!mounted) return;
    _setStatus('⚠️ システムエラー sau OTP — chờ 2s rồi check lại...');
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    final p = context.read<AppProvider>();
    setState(() {
      _loginAttemptTime = null;
      _lastAutoFillUrl = null;
      _lastOtpPageUrl = null;
      _otpAutoSubmitting = false;
      _passedOtpPage = false;
      _checkLoginAfterOtpError = true;
    });
    _setStatus('🔃 Đi đến URL ban đầu...');
    final target = widget.startUrl ?? p.loginUrl;
    await _controller.loadRequest(Uri.parse(target));
  }

  /// Skip account hiện tại: nếu đang chạy all thì gọi callback, không thì đóng browser
  void _skipCurrentAccount() {
    if (widget.isRunningAll && widget.onSkipCurrent != null) {
      widget.onSkipCurrent!();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// OTP page không phản hồi sau 60s: navigate đến loginUrl, kiểm tra session
  /// - Không phải trang login (session còn) → tiếp tục các bước lottery/order
  /// - Là trang login (session mất) → nhập lại email/password + login
  Future<void> _handleOtpFreeze() async {
    if (!mounted) return;
    _otpFreezeTimer?.cancel();
    _otpFreezeTimer = null;

    if (_otpFreezeRetryCount >= _maxOtpFreezeRetries) {
      setState(() => _otpAutoSubmitting = false);
      _setStatus('❌ OTP đơ $_maxOtpFreezeRetries lần — skip account');
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) _skipCurrentAccount();
      return;
    }

    _otpFreezeRetryCount++;
    _setStatus('⏰ OTP không phản hồi 60s — kiểm tra session...');
    setState(() {
      _otpAutoSubmitting = false;
      _checkLoginAfterOtpError = true;
    });

    await _controller.loadRequest(
      Uri.parse('https://www.pokemoncenter-online.com/mypage/'),
    );
  }

  Future<void> _openMailApp() async {
    try {
      await _utilsChannel.invokeMethod('openMailApp');
    } catch (_) {}
  }

  Future<void> _autoFill({bool silent = false}) async {
    if (!silent) {
      // Manual trigger: reset để cho phép nhận OTP mới
      _loginAttemptTime = null;
    } else {
      // Auto trigger: set ngay để ngăn onPageFinished gọi lại _autoFill trong khi đang fill
      _loginAttemptTime = DateTime.now();
    }
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

      // Copy email vào clipboard trước khi click login
      // → giúp user biết email nào cần check khi mở app Mail
      await Clipboard.setData(ClipboardData(text: widget.account.email));

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
            Row(
              children: [
                Flexible(
                  child: Text(
                    widget.account.email,
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.accountIndex != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withAlpha(40),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.accent.withAlpha(100)),
                    ),
                    child: Text(
                      '${widget.accountIndex}/${widget.totalAccounts}',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            Row(
              children: [
                Flexible(
                  child: Text(
                    _currentUrl.length > 32
                        ? '${_currentUrl.substring(0, 32)}...'
                        : _currentUrl,
                    style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _shortUaLabel(_profile.userAgent),
                  style: const TextStyle(fontSize: 10, color: AppColors.secondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Nút shuffle UA (#2)
          IconButton(
            icon: const Icon(Icons.shuffle, color: AppColors.secondary, size: 20),
            tooltip: 'Đổi User Agent ngẫu nhiên',
            onPressed: () async {
              final newProfile = randomProfile(except: _profile);
              setState(() {
                _profile = newProfile;
                _lastAutoFillUrl = null;
              });
              await _controller.setUserAgent(_profile.userAgent);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('UA: ${_profile.name}  •  ${_shortUaLabel(_profile.userAgent)}'),
                  backgroundColor: AppColors.surfaceVariant,
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              _controller.reload();
            },
          ),
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
      body: Column(
        children: [
          _buildProgressBanner(),
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_loading)
                  const LinearProgressIndicator(
                    backgroundColor: AppColors.surfaceVariant,
                    valueColor: AlwaysStoppedAnimation(AppColors.primary),
                  ),
              ],
            ),
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
                  // Nút relogin thủ công (#7)
                  IconButton(
                    icon: const Icon(Icons.login, size: 18, color: AppColors.warning),
                    tooltip: 'Relogin',
                    onPressed: () {
                      setState(() {
                        _loginAttemptTime = null;
                        _lastAutoFillUrl = null;
                        _lastOtpPageUrl = null;
                        _otpAutoSubmitting = false;
                        _passedOtpPage = false;
                      });
                      _controller.loadRequest(
                        Uri.parse(context.read<AppProvider>().loginUrl),
                      );
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

  /// Banner thống kê realtime cho lotteryResult / orderStatus mode
  Widget _buildProgressBanner() {
    final mode = widget.account.mode;
    if (mode != AccountMode.lotteryResult && mode != AccountMode.orderStatus) {
      return const SizedBox.shrink();
    }
    return Consumer<AppProvider>(
      builder: (ctx, p, _) {
        if (mode == AccountMode.lotteryResult) {
          return _lotteryBanner(p.lotteryResults);
        }
        return _orderStatusBanner(p.orderStatusResults);
      },
    );
  }

  Widget _lotteryBanner(List<LotteryResultEntry> rows) {
    final won = rows.where((r) => r.isWon).length;
    final lost = rows.where((r) => r.isLost).length;
    final err = rows.where((r) => r.isError).length;
    final noResult = rows.where((r) => r.result == '対象なし' || r.result == '結果なし').length;
    final pending = rows.where((r) => r.result == '未定').length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Text('🎯',
                style: TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Text(
              '${rows.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            _bannerChip('当選', won, AppColors.done),
            _bannerChip('落選', lost, AppColors.error),
            if (pending > 0) _bannerChip('未定', pending, AppColors.secondary),
            if (err > 0) _bannerChip('エラー', err, AppColors.warning),
            if (noResult > 0) _bannerChip('対象なし', noResult, AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _orderStatusBanner(List<OrderStatusEntry> rows) {
    final received = rows.where((e) => e.isReceived).length;
    final preparing = rows.where((e) => e.isPreparing).length;
    final shipped = rows.where((e) => e.isShipped).length;
    final cancelled = rows.where((e) => e.isCancelled).length;
    final err = rows.where((e) => e.status == 'エラー').length;
    final noResult = rows.where((e) => e.status == '対象なし').length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Text('📦',
                style: TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Text(
              '${rows.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            _bannerChip('受付', received, AppColors.primary),
            _bannerChip('準備中', preparing, AppColors.secondary),
            _bannerChip('発送済', shipped, AppColors.done),
            if (cancelled > 0) _bannerChip('キャンセル', cancelled, Colors.grey),
            if (err > 0) _bannerChip('エラー', err, AppColors.warning),
            if (noResult > 0) _bannerChip('対象なし', noResult, AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _bannerChip(String label, int count, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 5),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
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
