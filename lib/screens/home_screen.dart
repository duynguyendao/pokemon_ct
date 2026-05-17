import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:io';
import '../models/account.dart';
import '../models/result_snapshot.dart';
import '../models/start_all_report.dart';
import '../providers/app_provider.dart';
import '../services/discord_service.dart';
import '../services/shortcut_service.dart';
import '../utils/app_theme.dart';
import '../widgets/account_card.dart';
import '../widgets/summary_card.dart';
import 'add_account_screen.dart';
import 'browser_screen.dart';
import 'exitanty_browser_screen.dart';
import 'standalone_browser_screen.dart';
import 'package:share_plus/share_plus.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  String _searchQuery = '';
  String _statusFilter = 'all';
  String? _groupFilter;
  bool _searchVisible = false;
  bool _batchMode = false;
  final Set<String> _selected = {};
  final _searchCtrl = TextEditingController();

  // Start All
  bool _runningAll = false;
  int _runAllIndex = 0;
  List<Account> _runAllList = [];
  bool _stopCurrentRequested = false;
  bool _stopAllRequested = false;
  late StartAllReport _currentReport;

  // Pokeball animation
  late AnimationController _pokeballController;

  @override
  void initState() {
    super.initState();
    _pokeballController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  List<Account> _filtered(AppProvider p) {
    var list = p.accounts;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((a) => a.email.toLowerCase().contains(q)).toList();
    }
    if (_statusFilter != 'all') {
      list = list.where((a) => a.status == _statusFilter).toList();
    }
    if (_groupFilter != null) {
      list = list.where((a) => a.group == _groupFilter).toList();
    }
    return list;
  }

  void _toggleBatch(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        if (_selected.isEmpty) _batchMode = false;
      } else {
        _selected.add(id);
      }
    });
  }

  Future<void> _moveBatchToGroup(AppProvider p) async {
    String? selectedGroup = _groupFilter;
    final result = await showDialog<String?>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx2, setS) => AlertDialog(
          backgroundColor: AppColors.card,
          title: Text(
            'Chuyển ${_selected.length} tài khoản vào nhóm',
            style: const TextStyle(color: Colors.white),
          ),
          content: DropdownButtonFormField<String?>(
            value: selectedGroup,
            dropdownColor: AppColors.surfaceVariant,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(labelText: 'Nhóm'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Không có nhóm')),
              ...p.groups.map(
                (g) => DropdownMenuItem(value: g, child: Text(g)),
              ),
            ],
            onChanged: (v) => setS(() => selectedGroup = v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx2),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx2, selectedGroup ?? '__none__'),
              child: const Text('Chuyển'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final group = result == '__none__' ? null : result;
    for (final id in _selected.toList()) {
      final idx = p.accounts.indexWhere((a) => a.id == id);
      if (idx >= 0)
        await p.updateAccount(p.accounts[idx].copyWith(group: group));
    }
    setState(() {
      _selected.clear();
      _batchMode = false;
    });
  }

  Future<void> _changeBatchMode(AppProvider p) async {
    final mode = await showDialog<AccountMode>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          'Đổi mode cho ${_selected.length} account',
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: AccountMode.values.map((m) => ListTile(
            title: Text(m.label, style: const TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context, m),
          )).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
        ],
      ),
    );
    if (mode == null) return;
    for (final id in _selected.toList()) {
      final idx = p.accounts.indexWhere((a) => a.id == id);
      if (idx >= 0) await p.updateAccount(p.accounts[idx].copyWith(mode: mode));
    }
    setState(() {
      _selected.clear();
      _batchMode = false;
    });
  }

  Future<void> _deleteBatch(AppProvider p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Xóa tài khoản',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Xóa ${_selected.length} tài khoản đã chọn?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await p.deleteAccounts(_selected.toList());
      setState(() {
        _selected.clear();
        _batchMode = false;
      });
    }
  }

  Future<void> _openAccount(Account account, AppProvider p, {int? index, int? total}) async {
    // Copy email vào clipboard để Shortcut dùng lọc OTP đúng account
    await Clipboard.setData(ClipboardData(text: account.email));

    if (p.shortcut5gEnabled) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.card,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(color: AppColors.accent),
                ),
                const SizedBox(height: 16),
                const Text(
                  '⚡ Chạy 5G Shortcut...',
                  style: TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  account.mode == AccountMode.loginOnly
                      ? 'Login'
                      : account.mode == AccountMode.lottery
                      ? 'Lottery'
                      : 'Lottery Result',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      await ShortcutService.triggerShortcut('5G');
      await Future.delayed(const Duration(seconds: 5));
      if (mounted) Navigator.pop(context);
    }

    if (mounted) {

      // LUÔN start tại loginUrl (mọi mode). Sau khi login + OTP thành công,
      // browser_screen tự navigate đến URL mode-specific (lotteryUrl /
      // lotteryResultUrl / orderHistoryUrl) qua _pending*Navigation flags.
      //
      // Lý do: trang lottery/order-history protected bởi Akamai WAF, navigate
      // trực tiếp khi chưa có session sẽ bị Access Denied. Đi qua login trước
      // tạo session cookie + referer hợp lệ.
      final String startUrl = p.loginUrl;

      if (p.useExitanty) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ExitAntyBrowserScreen(
              account: account,
              startUrl: startUrl,
              isRunningAll: _runningAll,
              accountIndex: index,
              totalAccounts: total,
              onStopAll: _runningAll
                  ? () {
                      setState(() => _stopAllRequested = true);
                      Navigator.pop(context);
                    }
                  : null,
              onSkipCurrent: _runningAll
                  ? () {
                      setState(() => _stopCurrentRequested = true);
                      Navigator.pop(context);
                    }
                  : null,
            ),
          ),
        );
        return;
      }

      final proxy = p.proxyEnabled
          ? p.getProxyById(account.proxyId) ?? p.nextProxy
          : null;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BrowserScreen(
            account: account,
            proxy: proxy,
            startUrl: startUrl,
            isRunningAll: _runningAll,
            accountIndex: index,
            totalAccounts: total,
            onStopAll: _runningAll
                ? () {
                    setState(() => _stopAllRequested = true);
                    Navigator.pop(context);
                  }
                : null,
            onSkipCurrent: _runningAll
                ? () {
                    setState(() => _stopCurrentRequested = true);
                    Navigator.pop(context);
                  }
                : null,
          ),
        ),
      );

      // Auto-mark done for task-completion modes (lottery apply / lotteryResult / orderStatus)
      if (mounted &&
          (account.mode == AccountMode.lottery ||
              account.mode == AccountMode.lotteryResult ||
              account.mode == AccountMode.orderStatus)) {
        final current = p.accounts.firstWhere(
          (a) => a.id == account.id,
          orElse: () => account,
        );
        if (current.status == 'todo') {
          await p.toggleStatus(account.id);
        }
      }
    }
  }

  Future<void> _runAllAccounts(AppProvider p) async {
    final list = _filtered(p).where((a) => a.status == 'todo').toList();
    if (list.isEmpty) return;

    _currentReport = StartAllReport(startTime: DateTime.now(), results: []);
    _stopCurrentRequested = false;
    _stopAllRequested = false;

    setState(() {
      _runningAll = true;
      _runAllIndex = 0;
      _runAllList = list;
    });

    for (var i = 0; i < list.length; i++) {
      if (_stopAllRequested || !mounted) break;
      if (_stopCurrentRequested) {
        _currentReport.results.add(
          StartAllResult(
            accountEmail: list[i].email,
            success: false,
            error: 'Stopped by user',
            startTime: DateTime.now(),
            endTime: DateTime.now(),
            status: 'stopped',
          ),
        );
        _stopCurrentRequested = false;
        continue;
      }

      setState(() => _runAllIndex = i);
      final startTime = DateTime.now();
      try {
        await _openAccount(list[i], p, index: i + 1, total: list.length);
        _currentReport.results.add(
          StartAllResult(
            accountEmail: list[i].email,
            success: true,
            startTime: startTime,
            endTime: DateTime.now(),
            status: 'success',
          ),
        );
      } catch (e) {
        _currentReport.results.add(
          StartAllResult(
            accountEmail: list[i].email,
            success: false,
            error: e.toString(),
            startTime: startTime,
            endTime: DateTime.now(),
            status: 'error',
          ),
        );
      }
      if (!mounted) break;
    }

    if (mounted) {
      _currentReport = StartAllReport(
        startTime: _currentReport.startTime,
        endTime: DateTime.now(),
        results: _currentReport.results,
      );
      setState(() => _runningAll = false);
      // Auto-save snapshots for any result type that has data
      await p.saveSnapshotFromCurrentResults(SnapshotType.lottery);
      await p.saveSnapshotFromCurrentResults(SnapshotType.lotteryApply);
      await p.saveSnapshotFromCurrentResults(SnapshotType.order);
      await p.saveSnapshotFromCurrentResults(SnapshotType.shipping);
      _showStartAllReport();
    }
  }

  void _showStartAllReport() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Start All Report',
          style: TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '✅ Success: ${_currentReport.successCount}',
                style: const TextStyle(
                  color: AppColors.done,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '❌ Error: ${_currentReport.errorCount}',
                style: const TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '⏸️ Stopped: ${_currentReport.stoppedCount}',
                style: const TextStyle(
                  color: AppColors.warning,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Divider(color: AppColors.divider),
              const SizedBox(height: 8),
              ..._currentReport.results.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${r.accountEmail}: ${r.status}${r.error != null ? " (${r.error})" : ""}',
                    style: TextStyle(
                      color: r.status == 'success'
                          ? AppColors.done
                          : AppColors.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _shareReportFile('txt'),
            child: const Text('Share TXT'),
          ),
          TextButton(
            onPressed: () => _shareReportFile('csv'),
            child: const Text('Share CSV'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareReportFile(String format) async {
    final isCsv = format == 'csv';
    final content = isCsv ? _currentReport.toCsv() : _currentReport.toTxt();
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
    final ext = isCsv ? 'csv' : 'txt';
    final mime = isCsv ? 'text/csv; charset=utf-8' : 'text/plain; charset=utf-8';
    final file = File('${Directory.systemTemp.path}/start_all_report_$ts.$ext');
    final bom = isCsv ? [0xEF, 0xBB, 0xBF] : <int>[];
    await file.writeAsBytes([...bom, ...utf8.encode(content)]);
    await Share.shareXFiles([XFile(file.path, mimeType: mime)]);
  }

  void _showGlobalModeDialog(BuildContext ctx, AppProvider p) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Set global mode cho tất cả account',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Chọn mode sẽ áp dụng cho toàn bộ tài khoản:',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          ...AccountMode.values.map(
            (mode) => ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
              ),
              onPressed: () {
                p.setAllAccountsMode(mode);
                Navigator.pop(ctx);
              },
              child: Text(mode.label),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext ctx, Account account, AppProvider p) {
    final emailCtrl = TextEditingController(text: account.email);
    final passCtrl = TextEditingController(text: account.password);
    String? selectedGroup = account.group;
    AccountMode selectedMode = account.mode;

    showDialog(
      context: ctx,
      builder: (_) => StatefulBuilder(
        builder: (ctx2, setS) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text(
            'Chỉnh sửa tài khoản',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Mật khẩu'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: selectedGroup,
                  dropdownColor: AppColors.surfaceVariant,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Nhóm'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Không có nhóm'),
                    ),
                    ...p.groups.map(
                      (g) => DropdownMenuItem(value: g, child: Text(g)),
                    ),
                  ],
                  onChanged: (v) => setS(() => selectedGroup = v),
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Chế độ mở',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                ...AccountMode.values.map(
                  (mode) => RadioListTile<AccountMode>(
                    value: mode,
                    groupValue: selectedMode,
                    onChanged: (v) => setS(() => selectedMode = v!),
                    title: Text(
                      mode.label,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    activeColor: AppColors.primary,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx2),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () {
                p.updateAccount(
                  account.copyWith(
                    email: emailCtrl.text.trim(),
                    password: passCtrl.text.trim(),
                    group: selectedGroup,
                    mode: selectedMode,
                  ),
                );
                Navigator.pop(ctx2);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }

  void _showGroupManager(BuildContext ctx, AppProvider p) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: ctx,
      backgroundColor: AppColors.surfaceVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx2, setS) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Quản lý nhóm',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Tên nhóm mới',
                        hintStyle: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      if (ctrl.text.trim().isNotEmpty) {
                        p.addGroup(ctrl.text.trim());
                        ctrl.clear();
                        setS(() {});
                      }
                    },
                    child: const Text('Thêm'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...p.groups.map(
                (g) => ListTile(
                  title: Text(g, style: const TextStyle(color: Colors.white)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: AppColors.error),
                    onPressed: () {
                      p.deleteGroup(g);
                      setS(() {});
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettingsMenu(BuildContext ctx, AppProvider p) {
    final pwCtrl = TextEditingController(text: p.defaultPassword);
    final discordCtrl = TextEditingController(text: p.discordWebhookUrl);
    final exitantyPortCtrl = TextEditingController(text: p.exitantyPort.toString());
    final exitantyTokenCtrl = TextEditingController(text: p.exitantyToken);
    showModalBottomSheet(
      context: ctx,
      backgroundColor: AppColors.surfaceVariant,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Consumer<AppProvider>(
        builder: (_, prov, __) => SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Cài đặt',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: prov.proxyEnabled,
                onChanged: prov.setProxyEnabled,
                title: const Text(
                  'Bật Proxy',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Tự động dùng proxy khi mở tài khoản',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                activeThumbColor: AppColors.secondary,
              ),
              SwitchListTile(
                value: prov.fakeBrowser,
                onChanged: prov.setFakeBrowser,
                title: const Text(
                  'Giả mạo trình duyệt',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Inject anti-fingerprint + block WebRTC',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                activeThumbColor: AppColors.secondary,
              ),
              SwitchListTile(
                value: prov.fingerprintSeedMode,
                onChanged: prov.fakeBrowser ? prov.setFingerprintSeedMode : null,
                title: Text(
                  'Fingerprint cố định theo account',
                  style: TextStyle(
                    color: prov.fakeBrowser ? Colors.white : AppColors.textSecondary,
                  ),
                ),
                subtitle: Text(
                  prov.fakeBrowser
                      ? 'Mỗi account có fingerprint riêng nhất quán — tắt = random mỗi session'
                      : 'Cần bật "Giả mạo trình duyệt" trước',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                activeThumbColor: AppColors.secondary,
              ),
              SwitchListTile(
                value: prov.incognitoMode,
                onChanged: prov.setIncognitoMode,
                title: const Text(
                  'Chế độ ẩn danh',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Xóa cookies/cache mỗi lần mở tài khoản',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                activeThumbColor: AppColors.secondary,
              ),
              SwitchListTile(
                value: prov.blockImages,
                onChanged: prov.setBlockImages,
                title: const Text(
                  'Ẩn hình ảnh',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Tắt ảnh trong webview để tải nhanh hơn',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                activeThumbColor: AppColors.secondary,
              ),
              SwitchListTile(
                value: prov.shortcut5gEnabled,
                onChanged: prov.setShortcut5gEnabled,
                title: const Text(
                  'Shortcut 5G/WiFi',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Tắt 5G → Bật 5G → Open App trước mỗi account',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                activeThumbColor: AppColors.accent,
                secondary: prov.shortcut5gEnabled
                    ? ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow, size: 14),
                        label:
                            const Text('Chạy', style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          minimumSize: Size.zero,
                        ),
                        onPressed: () async {
                          final ok =
                              await ShortcutService.triggerShortcut('5G');
                          if (!ok && ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Shortcut "5G" không tìm thấy'),
                                backgroundColor: AppColors.error,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      )
                    : null,
              ),
              const Divider(height: 1),
              const SizedBox(height: 8),
              const Text(
                'Tốc độ nhập (ms/ký tự)',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              Row(
                children: [
                  const Text('Min', style: TextStyle(color: Colors.white, fontSize: 13)),
                  Expanded(
                    child: Slider(
                      value: prov.typingMinDelay.toDouble(),
                      min: 30, max: 300, divisions: 27,
                      label: '${prov.typingMinDelay}ms',
                      activeColor: AppColors.secondary,
                      onChanged: (v) => prov.setTypingMinDelay(v.round()),
                    ),
                  ),
                  Text('${prov.typingMinDelay}ms', style: const TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
              Row(
                children: [
                  const Text('Max', style: TextStyle(color: Colors.white, fontSize: 13)),
                  Expanded(
                    child: Slider(
                      value: prov.typingMaxDelay.toDouble(),
                      min: 30, max: 500, divisions: 47,
                      label: '${prov.typingMaxDelay}ms',
                      activeColor: AppColors.secondary,
                      onChanged: (v) => prov.setTypingMaxDelay(v.round()),
                    ),
                  ),
                  Text('${prov.typingMaxDelay}ms', style: const TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
              Row(
                children: [
                  const Text('OTP watchdog', style: TextStyle(color: Colors.white, fontSize: 13)),
                  Expanded(
                    child: Slider(
                      value: prov.otpWatchdogSeconds.toDouble(),
                      min: 10, max: 300, divisions: 29,
                      label: '${prov.otpWatchdogSeconds}s',
                      activeColor: AppColors.accent,
                      onChanged: (v) => prov.setOtpWatchdogSeconds(v.round()),
                    ),
                  ),
                  Text('${prov.otpWatchdogSeconds}s', style: const TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.travel_explore,
                  color: AppColors.accent,
                ),
                title: const Text(
                  'Mở trình duyệt độc lập',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Check fingerprint, proxy, lướt web tự do',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.push(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => const StandaloneBrowserScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              const SizedBox(height: 12),
              TextField(
                controller: discordCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Discord Webhook URL',
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  hintText: 'https://discord.com/api/webhooks/...',
                  hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (discordCtrl.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.send, color: AppColors.secondary, size: 18),
                          tooltip: 'Test thử',
                          onPressed: () async {
                            await DiscordService.sendLotterySuccess(
                              webhookUrl: discordCtrl.text.trim(),
                              email: 'test@example.com',
                              productTitle: 'Test sản phẩm — PokemonCT',
                            );
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                                content: Text('Đã gửi test notification'),
                                duration: Duration(seconds: 2),
                              ));
                            }
                          },
                        ),
                      const Icon(Icons.notifications_active_outlined,
                          color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
                onChanged: (v) => prov.setDiscordWebhookUrl(v.trim()),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              // ── Automation engine ──
              Row(
                children: [
                  const Icon(Icons.smart_toy_outlined, color: AppColors.accent, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Automation Engine',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                  ),
                  SegmentedButton<String>(
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: AppColors.secondary,
                      selectedForegroundColor: Colors.white,
                      foregroundColor: AppColors.textSecondary,
                      textStyle: const TextStyle(fontSize: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    segments: const [
                      ButtonSegment(value: 'webview', label: Text('WebView')),
                      ButtonSegment(value: 'exitanty', label: Text('ExitAnty')),
                    ],
                    selected: {prov.automationEngine},
                    onSelectionChanged: (s) => prov.setAutomationEngine(s.first),
                  ),
                ],
              ),
              if (prov.automationEngine == 'exitanty') ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: exitantyPortCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          labelStyle: TextStyle(color: AppColors.textSecondary),
                          hintText: '9519',
                          hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                        onChanged: (v) {
                          final port = int.tryParse(v.trim());
                          if (port != null) prov.setExitantyPort(port);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 5,
                      child: TextField(
                        controller: exitantyTokenCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          labelText: 'Token (nếu có)',
                          labelStyle: TextStyle(color: AppColors.textSecondary),
                          hintText: 'Bearer token...',
                          hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                        onChanged: (v) => prov.setExitantyToken(v.trim()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'ExitAnty phải đang chạy trên thiết bị này. '
                  'App sẽ gửi lệnh qua WebDriver HTTP đến localhost:${prov.exitantyPort}.',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: pwCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Mật khẩu mặc định',
                  suffixIcon: Icon(
                    Icons.lock_outline,
                    color: AppColors.textSecondary,
                  ),
                ),
                onChanged: prov.setDefaultPassword,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pokeballController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final filtered = _filtered(p);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceVariant,
        title: _searchVisible
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'Tìm email...',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  border: InputBorder.none,
                  filled: false,
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : Row(
                children: [
                  AnimatedBuilder(
                    animation: _pokeballController,
                    builder: (_, __) => Transform.rotate(
                      angle: _pokeballController.value * 6.28,
                      child: const Text('🎡', style: TextStyle(fontSize: 22)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'PokemonCT',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'Account Manager',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
        actions: [
          if (_runningAll) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  '${_runAllIndex + 1}/${_runAllList.length}',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                ),
                onPressed: () => setState(() => _stopCurrentRequested = true),
                icon: const Icon(Icons.skip_next, size: 18),
                label: const Text('Skip', style: TextStyle(fontSize: 12)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                ),
                onPressed: () => setState(() => _stopAllRequested = true),
                icon: const Icon(Icons.stop, size: 18),
                label: const Text('Stop', style: TextStyle(fontSize: 12)),
              ),
            ),
          ] else if (_batchMode) ...[
            Text(
              '${_selected.length} đã chọn',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            IconButton(
              icon: Icon(
                _selected.length == filtered.length && filtered.isNotEmpty
                    ? Icons.deselect
                    : Icons.select_all,
                color: AppColors.accent,
              ),
              tooltip: _selected.length == filtered.length && filtered.isNotEmpty
                  ? 'Bỏ chọn tất cả'
                  : 'Chọn tất cả (đang lọc)',
              onPressed: () {
                setState(() {
                  final ids = filtered.map((a) => a.id).toSet();
                  if (_selected.containsAll(ids) && ids.isNotEmpty) {
                    // All filtered are selected → deselect them
                    _selected.removeAll(ids);
                  } else {
                    _selected.addAll(ids);
                  }
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.check_circle_outline, color: AppColors.done),
              tooltip: 'Đánh dấu Xong',
              onPressed: _selected.isEmpty
                  ? null
                  : () async {
                      await p.batchSetStatus(_selected.toList(), 'done');
                      setState(() {
                        _selected.clear();
                        _batchMode = false;
                      });
                    },
            ),
            IconButton(
              icon: const Icon(Icons.radio_button_unchecked, color: AppColors.todo),
              tooltip: 'Đánh dấu Chờ',
              onPressed: _selected.isEmpty
                  ? null
                  : () async {
                      await p.batchSetStatus(_selected.toList(), 'todo');
                      setState(() {
                        _selected.clear();
                        _batchMode = false;
                      });
                    },
            ),
            IconButton(
              icon: const Icon(Icons.drive_file_move_outlined),
              tooltip: 'Chuyển nhóm',
              onPressed: _selected.isEmpty ? null : () => _moveBatchToGroup(p),
            ),
            IconButton(
              icon: const Icon(Icons.tune, color: AppColors.secondary),
              tooltip: 'Đổi mode',
              onPressed: _selected.isEmpty ? null : () => _changeBatchMode(p),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: AppColors.error),
              onPressed: () => _deleteBatch(p),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _batchMode = false;
                _selected.clear();
              }),
            ),
          ] else ...[
            IconButton(
              icon: Icon(_searchVisible ? Icons.close : Icons.search),
              tooltip: _searchVisible ? 'Đóng tìm' : 'Tìm kiếm',
              onPressed: () => setState(() {
                _searchVisible = !_searchVisible;
                if (!_searchVisible) {
                  _searchQuery = '';
                  _searchCtrl.clear();
                }
              }),
            ),
            if (!_searchVisible) ...[
              IconButton(
                icon: const Icon(Icons.select_all, color: AppColors.accent),
                tooltip: 'Chọn tất cả',
                onPressed: filtered.isEmpty
                    ? null
                    : () => setState(() {
                          _batchMode = true;
                          _selected.addAll(filtered.map((a) => a.id));
                        }),
              ),
              IconButton(
                icon: const Icon(Icons.play_circle_outline, color: AppColors.done),
                tooltip: 'Start All (TODO)',
                onPressed: () => _runAllAccounts(p),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                color: AppColors.surfaceVariant,
                onSelected: (v) {
                  switch (v) {
                    case 'mode':
                      _showGlobalModeDialog(context, p);
                      break;
                    case 'browser':
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const StandaloneBrowserScreen()));
                      break;
                    case 'groups':
                      _showGroupManager(context, p);
                      break;
                    case 'settings':
                      _showSettingsMenu(context, p);
                      break;
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'mode',
                    child: Row(children: [
                      Icon(Icons.tune, color: AppColors.secondary, size: 18),
                      SizedBox(width: 10),
                      Text('Set global mode', style: TextStyle(color: Colors.white)),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'browser',
                    child: Row(children: [
                      Icon(Icons.travel_explore, color: AppColors.accent, size: 18),
                      SizedBox(width: 10),
                      Text('Trình duyệt độc lập', style: TextStyle(color: Colors.white)),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'groups',
                    child: Row(children: [
                      Icon(Icons.group, size: 18, color: Colors.white),
                      SizedBox(width: 10),
                      Text('Quản lý nhóm', style: TextStyle(color: Colors.white)),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'settings',
                    child: Row(children: [
                      Icon(Icons.settings, size: 18, color: Colors.white),
                      SizedBox(width: 10),
                      Text('Cài đặt', style: TextStyle(color: Colors.white)),
                    ]),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
      body: Column(
        children: [
          // Summary Row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: SummaryCard(
                    label: '⏳ Chờ',
                    value: p.todoCount,
                    color: AppColors.todo,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SummaryCard(
                    label: '✅ Xong',
                    value: p.doneCount,
                    color: AppColors.done,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SummaryCard(
                    label: '📊 Tổng',
                    value: p.accounts.length,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SummaryCard(
                    label: '🔐 Proxy',
                    value: p.proxies.length,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ),

          // Status Filter
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                for (final s in ['all', 'todo', 'done'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        s == 'all'
                            ? 'Tất cả'
                            : s == 'todo'
                            ? 'Chờ'
                            : 'Xong',
                      ),
                      selected: _statusFilter == s,
                      onSelected: (_) => setState(() => _statusFilter = s),
                    ),
                  ),
                if (p.groups.isNotEmpty) ...[
                  const VerticalDivider(color: AppColors.divider, width: 16),
                  ChoiceChip(
                    label: const Text('Tất cả nhóm'),
                    selected: _groupFilter == null,
                    onSelected: (_) => setState(() => _groupFilter = null),
                  ),
                  const SizedBox(width: 6),
                  ...p.groups.map(
                    (g) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(g),
                        selected: _groupFilter == g,
                        onSelected: (_) => setState(() => _groupFilter = g),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const Divider(height: 1),

          // Account List
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.catching_pokemon,
                          size: 64,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          p.accounts.isEmpty
                              ? 'Chưa có tài khoản nào'
                              : 'Không tìm thấy tài khoản',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80, top: 4),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final account = filtered[i];
                      return AccountCard(
                        account: account,
                        proxy: p.getProxyById(account.proxyId),
                        isSelected: _selected.contains(account.id),
                        batchMode: _batchMode,
                        onTap: () {
                          if (_batchMode) {
                            _toggleBatch(account.id);
                          } else {
                            _openAccount(account, p);
                          }
                        },
                        onLongPress: () {
                          setState(() {
                            _batchMode = true;
                            _selected.add(account.id);
                          });
                        },
                        onToggleStatus: () => p.toggleStatus(account.id),
                        onEdit: () => _showEditDialog(context, account, p),
                        onDelete: () => p.deleteAccount(account.id),
                        onModeChange: (mode) =>
                            p.updateAccount(account.copyWith(mode: mode)),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _batchMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddAccountScreen()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Thêm tài khoản'),
            ),
    );
  }
}
