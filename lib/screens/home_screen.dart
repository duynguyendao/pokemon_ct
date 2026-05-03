import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../providers/app_provider.dart';
import '../services/shortcut_service.dart';
import '../utils/app_theme.dart';
import '../widgets/account_card.dart';
import '../widgets/summary_card.dart';
import 'add_account_screen.dart';
import 'browser_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _searchQuery = '';
  String _statusFilter = 'all';
  String? _groupFilter;
  bool _searchVisible = false;
  bool _batchMode = false;
  final Set<String> _selected = {};
  final _searchCtrl = TextEditingController();

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

  Future<void> _deleteBatch(AppProvider p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Xóa tài khoản', style: TextStyle(color: Colors.white)),
        content: Text(
          'Xóa ${_selected.length} tài khoản đã chọn?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
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

  void _openAccount(Account account, AppProvider p) {
    final proxy = p.proxyEnabled ? p.getProxyById(account.proxyId) ?? p.nextProxy : null;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BrowserScreen(account: account, proxy: proxy),
      ),
    );
  }

  void _showEditDialog(BuildContext ctx, Account account, AppProvider p) {
    final emailCtrl = TextEditingController(text: account.email);
    final passCtrl = TextEditingController(text: account.password);
    String? selectedGroup = account.group;

    showDialog(
      context: ctx,
      builder: (_) => StatefulBuilder(
        builder: (ctx2, setS) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Chỉnh sửa tài khoản', style: TextStyle(color: Colors.white)),
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
                    const DropdownMenuItem(value: null, child: Text('Không có nhóm')),
                    ...p.groups.map((g) => DropdownMenuItem(value: g, child: Text(g))),
                  ],
                  onChanged: (v) => setS(() => selectedGroup = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx2), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: () {
                p.updateAccount(account.copyWith(
                  email: emailCtrl.text.trim(),
                  password: passCtrl.text.trim(),
                  group: selectedGroup,
                ));
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
              const Text('Quản lý nhóm',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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
              ...p.groups.map((g) => ListTile(
                    title: Text(g, style: const TextStyle(color: Colors.white)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: AppColors.error),
                      onPressed: () {
                        p.deleteGroup(g);
                        setS(() {});
                      },
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettingsMenu(BuildContext ctx, AppProvider p) {
    final pwCtrl = TextEditingController(text: p.defaultPassword);
    showModalBottomSheet(
      context: ctx,
      backgroundColor: AppColors.surfaceVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cài đặt',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SwitchListTile(
              value: p.proxyEnabled,
              onChanged: p.setProxyEnabled,
              title: const Text('Bật Proxy', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Tự động dùng proxy khi mở tài khoản',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              activeThumbColor: AppColors.secondary,
            ),
            SwitchListTile(
              value: p.fakeBrowser,
              onChanged: p.setFakeBrowser,
              title: const Text('Giả mạo trình duyệt', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Inject anti-fingerprint JavaScript',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              activeThumbColor: AppColors.secondary,
            ),
            ListTile(
              title: const Text('Bật 5G/WiFi Shortcut', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Gọi Shortcut: Tắt 5G → Bật 5G → Open App',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              trailing: ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('Chạy', style: TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                ),
                onPressed: () async {
                  final ok = await ShortcutService.triggerShortcut('5G');
                  if (!ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Shortcut "5G" không tìm thấy'),
                        backgroundColor: AppColors.error,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pwCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Mật khẩu mặc định',
                suffixIcon: Icon(Icons.lock_outline, color: AppColors.textSecondary),
              ),
              onChanged: p.setDefaultPassword,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
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
                  const Text('⚡', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('PokemonCT',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 0.5)),
                      Text('Account Manager',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  ),
                ],
              ),
        actions: [
          if (_batchMode) ...[
            Text('${_selected.length} đã chọn',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
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
              onPressed: () => setState(() {
                _searchVisible = !_searchVisible;
                if (!_searchVisible) {
                  _searchQuery = '';
                  _searchCtrl.clear();
                }
              }),
            ),
            IconButton(
              icon: const Icon(Icons.group),
              onPressed: () => _showGroupManager(context, p),
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => _showSettingsMenu(context, p),
            ),
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
                Expanded(child: SummaryCard(label: '⏳ Chờ', value: p.todoCount, color: AppColors.todo)),
                const SizedBox(width: 10),
                Expanded(child: SummaryCard(label: '✅ Xong', value: p.doneCount, color: AppColors.done)),
                const SizedBox(width: 10),
                Expanded(child: SummaryCard(label: '📊 Tổng', value: p.accounts.length, color: AppColors.primary)),
                const SizedBox(width: 10),
                Expanded(child: SummaryCard(label: '🔐 Proxy', value: p.proxies.length, color: AppColors.accent)),
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
                      label: Text(s == 'all' ? 'Tất cả' : s == 'todo' ? 'Chờ' : 'Xong'),
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
                  ...p.groups.map((g) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(g),
                          selected: _groupFilter == g,
                          onSelected: (_) => setState(() => _groupFilter = g),
                        ),
                      )),
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
                        const Icon(Icons.catching_pokemon, size: 64, color: AppColors.textSecondary),
                        const SizedBox(height: 12),
                        Text(
                          p.accounts.isEmpty ? 'Chưa có tài khoản nào' : 'Không tìm thấy tài khoản',
                          style: const TextStyle(color: AppColors.textSecondary),
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
