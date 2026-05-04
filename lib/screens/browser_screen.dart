import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/account.dart';
import '../models/proxy.dart';
import '../providers/app_provider.dart';
import '../utils/app_theme.dart';
import '../utils/device_profiles.dart';

class BrowserScreen extends StatefulWidget {
  final Account account;
  final Proxy? proxy;
  final String? startUrl;

  const BrowserScreen({super.key, required this.account, this.proxy, this.startUrl});

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

  // OTP auto-submit
  bool _otpAutoSubmitting = false;
  String? _lastOtpPageUrl; // tránh trigger lại cùng một URL
  int _otpRetryCount = 0;
  static const int _maxOtpRetries = 3;
  String? _lastSubmittedOtp;

  // Thời điểm bấm ログイン — chỉ lấy OTP gửi SAU thời điểm này
  DateTime? _loginAttemptTime;

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

  @override
  void initState() {
    super.initState();
    _profile = randomProfile();
    final startUrl = widget.startUrl ?? context.read<AppProvider>().loginUrl;
    _initController(startUrl);
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

  void _initController(String startUrl) {
    final p = context.read<AppProvider>();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          setState(() {
            _currentUrl = url;
            _loading = true;
          });
          if (p.fakeBrowser) {
            _controller.runJavaScript(buildAntiFingerprintScript(_profile));
          }
        },
        onPageFinished: (url) async {
          setState(() { _currentUrl = url; _loading = false; });
          _controller.canGoBack().then((v) => setState(() => _canGoBack = v));
          _controller.canGoForward().then((v) => setState(() => _canGoForward = v));

          if (p.fakeBrowser) {
            await _controller.runJavaScript(buildAntiFingerprintScript(_profile));
          }

          // Auto-fill email + password trên trang login
          if (_isLoginPage(url) && _lastAutoFillUrl != url && !_autoFilling) {
            _lastAutoFillUrl = url;
            await Future.delayed(const Duration(milliseconds: 700));
            await _autoFill(silent: true);
          }

          // Dùng JS để phát hiện field OTP — không phụ thuộc vào URL
          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) {
            await _controller.runJavaScript(_detectOtpFieldJs);
          }
        },
        onWebResourceError: (_) => setState(() => _loading = false),
      ))
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (msg) => _handleJsMessage(msg.message),
      )
      ..loadRequest(Uri.parse(startUrl));

    setState(() => _currentUrl = startUrl);
  }

  void _handleJsMessage(String message) {
    // OTP field phát hiện → auto submit
    if (message.contains('"type":"otpField"') && message.contains('"detected":true')) {
      // Chỉ trigger 1 lần cho mỗi URL để tránh spam
      if (!_otpAutoSubmitting && _lastOtpPageUrl != _currentUrl) {
        _lastOtpPageUrl = _currentUrl;
        _otpRetryCount = 0;
        _autoSubmitOtp();
      }
      return;
    }

    // Phát hiện lỗi OTP → retry
    if (message.contains('"type":"otpError"') && message.contains('"detected":true')) {
      if (_otpAutoSubmitting || _lastOtpPageUrl == _currentUrl) {
        _handleOtpError();
      }
      return;
    }

    // Status feedback từ buildOtpAutoSubmitScript
    if (message.contains('"type":"otpStatus"')) {
      if (message.contains('"status":"filled"')) {
        setState(() => _statusText = '⌨️ Đã điền OTP...');
      } else if (message.contains('"status":"submitted"')) {
        setState(() { _statusText = '⏳ Đang xác nhận...'; });
        // Sau 3s kiểm tra lại xem có lỗi không
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _currentUrl == _lastOtpPageUrl) {
            _controller.runJavaScript(_detectOtpFieldJs);
          }
          if (mounted) setState(() { _otpAutoSubmitting = false; });
        });
      } else if (message.contains('"status":"noField"')) {
        setState(() { _statusText = ''; _otpAutoSubmitting = false; });
      } else if (message.contains('"status":"noButton"')) {
        setState(() { _statusText = '⚠️ Không thấy nút 認証する'; _otpAutoSubmitting = false; });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _statusText = '');
        });
      }
    }
  }

  String? _getOtpForAccount() =>
      context.read<AppProvider>().latestOtpForEmail(
        widget.account.email,
        after: _loginAttemptTime,
      );

  Future<void> _autoSubmitOtp() async {
    if (!mounted) return;
    final otp = _getOtpForAccount();

    if (otp == null) {
      setState(() => _statusText = '⏳ Chờ OTP cho ${widget.account.email}...');
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        final newOtp = _getOtpForAccount();
        if (newOtp != null) {
          await _doSubmitOtp(newOtp);
          return;
        }
      }
      if (mounted) setState(() { _statusText = '❌ Không nhận OTP sau 30s'; _otpAutoSubmitting = false; });
      return;
    }

    await _doSubmitOtp(otp);
  }

  Future<void> _doSubmitOtp(String otp) async {
    if (!mounted) return;
    setState(() {
      _otpAutoSubmitting = true;
      _lastSubmittedOtp = otp;
      _statusText = '🔢 Điền OTP: $otp';
    });
    await _controller.runJavaScript(buildOtpAutoSubmitScript(otp));
  }

  void _handleOtpError() async {
    if (_otpRetryCount >= _maxOtpRetries) {
      setState(() { _statusText = '❌ Sai OTP ${_maxOtpRetries} lần, dừng lại'; _otpAutoSubmitting = false; });
      return;
    }
    _otpRetryCount++;
    setState(() => _statusText = '❌ Sai OTP, chờ mã mới... (${_otpRetryCount}/$_maxOtpRetries)');

    // Chờ OTP mới (khác mã vừa dùng)
    for (int i = 0; i < 60; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      final newOtp = _getOtpForAccount();
      if (newOtp != null && newOtp != _lastSubmittedOtp) {
        await _doSubmitOtp(newOtp);
        return;
      }
    }
    if (mounted) setState(() { _statusText = '❌ Không có OTP mới sau 60s'; _otpAutoSubmitting = false; });
  }

  Future<void> _autoFill({bool silent = false}) async {
    // Reset login timestamp khi bắt đầu lại flow login
    _loginAttemptTime = null;
    setState(() { _autoFilling = true; _statusText = '📧 Điền email + password...'; });
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      await _controller.runJavaScript(
          buildAutoFillScript(widget.account.email, widget.account.password));
      setState(() => _statusText = '🔐 Đang login...');
      await Future.delayed(const Duration(milliseconds: 700));

      // Ghi lại thời điểm bấm ログイン — chỉ nhận OTP từ sau thời điểm này
      _loginAttemptTime = DateTime.now();

      await _controller.runJavaScript('''
(function() {
  var btns = Array.from(document.querySelectorAll('button, input[type="submit"], a[role="button"]'));
  for (var i = 0; i < btns.length; i++) {
    var t = btns[i].textContent || btns[i].value || '';
    if (t.indexOf('ログイン') >= 0 || t.indexOf('送信') >= 0 ||
        t.toLowerCase().indexOf('login') >= 0 || t.toLowerCase().indexOf('sign in') >= 0) {
      btns[i].click(); break;
    }
  }
})();
''');
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _statusText = '');
    } catch (_) {
      if (mounted) setState(() => _statusText = '');
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
        title: const Text('Thông tin Proxy', style: TextStyle(color: Colors.white)),
        content: proxy == null
            ? const Text('Không dùng proxy', style: TextStyle(color: AppColors.textSecondary))
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
          ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Text('$label: ', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          Flexible(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13))),
        ]),
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
            Text(widget.account.email,
                style: const TextStyle(fontSize: 13, color: Colors.white),
                overflow: TextOverflow.ellipsis),
            Text(
              _currentUrl.length > 45 ? '${_currentUrl.substring(0, 45)}...' : _currentUrl,
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (widget.proxy != null)
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
          if (_statusText.isNotEmpty)
            Positioned(
              top: 8, left: 16, right: 16,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.secondary),
                    boxShadow: [BoxShadow(color: Colors.black.withAlpha(120), blurRadius: 8)],
                  ),
                  child: Row(children: [
                    const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(AppColors.secondary)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_statusText,
                        style: const TextStyle(color: Colors.white, fontSize: 13))),
                  ]),
                ),
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
              Row(children: [
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
                      ? const SizedBox(width: 12, height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_fix_high, size: 14),
                  label: Text(_autoFilling ? '...' : 'Tự điền',
                      style: const TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _autoFilling ? AppColors.card : AppColors.secondary,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                ),
              ]),
              // Browser controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios, size: 18,
                        color: _canGoBack ? Colors.white : AppColors.textSecondary),
                    onPressed: _canGoBack ? () => _controller.goBack() : null,
                  ),
                  IconButton(
                    icon: Icon(Icons.arrow_forward_ios, size: 18,
                        color: _canGoForward ? Colors.white : AppColors.textSecondary),
                    onPressed: _canGoForward ? () => _controller.goForward() : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: () {
                      // Reset state khi reload để trigger lại detection
                      setState(() { _lastOtpPageUrl = null; _otpAutoSubmitting = false; });
                      _controller.reload();
                    },
                  ),
                  // OTP display — nhấn để fill + submit thủ công
                  Consumer<AppProvider>(
                    builder: (_, prov, __) {
                      final otp = prov.latestOtpForEmail(
                        widget.account.email,
                        after: _loginAttemptTime,
                      );
                      return GestureDetector(
                        onTap: otp != null ? () => _doSubmitOtp(otp) : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: otp != null ? AppColors.done : AppColors.card,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.sms, size: 14, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              otp ?? 'OTP',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: otp != null ? FontWeight.bold : FontWeight.normal,
                                fontSize: 13,
                                letterSpacing: otp != null ? 2 : 0,
                              ),
                            ),
                          ]),
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
            setState(() { _lastOtpPageUrl = null; _otpAutoSubmitting = false; });
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
          child: Text(label,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      );
}
