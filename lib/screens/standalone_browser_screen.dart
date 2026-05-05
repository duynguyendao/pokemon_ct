import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../providers/app_provider.dart';
import '../utils/app_theme.dart';
import '../utils/device_profiles.dart';

// Known fingerprint / proxy check sites
const _quickSites = [
  ('🔍 Fingerprint', 'https://fingerprintjs.github.io/fingerprintjs/'),
  ('🕵️ BrowserLeaks', 'https://browserleaks.com/'),
  ('🌐 IP Check', 'https://whoer.net/'),
  ('🔒 Proxy Check', 'https://proxycheck.io/'),
  ('🎯 CreepJS', 'https://abrahamjuliot.github.io/creepjs/'),
  ('📡 IPLeak', 'https://ipleak.net/'),
];

class StandaloneBrowserScreen extends StatefulWidget {
  final String? initialUrl;

  const StandaloneBrowserScreen({super.key, this.initialUrl});

  @override
  State<StandaloneBrowserScreen> createState() =>
      _StandaloneBrowserScreenState();
}

class _StandaloneBrowserScreenState extends State<StandaloneBrowserScreen> {
  late final WebViewController _controller;
  late DeviceProfile _profile;

  final _urlController = TextEditingController();
  final _urlFocusNode = FocusNode();

  bool _loading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String _currentUrl = '';
  String _pageTitle = '';
  double _loadProgress = 0;

  @override
  void initState() {
    super.initState();
    _profile = randomProfile();
    final start =
        widget.initialUrl ?? 'https://abrahamjuliot.github.io/creepjs/';
    _urlController.text = start;
    _currentUrl = start;
    _initController(start);

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
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    });
  }

  String _shortUaLabel(String ua) {
    final m = RegExp(r'Chrome/([\d.]+)').firstMatch(ua);
    if (m != null) return 'Chrome ${m.group(1)!.split('.').first}';
    final s = RegExp(r'Version/([\d.]+)').firstMatch(ua);
    if (s != null) return 'Safari ${s.group(1)}';
    return ua.length > 28 ? '${ua.substring(0, 28)}…' : ua;
  }

  void _initController(String startUrl) {
    final p = context.read<AppProvider>();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (v) => setState(() => _loadProgress = v / 100),
          onPageStarted: (url) {
            setState(() {
              _currentUrl = url;
              _loading = true;
              _loadProgress = 0;
            });
            _urlController.text = url;
            if (p.fakeBrowser) {
              _controller.runJavaScript(buildAntiFingerprintScript(_profile));
            }
          },
          onPageFinished: (url) async {
            setState(() {
              _currentUrl = url;
              _loading = false;
            });
            _urlController.text = url;
            _controller.canGoBack().then((v) => setState(() => _canGoBack = v));
            _controller
                .canGoForward()
                .then((v) => setState(() => _canGoForward = v));

            if (p.fakeBrowser) {
              await _controller
                  .runJavaScript(buildAntiFingerprintScript(_profile));
            }

            // Get page title
            final title = await _controller.getTitle();
            if (mounted && title != null && title.isNotEmpty) {
              setState(() => _pageTitle = title);
            }
          },
          onWebResourceError: (_) => setState(() => _loading = false),
        ),
      )
      ..loadRequest(Uri.parse(startUrl));
  }

  void _navigate(String input) {
    _urlFocusNode.unfocus();
    var url = input.trim();
    if (url.isEmpty) return;

    // If no scheme and not a domain-looking string, treat as search
    if (!url.contains('://')) {
      if (url.contains('.') && !url.contains(' ')) {
        url = 'https://$url';
      } else {
        url =
            'https://www.google.com/search?q=${Uri.encodeComponent(url)}';
      }
    }

    setState(() {
      _currentUrl = url;
      _pageTitle = '';
    });
    _controller.loadRequest(Uri.parse(url));
  }

  void _reload({bool newProfile = false}) {
    if (newProfile) {
      setState(() {
        _profile = randomProfile();
        _pageTitle = '';
      });
      // Clear storage then reload
      WebViewCookieManager().clearCookies();
      _controller.runJavaScript(
        'try{localStorage.clear();sessionStorage.clear();}catch(e){}',
      );
      final shortUa = _shortUaLabel(_profile.userAgent);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.shuffle, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'UA mới: ${_profile.name}  •  $shortUa',
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1B3A2D),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
    _controller.reload();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          // ── Custom top bar ──────────────────────────────────────────
          Container(
            color: AppColors.surfaceVariant,
            padding: EdgeInsets.fromLTRB(4, topPad + 4, 4, 6),
            child: Column(
              children: [
                // Row 1: back / forward / close + title
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back_ios,
                        size: 18,
                        color: _canGoBack
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                      onPressed:
                          _canGoBack ? () => _controller.goBack() : null,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.arrow_forward_ios,
                        size: 18,
                        color: _canGoForward
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                      onPressed:
                          _canGoForward ? () => _controller.goForward() : null,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                    Expanded(
                      child: Text(
                        _pageTitle.isNotEmpty
                            ? _pageTitle
                            : _profile.name,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    // New UA button
                    Tooltip(
                      message: 'Random UA mới + reload',
                      child: IconButton(
                        icon: const Icon(
                          Icons.shuffle,
                          size: 20,
                          color: AppColors.accent,
                        ),
                        onPressed: () => _reload(newProfile: true),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                  ],
                ),

                // Row 2: URL bar
                Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 10),
                      Icon(
                        _currentUrl.startsWith('https')
                            ? Icons.lock_outline
                            : Icons.lock_open,
                        size: 14,
                        color: _currentUrl.startsWith('https')
                            ? AppColors.done
                            : AppColors.warning,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _urlController,
                          focusNode: _urlFocusNode,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            hintText: 'Nhập URL hoặc tìm kiếm...',
                            hintStyle: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                            filled: false,
                          ),
                          onTap: () => _urlController.selection =
                              TextSelection(
                                baseOffset: 0,
                                extentOffset: _urlController.text.length,
                              ),
                          onSubmitted: _navigate,
                          textInputAction: TextInputAction.go,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                        ),
                      ),
                      if (_loading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation(AppColors.primary),
                          ),
                        )
                      else
                        GestureDetector(
                          onTap: () => _reload(),
                          child: const Icon(
                            Icons.refresh,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      const SizedBox(width: 10),
                    ],
                  ),
                ),

                const SizedBox(height: 4),

                // Row 3: quick-site chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final site in _quickSites)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            onTap: () => _navigate(site.$2),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _currentUrl.contains(
                                          Uri.parse(site.$2).host,
                                        )
                                        ? AppColors.secondary.withAlpha(80)
                                        : AppColors.card,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _currentUrl.contains(
                                            Uri.parse(site.$2).host,
                                          )
                                          ? AppColors.secondary
                                          : AppColors.divider,
                                ),
                              ),
                              child: Text(
                                site.$1,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Copy URL button
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: _currentUrl),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Đã copy URL'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: const Text(
                            '📋 Copy',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Progress bar
          if (_loading && _loadProgress > 0 && _loadProgress < 1)
            LinearProgressIndicator(
              value: _loadProgress,
              backgroundColor: AppColors.surfaceVariant,
              valueColor:
                  const AlwaysStoppedAnimation(AppColors.primary),
              minHeight: 2,
            ),

          // ── Proxy info banner (khi proxy enabled) ──────────────────
          if (p.proxyEnabled && p.proxies.any((px) => px.enabled))
            _ProxyBanner(proxy: p.nextProxy),

          // ── WebView ────────────────────────────────────────────────
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}

class _ProxyBanner extends StatelessWidget {
  final dynamic proxy;

  const _ProxyBanner({this.proxy});

  @override
  Widget build(BuildContext context) {
    if (proxy == null) {
      return Container(
        color: AppColors.warning.withAlpha(20),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: const Row(
          children: [
            Icon(Icons.vpn_lock, size: 13, color: AppColors.warning),
            SizedBox(width: 6),
            Text(
              'Proxy bật nhưng không có proxy nào enabled',
              style: TextStyle(color: AppColors.warning, fontSize: 11),
            ),
          ],
        ),
      );
    }
    return Container(
      color: AppColors.done.withAlpha(20),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.vpn_lock, size: 13, color: AppColors.done),
          const SizedBox(width: 6),
          Text(
            'Proxy: ${proxy.displayLabel}  •  ${proxy.host}:${proxy.port}',
            style: const TextStyle(color: AppColors.done, fontSize: 11),
          ),
          const Spacer(),
          const Text(
            '(WebView dùng proxy hệ thống)',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
