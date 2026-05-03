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
  String _currentUrl = 'https://www.pokemon-card.com/';
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _otpOverlayVisible = false;
  String? _latestOtp;

  static const _startUrl = 'https://www.pokemoncenter-online.com/login/';

  @override
  void initState() {
    super.initState();
    _profile = randomProfile();
    _initController();
  }

  void _initController() {
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
          setState(() {
            _currentUrl = url;
            _loading = false;
          });
          _controller.canGoBack().then((v) => setState(() => _canGoBack = v));
          _controller.canGoForward().then((v) => setState(() => _canGoForward = v));

          if (p.fakeBrowser) {
            await _controller.runJavaScript(buildAntiFingerprintScript(_profile));
          }

          // Check OTP field
          await _controller.runJavaScript('''
(function() {
  const selectors = ['input[name="otp"]','input[name="code"]','input[id*="otp"]','input[maxlength="6"]'];
  for (const s of selectors) {
    if (document.querySelector(s)) {
      window.FlutterChannel.postMessage(JSON.stringify({type: 'otpField', detected: true}));
      break;
    }
  }
})();
''');
        },
        onWebResourceError: (error) {
          setState(() => _loading = false);
        },
      ))
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (msg) => _handleJsMessage(msg.message),
      )
      ..loadRequest(Uri.parse(_startUrl));
  }

  void _handleJsMessage(String message) {
    try {
      // Simple JSON parsing
      if (message.contains('"type":"otpField"') && message.contains('"detected":true')) {
        final otp = context.read<AppProvider>().latestOtp;
        if (otp != null) {
          setState(() {
            _latestOtp = otp;
            _otpOverlayVisible = true;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _autoFill() async {
    await _controller.runJavaScript(
      buildAutoFillScript(widget.account.email, widget.account.password),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã điền thông tin tự động'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _fillOtp(String otp) async {
    await _controller.runJavaScript(buildOtpFillScript(otp));
    setState(() => _otpOverlayVisible = false);
  }

  Future<void> _openInLoginPage() async {
    await _controller.loadRequest(Uri.parse('https://www.pokemon-card.com/'));
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
        child: Row(
          children: [
            Text('$label: ', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            Flexible(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
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
              _currentUrl.length > 40 ? '${_currentUrl.substring(0, 40)}...' : _currentUrl,
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
          IconButton(
            icon: const Icon(Icons.open_in_browser, size: 20),
            onPressed: _openInLoginPage,
            tooltip: 'Trang chủ',
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

          // OTP auto-fill overlay
          if (_otpOverlayVisible && _latestOtp != null)
            Positioned(
              top: 8,
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
                    boxShadow: [BoxShadow(color: Colors.black.withAlpha(100), blurRadius: 8)],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.sms, color: AppColors.secondary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'OTP: $_latestOtp',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: 2,
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () => _fillOtp(_latestOtp!),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.secondary,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                        ),
                        child: const Text('Điền', style: TextStyle(fontSize: 12)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => _otpOverlayVisible = false),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        color: AppColors.surfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_ios, size: 20,
                    color: _canGoBack ? Colors.white : AppColors.textSecondary),
                onPressed: _canGoBack ? () => _controller.goBack() : null,
              ),
              IconButton(
                icon: Icon(Icons.arrow_forward_ios, size: 20,
                    color: _canGoForward ? Colors.white : AppColors.textSecondary),
                onPressed: _canGoForward ? () => _controller.goForward() : null,
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () => _controller.reload(),
              ),
              ElevatedButton.icon(
                onPressed: _autoFill,
                icon: const Icon(Icons.auto_fix_high, size: 16),
                label: const Text('Tự điền', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                ),
              ),
              Consumer<AppProvider>(
                builder: (context, p, child) {
                  final otp = p.latestOtp;
                  return ElevatedButton.icon(
                    onPressed: otp != null
                        ? () {
                            setState(() {
                              _latestOtp = otp;
                              _otpOverlayVisible = true;
                            });
                          }
                        : null,
                    icon: const Icon(Icons.sms, size: 16),
                    label: Text(otp ?? 'OTP', style: const TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: otp != null ? AppColors.done : AppColors.card,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: Size.zero,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
