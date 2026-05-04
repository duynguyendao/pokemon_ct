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

  const BrowserScreen({super.key, required this.account, this.proxy});

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

  // OTP auto-submit state
  bool _otpAutoSubmitting = false;
  int _otpRetryCount = 0;
  static const int _maxOtpRetries = 3;
  String? _lastSubmittedOtp;

  @override
  void initState() {
    super.initState();
    _profile = randomProfile();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<AppProvider>();
      _initController(p.loginUrl);
    });
  }

  bool _isLoginPage(String url) {
    final u = url.toLowerCase();
    return u.contains('/login') &&
        !u.contains('passcode') &&
        !u.contains('otp') &&
        !u.contains('code') &&
        !u.contains('verify');
  }

  bool _isOtpPage(String url) {
    final u = url.toLowerCase();
    return u.contains('passcode') ||
        u.contains('/otp') ||
        u.contains('/authenticate') ||
        u.contains('/verify');
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
            _otpRetryCount = 0;
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

          // Auto-fill credentials on login page
          if (_isLoginPage(url) && _lastAutoFillUrl != url && !_autoFilling) {
            _lastAutoFillUrl = url;
            await Future.delayed(const Duration(milliseconds: 600));
            await _autoFill(silent: true);
          }

          // Auto-fill OTP + submit on passcode page
          if (_isOtpPage(url) && !_otpAutoSubmitting) {
            await Future.delayed(const Duration(milliseconds: 800));
            await _autoSubmitOtp();
          }

          // Check for OTP error message
          if (_isOtpPage(url)) {
            await Future.delayed(const Duration(milliseconds: 500));
            await _controller.runJavaScript(buildOtpErrorDetectScript());
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
    try {
      if (message.contains('"type":"otpStatus"')) {
        if (message.contains('"status":"filled"')) {
          setState(() => _statusText = '⌨️ Đã điền OTP...');
        } else if (message.contains('"status":"submitted"')) {
          setState(() { _statusText = '⏳ Đang xác nhận...'; _otpAutoSubmitting = false; });
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) setState(() => _statusText = '');
          });
        } else if (message.contains('"status":"noField"') || message.contains('"status":"noButton"')) {
          setState(() { _statusText = ''; _otpAutoSubmitting = false; });
        }
      } else if (message.contains('"type":"otpError"') && message.contains('"detected":true')) {
        _handleOtpError();
      }
    } catch (_) {}
  }

  Future<void> _autoSubmitOtp() async {
    final otp = context.read<AppProvider>().latestOtp;
    if (otp == null) {
      setState(() => _statusText = '⏳ Chờ OTP từ email...');
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        final newOtp = context.read<AppProvider>().latestOtp;
        if (newOtp != null) {
          await _doSubmitOtp(newOtp);
          return;
        }
      }
      if (mounted) setState(() => _statusText = '❌ Không nhận được OTP');
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
      setState(() { _statusText = '❌ Sai OTP ${_maxOtpRetries}x, dừng'; _otpAutoSubmitting = false; });
      return;
    }
    _otpRetryCount++;
    setState(() => _statusText = '❌ Sai OTP, chờ mã mới... (${_otpRetryCount}/$_maxOtpRetries)');

    for (int i = 0; i < 60; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      final newOtp = context.read<AppProvider>().latestOtp;
      if (newOtp != null && newOtp != _lastSubmittedOtp) {
        await _doSubmitOtp(newOtp);
        return;
      }
    }
    if (mounted) setState(() { _statusText = '❌ Không nhận OTP mới sau 60s'; _otpAutoSubmitting = false; });
  }

  Future<void> _autoFill({bool silent = false}) async {
    setState(() { _autoFilling = true; _statusText = '📧 Điền email...'; });
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      await _controller.runJavaScript(
          buildAutoFillScript(widget.account.email, widget.account.password));
      setState(() => _statusText = '✅ Điền xong - Đang login...');
      await Future.delayed(const Duration(milliseconds: 600));

      await _controller.runJavaScript('''
(function() {
  const btns = Array.from(document.querySelectorAll('button, input[type="submit"], a[role="button"]'));
  for (const btn of btns) {
    const t = btn.textContent || btn.value || '';
    if (t.includes('ログイン') || t.includes('送信') || t.toLowerCase().includes('login') || t.toLowerCase().includes('sign in')) {
      btn.click(); break;
    }
  }
})();
''');
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        setState(() => _statusText = '');
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Đã login - Chờ OTP'), duration: Duration(seconds: 2)),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _statusText = '');
    } finally {
      setState(() => _autoFilling = false);
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
                      child: CircularProgressIndicator(strokeWidth: 2,
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
              // Quick nav URL buttons
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
              // Browser nav
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
                    onPressed: () => _controller.reload(),
                  ),
                  // OTP display - tap to manually fill
                  Consumer<AppProvider>(
                    builder: (_, prov, __) {
                      final otp = prov.latestOtp;
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
          if (url.isNotEmpty) _controller.loadRequest(Uri.parse(url));
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
