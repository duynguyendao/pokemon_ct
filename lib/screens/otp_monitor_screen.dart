import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/filter_rule.dart';
import '../models/otp_entry.dart';
import '../providers/app_provider.dart';
import '../utils/app_theme.dart';
import 'package:intl/intl.dart';

class OtpMonitorScreen extends StatefulWidget {
  const OtpMonitorScreen({super.key});

  @override
  State<OtpMonitorScreen> createState() => _OtpMonitorScreenState();
}

class _OtpMonitorScreenState extends State<OtpMonitorScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  // IMAP config controllers
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '993');
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pollCtrl = TextEditingController(text: '30');
  bool _testing = false;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    final p = context.read<AppProvider>();
    final cfg = p.imapConfig;
    _hostCtrl.text = cfg['host'] ?? '';
    _portCtrl.text = cfg['port'] ?? '993';
    _userCtrl.text = cfg['username'] ?? '';
    _passCtrl.text = cfg['password'] ?? '';
    _pollCtrl.text = cfg['pollInterval'] ?? '30';
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _pollCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveConfig(AppProvider p) async {
    await p.saveImapConfig({
      'host': _hostCtrl.text.trim(),
      'port': _portCtrl.text.trim(),
      'username': _userCtrl.text.trim(),
      'password': _passCtrl.text.trim(),
      'pollInterval': _pollCtrl.text.trim(),
    });
  }

  Future<void> _testConnection(AppProvider p) async {
    await _saveConfig(p);
    setState(() => _testing = true);
    final ok = await p.testImapConnection();
    setState(() => _testing = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Kết nối thành công!' : 'Kết nối thất bại!'),
        backgroundColor: ok ? AppColors.done : AppColors.error,
      ));
    }
  }

  Future<void> _toggleImap(AppProvider p) async {
    if (p.imapRunning) {
      await p.stopImap();
    } else {
      await _saveConfig(p);
      await p.startImap();
      if (p.imapError != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Lỗi: ${p.imapError}'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  Future<void> _fetchNow(AppProvider p) async {
    setState(() => _fetching = true);
    final results = await p.fetchOtpNow();
    setState(() => _fetching = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(results.isEmpty ? 'Không tìm thấy OTP mới' : 'Tìm thấy ${results.length} OTP'),
      ));
    }
  }

  void _showAddRuleDialog(AppProvider p) {
    FilterType type = FilterType.sender;
    final patternCtrl = TextEditingController();
    final extractCtrl = TextEditingController(text: r'\b(\d{6})\b');

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Thêm quy tắc lọc', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<FilterType>(
                value: type,
                dropdownColor: AppColors.surfaceVariant,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Loại'),
                items: FilterType.values
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t == FilterType.sender
                              ? 'Người gửi'
                              : t == FilterType.subject
                                  ? 'Tiêu đề'
                                  : 'Regex'),
                        ))
                    .toList(),
                onChanged: (v) => setS(() => type = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: patternCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Pattern',
                  hintText: 'pokemon-center',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: extractCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Regex trích xuất OTP',
                  hintText: r'\b(\d{6})\b',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: () {
                if (patternCtrl.text.trim().isNotEmpty) {
                  final rules = List<FilterRule>.from(p.filterRules)
                    ..add(FilterRule(
                      type: type,
                      pattern: patternCtrl.text.trim(),
                      extractPattern: extractCtrl.text.trim(),
                    ));
                  p.saveFilterRules(rules);
                  Navigator.pop(context);
                }
              },
              child: const Text('Thêm'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('OTP Monitor'),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Cài đặt'),
            Tab(text: 'OTP'),
          ],
        ),
        actions: [
          if (p.imapRunning)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.circle, color: AppColors.done, size: 12),
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildSettingsTab(p),
          _buildOtpTab(p),
        ],
      ),
    );
  }

  Widget _buildSettingsTab(AppProvider p) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Connection Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Kết nối IMAP',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _hostCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Host',
                            hintText: 'imap.gmail.com',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _portCtrl,
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Port'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _userCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined, color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passCtrl,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'App Password',
                      prefixIcon: Icon(Icons.lock_outline, color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pollCtrl,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Poll interval (giây)',
                      prefixIcon: Icon(Icons.timer_outlined, color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _testing ? null : () => _testConnection(p),
                          icon: _testing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.check_circle_outline),
                          label: Text(_testing ? 'Đang test...' : 'Test kết nối'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(color: AppColors.divider),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _toggleImap(p),
                          icon: Icon(p.imapRunning ? Icons.stop : Icons.play_arrow),
                          label: Text(p.imapRunning ? 'Dừng' : 'Bắt đầu'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                p.imapRunning ? AppColors.error : AppColors.done,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Filter Rules
          Row(
            children: [
              const Text('Quy tắc lọc',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _showAddRuleDialog(p),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Thêm'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...p.filterRules.map((rule) => _buildRuleTile(rule, p)),
        ],
      ),
    );
  }

  Widget _buildRuleTile(FilterRule rule, AppProvider p) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.secondary.withAlpha(50),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(rule.typeLabel,
              style: const TextStyle(color: AppColors.secondary, fontSize: 11)),
        ),
        title: Text(rule.pattern, style: const TextStyle(color: Colors.white, fontSize: 14)),
        subtitle: rule.extractPattern != null
            ? Text('Extract: ${rule.extractPattern}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11))
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: rule.enabled,
              onChanged: (v) {
                final rules = List<FilterRule>.from(p.filterRules);
                final idx = rules.indexWhere((r) => r.id == rule.id);
                if (idx >= 0) rules[idx] = rule.copyWith(enabled: v);
                p.saveFilterRules(rules);
              },
              activeThumbColor: AppColors.done,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
              onPressed: () {
                final rules = List<FilterRule>.from(p.filterRules)
                  ..removeWhere((r) => r.id == rule.id);
                p.saveFilterRules(rules);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtpTab(AppProvider p) {
    final fmt = DateFormat('HH:mm:ss dd/MM');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  p.imapRunning
                      ? 'Đang theo dõi... (${p.otpHistory.length} OTPs)'
                      : 'Chưa kết nối',
                  style: TextStyle(
                    color: p.imapRunning ? AppColors.done : AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _fetching ? null : () => _fetchNow(p),
                icon: _fetching
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 16),
                label: Text(_fetching ? '...' : 'Lấy ngay'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.card,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: p.otpHistory.isEmpty
              ? const Center(
                  child: Text('Chưa có OTP nào',
                      style: TextStyle(color: AppColors.textSecondary)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: p.otpHistory.length,
                  itemBuilder: (_, i) {
                    final otp = p.otpHistory[i];
                    return _buildOtpTile(otp, fmt);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildOtpTile(OtpEntry otp, DateFormat fmt) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: otp.isRecent
                ? AppColors.done.withAlpha(30)
                : AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: otp.isRecent
                ? Border.all(color: AppColors.done, width: 1)
                : null,
          ),
          child: Icon(
            Icons.sms,
            color: otp.isRecent ? AppColors.done : AppColors.textSecondary,
            size: 24,
          ),
        ),
        title: Row(
          children: [
            Text(
              otp.code,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
                letterSpacing: 3,
              ),
            ),
            if (otp.isRecent) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.done,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('MỚI',
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (otp.sender != null)
              Text(otp.sender!,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            Text(fmt.format(otp.timestamp),
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.copy, color: AppColors.textSecondary, size: 20),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: otp.code));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đã copy OTP!'), duration: Duration(seconds: 1)),
            );
          },
        ),
      ),
    );
  }
}
