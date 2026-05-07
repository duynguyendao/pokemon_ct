import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/account.dart';
import '../models/lottery_result_entry.dart';
import '../providers/app_provider.dart';
import '../utils/app_theme.dart';
import '../utils/device_profiles.dart';

class OtherScreen extends StatefulWidget {
  const OtherScreen({super.key});

  @override
  State<OtherScreen> createState() => _OtherScreenState();
}

class _OtherScreenState extends State<OtherScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  late TextEditingController _productCtrl;
  late TextEditingController _searchCtrl;

  // Checker state
  bool _checking = false;
  bool _stopRequested = false;
  int _checkedCount = 0;
  int _totalCount = 0;
  String _statusText = '';

  final List<LotteryResultEntry> _results = [];

  // Table filter / sort state
  String? _filterResult; // null = all, '当選', '落選', 'エラー'
  bool _sortWonFirst = false;

  // WebView
  WebViewController? _wv;
  String _wvUrl = '';
  Completer<void>? _pageLoadCompleter;
  Completer<List<dynamic>>? _extractCompleter;

  static const _extractJs = '''
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
    var won      = li.querySelector('.checkedTxt');
    var lost     = li.querySelector('.endTxt');
    items.push({
      title:  ttlEl.textContent.trim(),
      date:   dateText + ' ' + timeText,
      result: won ? '当選' : (lost ? '落選' : '未定'),
    });
  });
  window.FlutterChannel.postMessage(JSON.stringify({type:'lotteryResults', data:items}));
})();
''';

  static const _loginClickJs = '''
(function() {
  var btn = document.querySelector('a.loginBtn, a.btn.loginBtn');
  if (btn) { btn.click(); return; }
  var all = Array.from(document.querySelectorAll('button,input[type="submit"],a[role="button"],a.btn'));
  for (var i = 0; i < all.length; i++) {
    var t = (all[i].textContent || all[i].value || '').trim();
    if (t.indexOf('ログイン') >= 0 || t.indexOf('送信') >= 0 ||
        t.toLowerCase().indexOf('login') >= 0 || t.toLowerCase().indexOf('sign in') >= 0) {
      all[i].click(); return;
    }
  }
})();
''';

  // ─── Computed ──────────────────────────────────────────────────────────────

  List<LotteryResultEntry> get _filteredResults {
    var list = _results.where((e) {
      final searchQ = _searchCtrl.text.trim().toLowerCase();
      if (searchQ.isNotEmpty && !e.accountEmail.toLowerCase().contains(searchQ)) {
        return false;
      }
      if (_filterResult != null) {
        if (_filterResult == 'エラー') {
          if (!e.isError) return false;
        } else {
          if (e.result != _filterResult) return false;
        }
      }
      return true;
    }).toList();

    if (_sortWonFirst) {
      list.sort((a, b) {
        if (a.isWon && !b.isWon) return -1;
        if (!a.isWon && b.isWon) return 1;
        return 0;
      });
    }
    return list;
  }

  List<LotteryResultEntry> get _errorResults =>
      _results.where((e) => e.isError).toList();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    final p = context.read<AppProvider>();
    _productCtrl = TextEditingController(text: p.targetProductName);
    _searchCtrl = TextEditingController();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _productCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ─── WebView init ──────────────────────────────────────────────────────────

  void _initWebView() {
    _wv = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          _wvUrl = url;
        },
        onPageFinished: (url) {
          _wvUrl = url;
          if (_pageLoadCompleter?.isCompleted == false) {
            _pageLoadCompleter!.complete();
          }
        },
        onWebResourceError: (_) {
          if (_pageLoadCompleter?.isCompleted == false) {
            _pageLoadCompleter!.complete();
          }
        },
      ))
      ..addJavaScriptChannel('FlutterChannel', onMessageReceived: (msg) {
        _handleJs(msg.message);
      });
  }

  void _handleJs(String message) {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      if (data['type'] == 'lotteryResults') {
        final items = (data['data'] as List?) ?? [];
        if (_extractCompleter?.isCompleted == false) {
          _extractCompleter!.complete(items);
        }
      }
    } catch (_) {}
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _loadPage(String url) async {
    _pageLoadCompleter = Completer<void>();
    await _wv!.loadRequest(Uri.parse(url));
    try {
      await _pageLoadCompleter!.future.timeout(const Duration(seconds: 20));
    } catch (_) {}
  }

  Future<bool> _waitForUrlChange(
      {required String fromContains,
      Duration timeout = const Duration(seconds: 25)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!mounted || _stopRequested) return false;
      if (!_wvUrl.contains(fromContains)) return true;
      await Future.delayed(const Duration(milliseconds: 400));
    }
    return false;
  }

  LotteryResultEntry _errEntry(String email, String keyword, String reason) =>
      LotteryResultEntry(
        accountEmail: email,
        productTitle: keyword,
        time: '',
        result: reason,
      );

  void _snack(String msg, {Duration duration = const Duration(seconds: 2)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: duration));
  }

  // ─── Checking logic ────────────────────────────────────────────────────────

  Future<void> _startChecking({List<Account>? overrideAccounts}) async {
    final p = context.read<AppProvider>();
    final keyword = _productCtrl.text.trim();
    await p.setTargetProductName(keyword);

    final accounts = overrideAccounts ??
        p.accounts.where((a) => a.status == 'todo').toList();

    if (accounts.isEmpty) {
      if (!mounted) return;
      _snack('Không có account nào để check');
      return;
    }

    _initWebView();

    setState(() {
      _checking = true;
      _stopRequested = false;
      if (overrideAccounts == null) _results.clear();
      _checkedCount = 0;
      _totalCount = accounts.length;
      _statusText = 'Bắt đầu...';
    });

    for (final account in accounts) {
      if (_stopRequested || !mounted) break;

      setState(() {
        _statusText = 'Đang check: ${account.email}';
      });

      LotteryResultEntry entry;
      try {
        entry = await _checkAccount(account, p, keyword)
            .timeout(const Duration(seconds: 90));
      } on TimeoutException {
        entry = _errEntry(account.email, keyword, 'Timeout');
      } catch (_) {
        entry = _errEntry(account.email, keyword, 'エラー');
      }

      if (mounted) {
        setState(() {
          // Replace existing entry for this email if re-checking
          if (overrideAccounts != null) {
            final idx =
                _results.indexWhere((r) => r.accountEmail == account.email);
            if (idx >= 0) {
              _results[idx] = entry;
            } else {
              _results.add(entry);
            }
          } else {
            _results.add(entry);
          }
          _checkedCount++;
        });
      }
    }

    if (mounted) {
      setState(() {
        _checking = false;
        _statusText = '完了 $_checkedCount/${accounts.length}';
      });
    }
  }

  Future<void> _recheckFailed() async {
    final p = context.read<AppProvider>();
    final errorEmails = _errorResults.map((e) => e.accountEmail).toSet();
    final accounts = p.accounts
        .where((a) => errorEmails.contains(a.email))
        .toList();
    await _startChecking(overrideAccounts: accounts);
  }

  Future<LotteryResultEntry> _checkAccount(
      Account account, AppProvider p, String keyword) async {
    final loginUrl = p.loginUrl;
    final historyUrl = p.lotteryResultUrl;

    setState(() => _statusText = '${account.email}\nLogin page...');
    await _loadPage(loginUrl);
    await Future.delayed(const Duration(milliseconds: 600));

    setState(() => _statusText = '${account.email}\nĐiền email/password...');
    await _wv!.runJavaScript(buildAutoFillScript(account.email, account.password));
    await Future.delayed(const Duration(milliseconds: 800));

    await _wv!.runJavaScript(_loginClickJs);

    setState(() => _statusText = '${account.email}\nĐăng nhập...');
    final loginOk = await _waitForUrlChange(fromContains: '/login');
    if (!loginOk) return _errEntry(account.email, keyword, 'ログイン失敗');

    await Future.delayed(const Duration(milliseconds: 500));

    setState(() => _statusText = '${account.email}\nLottery history...');
    await _loadPage(historyUrl);
    await Future.delayed(const Duration(milliseconds: 600));

    if (_wvUrl.contains('/login')) {
      return _errEntry(account.email, keyword, 'ログイン失敗');
    }

    setState(() => _statusText = '${account.email}\nExtracting...');
    _extractCompleter = Completer<List<dynamic>>();
    await _wv!.runJavaScript(_extractJs);

    List<dynamic> items;
    try {
      items = await _extractCompleter!.future
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return _errEntry(account.email, keyword, 'Extract失敗');
    }

    if (items.isEmpty) {
      return _errEntry(account.email, keyword, '結果なし');
    }

    final kw = keyword.toLowerCase();
    for (final item in items) {
      final title = ((item['title'] as String?) ?? '').toLowerCase();
      if (kw.isEmpty || title.contains(kw)) {
        return LotteryResultEntry(
          accountEmail: account.email,
          productTitle: item['title'] as String? ?? '',
          time: item['date'] as String? ?? '',
          result: item['result'] as String? ?? '未定',
        );
      }
    }

    return _errEntry(account.email, keyword, '対象なし');
  }

  // ─── CSV / Export ──────────────────────────────────────────────────────────

  String _buildCsv(List<LotteryResultEntry> rows) {
    final lines = ['Email,Hàng,Thời gian,Kết quả'];
    for (final r in rows) {
      lines.add('"${r.accountEmail}","${r.productTitle}","${r.time}","${r.result}"');
    }
    return lines.join('\n');
  }

  void _copyResultsCsv() {
    final csv = _buildCsv(_filteredResults);
    Clipboard.setData(ClipboardData(text: csv));
    _snack('Đã copy ${_filteredResults.length} dòng CSV');
  }

  Future<void> _exportCsvFile() async {
    final csv = _buildCsv(_filteredResults);
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 19);
    final file = File('${Directory.systemTemp.path}/lottery_results_$ts.csv');
    await file.writeAsString(csv);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Lottery Results $ts',
    );
  }

  void _copyWonEmails() {
    final won = _filteredResults.where((r) => r.isWon).map((r) => r.accountEmail).join('\n');
    if (won.isEmpty) {
      _snack('Không có 当選 trong danh sách hiện tại');
      return;
    }
    Clipboard.setData(ClipboardData(text: won));
    _snack('Đã copy email 当選');
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceVariant,
        title: const Text('Other'),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.primary,
          labelColor: Colors.white,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: 'Lottery Result'),
            Tab(text: 'Order Status'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildLotteryResultTab(),
          _buildOrderStatusTab(),
        ],
      ),
    );
  }

  Widget _buildLotteryResultTab() {
    if (_checking && _wv != null) {
      return Stack(
        children: [
          WebViewWidget(controller: _wv!),
          Container(
            color: Colors.black.withAlpha(200),
            child: SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '$_checkedCount / $_totalCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _statusText,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_results.isNotEmpty) ...[
                    const Text(
                      'Kết quả đến hiện tại:',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _results.length,
                        itemBuilder: (_, i) =>
                            _buildCompactResultRow(_results[i]),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () =>
                        setState(() => _stopRequested = true),
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('Dừng'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSettingsCard(),
          const SizedBox(height: 16),
          if (_results.isNotEmpty) _buildResultsSection(),
        ],
      ),
    );
  }

  Widget _buildSettingsCard() {
    final p = context.watch<AppProvider>();
    final todoCount = p.accounts.where((a) => a.status == 'todo').length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Lọc kết quả Lottery',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _productCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Tên hàng (keyword)',
                hintText: 'VD: アビスアイ, MEGA拡張',
                hintStyle: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.textSecondary, size: 18),
                suffixIcon: _productCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            color: AppColors.textSecondary, size: 16),
                        onPressed: () =>
                            setState(() => _productCtrl.clear()),
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Text(
              'URL: ${p.lotteryResultUrl}',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _checking ? null : _startChecking,
                    icon: const Icon(Icons.play_circle_outline, size: 18),
                    label: Text('Check $todoCount accounts (TODO)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ),
                if (_errorResults.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Re-check ${_errorResults.length} lỗi',
                    child: ElevatedButton(
                      onPressed: _checking ? null : _recheckFailed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.warning,
                        minimumSize: const Size(48, 48),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Icon(Icons.refresh, size: 20),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Results section (filter bar + table) ─────────────────────────────────

  Widget _buildResultsSection() {
    final filtered = _filteredResults;
    final wonCount = _results.where((r) => r.isWon).length;
    final lostCount = _results.where((r) => r.isLost).length;
    final errCount = _errorResults.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Summary row ──
        Row(
          children: [
            Text(
              filtered.length == _results.length
                  ? '${_results.length} kết quả'
                  : '${filtered.length} / ${_results.length}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 10),
            _chip('当選 $wonCount', AppColors.done),
            const SizedBox(width: 5),
            _chip('落選 $lostCount', AppColors.error),
            if (errCount > 0) ...[
              const SizedBox(width: 5),
              _chip('エラー $errCount', AppColors.warning),
            ],
            const Spacer(),
            // Sort toggle
            Tooltip(
              message: _sortWonFirst ? 'Đang sort: 当選 trên' : 'Sort 当選 lên trên',
              child: IconButton(
                icon: Icon(
                  Icons.sort,
                  color: _sortWonFirst
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _sortWonFirst = !_sortWonFirst),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── Search by email ──
        TextField(
          controller: _searchCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Tìm theo email...',
            hintStyle:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            prefixIcon: const Icon(Icons.search,
                color: AppColors.textSecondary, size: 18),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear,
                        color: AppColors.textSecondary, size: 16),
                    onPressed: () => _searchCtrl.clear(),
                  )
                : null,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
        const SizedBox(height: 8),

        // ── Filter chips ──
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip('Tất cả', null),
              const SizedBox(width: 6),
              _filterChip('当選', '当選'),
              const SizedBox(width: 6),
              _filterChip('落選', '落選'),
              const SizedBox(width: 6),
              _filterChip('エラー', 'エラー'),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ── Action buttons ──
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.copy_all,
                  color: AppColors.textSecondary, size: 20),
              tooltip: 'Copy CSV (filtered)',
              onPressed: _copyResultsCsv,
            ),
            IconButton(
              icon: const Icon(Icons.ios_share,
                  color: AppColors.textSecondary, size: 20),
              tooltip: 'Export file CSV',
              onPressed: _exportCsvFile,
            ),
            if (filtered.any((r) => r.isWon))
              IconButton(
                icon: const Icon(Icons.emoji_events,
                    color: AppColors.done, size: 20),
                tooltip: 'Copy email 当選',
                onPressed: _copyWonEmails,
              ),
            if (_results.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.error, size: 20),
                tooltip: 'Xóa tất cả',
                onPressed: () => setState(() {
                  _results.clear();
                  _filterResult = null;
                  _searchCtrl.clear();
                }),
              ),
          ],
        ),
        const SizedBox(height: 6),

        // ── Table ──
        _buildTable(filtered),
      ],
    );
  }

  Widget _filterChip(String label, String? value) {
    final selected = _filterResult == value;
    Color color;
    if (value == '当選') {
      color = AppColors.done;
    } else if (value == '落選') {
      color = AppColors.error;
    } else if (value == 'エラー') {
      color = AppColors.warning;
    } else {
      color = AppColors.primary;
    }

    return GestureDetector(
      onTap: () => setState(() => _filterResult = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(50) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : AppColors.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildTable(List<LotteryResultEntry> rows) {
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.divider),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'Không có kết quả',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: const Row(
            children: [
              Expanded(
                  flex: 3,
                  child: Text('Email',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold))),
              Expanded(
                  flex: 3,
                  child: Text('Hàng',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold))),
              Expanded(
                  flex: 2,
                  child: Text('Thời gian',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold))),
              SizedBox(
                  width: 64,
                  child: Text('Kết quả',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center)),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(8)),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rows.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppColors.divider),
            itemBuilder: (_, i) => _buildResultRow(rows[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildResultRow(LotteryResultEntry e) {
    Color resultColor;
    if (e.isWon) {
      resultColor = AppColors.done;
    } else if (e.isLost) {
      resultColor = AppColors.error;
    } else if (e.isError) {
      resultColor = AppColors.warning;
    } else {
      resultColor = AppColors.textSecondary;
    }

    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(
            text:
                '${e.accountEmail},${e.productTitle},${e.time},${e.result}'));
        _snack('Copied row', duration: const Duration(seconds: 1));
      },
      child: Container(
        color: e.isWon ? AppColors.done.withAlpha(15) : Colors.transparent,
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                e.accountEmail,
                style:
                    const TextStyle(color: Colors.white, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                e.productTitle.isEmpty ? '—' : e.productTitle,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                e.time.isEmpty ? '—' : e.time,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 64,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: resultColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: resultColor.withAlpha(120)),
                ),
                child: Text(
                  e.result,
                  style: TextStyle(
                    color: resultColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactResultRow(LotteryResultEntry e) {
    final c = e.isWon
        ? AppColors.done
        : e.isLost
            ? AppColors.error
            : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              e.accountEmail,
              style:
                  const TextStyle(color: Colors.white, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(e.result,
              style: TextStyle(
                  color: c,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withAlpha(120)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold)),
      );

  Widget _buildOrderStatusTab() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 56, color: AppColors.textSecondary),
          SizedBox(height: 12),
          Text('Order Status',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          SizedBox(height: 6),
          Text('Coming soon...',
              style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
