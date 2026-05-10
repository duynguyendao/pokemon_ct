import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_provider.dart';
import '../utils/app_theme.dart';
import '../services/debug_service.dart';

class OtpMonitorScreen extends StatefulWidget {
  const OtpMonitorScreen({super.key});

  @override
  State<OtpMonitorScreen> createState() => _OtpMonitorScreenState();
}

class _OtpMonitorScreenState extends State<OtpMonitorScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  // IMAP config
  final _hostCtrl = TextEditingController(text: 'imap.gmail.com');
  final _portCtrl = TextEditingController(text: '993');
  final _userCtrl = TextEditingController(text: 'duynguyenpk8793@gmail.com');
  final _passCtrl = TextEditingController();
  final _pollCtrl = TextEditingController(text: '1');

  // URL config
  final _loginUrlCtrl = TextEditingController(
    text: 'https://www.pokemoncenter-online.com/login/',
  );
  final _lotteryUrlCtrl = TextEditingController(
    text: 'https://www.pokemoncenter-online.com/lottery/',
  );
  final _lotteryResultUrlCtrl = TextEditingController(
    text: 'https://www.pokemoncenter-online.com/lottery-history/',
  );
  final _orderHistoryUrlCtrl = TextEditingController(
    text: 'https://www.pokemoncenter-online.com/order-history/',
  );

  // Search
  final _searchSubjectCtrl = TextEditingController(text: 'ポケモンセンター');
  final _searchBodyCtrl = TextEditingController();
  DateTime _searchFrom = DateTime.now().subtract(const Duration(minutes: 30));
  DateTime _searchTo = DateTime.now();
  List<EmailSearchResult> _searchResults = [];
  bool _searching = false;
  String? _searchError;

  bool _testing = false;
  String? _testError;
  bool _testSuccess = false;

  final _dateFmt = DateFormat('HH:mm dd/MM/yyyy');
  final _timeFmt = DateFormat('HH:mm:ss dd/MM');

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _searchSubjectCtrl.clear();
    _loadConfig();
  }

  void _loadConfig() {
    final p = context.read<AppProvider>();
    final cfg = p.imapConfig;
    if (cfg['host']?.isNotEmpty == true) _hostCtrl.text = cfg['host']!;
    if (cfg['port']?.isNotEmpty == true) _portCtrl.text = cfg['port']!;
    if (cfg['username']?.isNotEmpty == true) _userCtrl.text = cfg['username']!;
    if (cfg['password']?.isNotEmpty == true) _passCtrl.text = cfg['password']!;
    if (cfg['pollInterval']?.isNotEmpty == true)
      _pollCtrl.text = cfg['pollInterval']!;
    final urls = p.urlConfig;
    if (urls['loginUrl']?.isNotEmpty == true)
      _loginUrlCtrl.text = urls['loginUrl']!;
    if (urls['lotteryUrl']?.isNotEmpty == true)
      _lotteryUrlCtrl.text = urls['lotteryUrl']!;
    if (urls['lotteryResultUrl']?.isNotEmpty == true)
      _lotteryResultUrlCtrl.text = urls['lotteryResultUrl']!;
    if (urls['orderHistoryUrl']?.isNotEmpty == true)
      _orderHistoryUrlCtrl.text = urls['orderHistoryUrl']!;
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _pollCtrl.dispose();
    _searchSubjectCtrl.dispose();
    _searchBodyCtrl.dispose();
    _loginUrlCtrl.dispose();
    _lotteryUrlCtrl.dispose();
    _lotteryResultUrlCtrl.dispose();
    _orderHistoryUrlCtrl.dispose();
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
    await p.saveUrlConfig({
      'loginUrl': _loginUrlCtrl.text.trim(),
      'lotteryUrl': _lotteryUrlCtrl.text.trim(),
      'lotteryResultUrl': _lotteryResultUrlCtrl.text.trim(),
      'orderHistoryUrl': _orderHistoryUrlCtrl.text.trim(),
    });
  }

  Future<void> _testConnection(AppProvider p) async {
    await _saveConfig(p);
    setState(() {
      _testing = true;
      _testError = null;
      _testSuccess = false;
    });
    try {
      final ok = await p.testImapConnection();
      setState(() {
        _testing = false;
        _testSuccess = ok;
        _testError = ok ? null : p.imapError ?? 'Ket noi that bai.';
      });
    } catch (e) {
      setState(() {
        _testing = false;
        _testError = e.toString();
        _testSuccess = false;
      });
    }
  }

  Future<void> _toggleImap(AppProvider p) async {
    if (p.imapRunning) {
      await p.stopImap();
    } else {
      await _saveConfig(p);
      try {
        await p.startImap();
      } catch (_) {}

      if (p.imapError != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: ${p.imapError}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _searchEmails(AppProvider p) async {
    await _saveConfig(p);
    setState(() {
      _searching = true;
      _searchError = null;
      _searchResults = [];
    });
    try {
      final results = await p.searchEmails(
        subjectKeyword: _searchSubjectCtrl.text.trim(),
        bodyKeyword: _searchBodyCtrl.text.trim(),
        from: _searchFrom,
        to: _searchTo,
        maxMessages: 3,
      );
      setState(() {
        _searching = false;
        _searchResults = results;
      });
      if (results.isEmpty) {
        setState(
          () => _searchError =
              'Không tìm thấy email nào trong khoảng thời gian này.',
        );
      }
    } catch (e) {
      setState(() {
        _searching = false;
        _searchError = 'Lỗi: ${e.toString()}';
      });
    }
  }

  Future<void> _pickDateTime(bool isFrom) async {
    final now = DateTime.now();
    final initial = isFrom ? _searchFrom : _searchTo;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (time == null) return;
    final dt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (isFrom)
        _searchFrom = dt;
      else
        _searchTo = dt;
    });
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('OTP Monitor'),
            if (p.imapRunning) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.done.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.done, width: 1),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    color: AppColors.done,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.primary,
          labelColor: Colors.white,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: 'Cài đặt'),
            Tab(text: 'Tìm email'),
            Tab(text: 'Debug'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildSettingsTab(p),
          _buildSearchTab(p),
          _buildDebugTab(),
        ],
      ),
    );
  }

  // ─── TAB 1: Settings ──────────────────────────────────────────────────────

  Widget _buildSettingsTab(AppProvider p) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // OTP Source Card
          _sectionCard(
            title: 'Nguồn OTP',
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'imap',
                    label: Text('IMAP Email'),
                    icon: Icon(Icons.email_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: 'clipboard',
                    label: Text('Shortcut Clipboard'),
                    icon: Icon(Icons.content_paste, size: 16),
                  ),
                ],
                selected: {p.otpSource},
                onSelectionChanged: (v) => p.setOtpSource(v.first),
              ),
              const SizedBox(height: 10),
              if (p.otpSource == 'clipboard')
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primary.withAlpha(80)),
                  ),
                  child: const Text(
                    '📋 Shortcut iPhone sẽ tự phát hiện email → lấy OTP → copy vào Clipboard.\n'
                    'Khi browser đang chờ OTP, app tự động phát hiện mã 6 số mới trong Clipboard và điền vào.\n'
                    'Clipboard sẽ được xóa ngay sau khi dùng để tránh nhầm lẫn OTP cũ.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
                  ),
                )
              else
                const Text(
                  '💡 IMAP mode: app tự kết nối email để lấy OTP bên dưới.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // IMAP Connection Card
          _sectionCard(
            title: 'Kết nối IMAP',
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _hostCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Host'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 70,
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
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(
                    Icons.email_outlined,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passCtrl,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'App Password (Gmail: 16 ký tự, space OK)',
                  prefixIcon: Icon(
                    Icons.lock_outline,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pollCtrl,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Kiểm tra mỗi (giây)',
                  prefixIcon: Icon(
                    Icons.timer_outlined,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Test connection result
              if (_testSuccess || _testError != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _testSuccess
                        ? AppColors.done.withAlpha(20)
                        : AppColors.error.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _testSuccess ? AppColors.done : AppColors.error,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _testSuccess ? Icons.check_circle : Icons.error_outline,
                        color: _testSuccess ? AppColors.done : AppColors.error,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _testSuccess ? '✅ Kết nối thành công!' : _testError!,
                          style: TextStyle(
                            color: _testSuccess
                                ? AppColors.done
                                : AppColors.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _testing ? null : () => _testConnection(p),
                      icon: _testing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_outline, size: 16),
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
                      onPressed: (p.imapStarting || p.imapStopping)
                          ? null
                          : () => _toggleImap(p),
                      icon: (p.imapStarting || p.imapStopping)
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              p.imapRunning ? Icons.stop : Icons.play_arrow,
                              size: 16,
                            ),
                      label: Text(
                        p.imapStarting
                            ? 'Đang kết nối...'
                            : p.imapStopping
                            ? 'Đang dừng...'
                            : p.imapRunning
                            ? 'Dừng'
                            : 'Bắt đầu',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: p.imapRunning
                            ? AppColors.error
                            : AppColors.done,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // URL Settings
          _sectionCard(
            title: '🔗 Cài đặt đường dẫn',
            children: [
              TextField(
                controller: _loginUrlCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Login URL',
                  prefixIcon: Icon(
                    Icons.login,
                    color: AppColors.primary,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _lotteryUrlCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Lottery URL',
                  hintText: 'https://...',
                  prefixIcon: Icon(
                    Icons.casino_outlined,
                    color: AppColors.secondary,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _lotteryResultUrlCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Lottery Result URL',
                  hintText: 'https://...',
                  prefixIcon: Icon(
                    Icons.emoji_events_outlined,
                    color: AppColors.done,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _orderHistoryUrlCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Order History URL',
                  hintText: 'https://...',
                  prefixIcon: Icon(
                    Icons.receipt_long_outlined,
                    color: AppColors.secondary,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _saveConfig(p);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ Đã lưu cài đặt'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Lưu đường dẫn'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── TAB 2: Search ────────────────────────────────────────────────────────

  Widget _buildSearchTab(AppProvider p) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionCard(
            title: '🔍 Tìm email để kiểm tra kết nối',
            children: [
              TextField(
                controller: _searchSubjectCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Từ khoá tiêu đề',
                  hintText: 'ポケモンセンター hoặc パスコード',
                  prefixIcon: Icon(
                    Icons.subject,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchBodyCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Từ khoá trong nội dung email',
                  hintText: 'Ví dụ: confirmation, verify, code',
                  prefixIcon: Icon(
                    Icons.mail_outline,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // From date
              _dateRow('Từ', _searchFrom, () => _pickDateTime(true)),
              const SizedBox(height: 8),
              // To date
              _dateRow('Đến', _searchTo, () => _pickDateTime(false)),

              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _searching ? null : () => _searchEmails(p),
                icon: _searching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search, size: 16),
                label: Text(_searching ? 'Đang tìm...' : 'Tìm email'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 48)),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (_searchError != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.error),
              ),
              child: Text(
                _searchError!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ),

          if (_searchResults.isNotEmpty) ...[
            Text(
              'Tìm thấy ${_searchResults.length} email:',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            ..._searchResults.map((r) => _buildSearchResultTile(r)),
          ],
        ],
      ),
    );
  }

  Widget _dateRow(String label, DateTime dt, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today,
              color: AppColors.textSecondary,
              size: 16,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _dateFmt.format(dt),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            const Icon(Icons.edit, color: AppColors.textSecondary, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultTile(EmailSearchResult r) {
    final hasOtp = r.otpFound != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: hasOtp ? AppColors.done.withAlpha(30) : AppColors.card,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            hasOtp ? Icons.mark_email_read : Icons.email_outlined,
            color: hasOtp ? AppColors.done : AppColors.textSecondary,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                r.subject,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasOtp)
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: r.otpFound!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied OTP!'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.done,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    r.otpFound!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${r.sender} · ${_timeFmt.format(r.date)}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: AppColors.surfaceVariant,
            width: double.infinity,
            child: Text(
              r.body,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── TAB 3: Debug ─────────────────────────────────────────────────────────

  Widget _buildDebugTab() {
    return ChangeNotifierProvider.value(
      value: debugService,
      child: Consumer<DebugService>(
        builder: (context, debug, _) => Column(
          children: [
            // Controls
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${debug.logs.length} log messages',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => debug.clear(),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Clear'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.card,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Logs
            Expanded(
              child: debug.logs.isEmpty
                  ? const Center(
                      child: Text(
                        'Chưa có log nào',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      reverse: false,
                      padding: const EdgeInsets.all(8),
                      itemCount: debug.logs.length,
                      itemBuilder: (_, i) {
                        final log = debug.logs[i];
                        final isError =
                            log.contains('ERROR') ||
                            log.contains('failed') ||
                            log.contains('lỗi');
                        final isSuccess =
                            log.contains('✓') ||
                            log.contains('Success') ||
                            log.contains('OK');
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isError
                                ? AppColors.error.withAlpha(10)
                                : isSuccess
                                ? AppColors.done.withAlpha(10)
                                : AppColors.card,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isError
                                  ? AppColors.error.withAlpha(50)
                                  : isSuccess
                                  ? AppColors.done.withAlpha(50)
                                  : AppColors.divider,
                            ),
                          ),
                          child: SelectableText(
                            log,
                            style: TextStyle(
                              color: isError
                                  ? AppColors.error
                                  : isSuccess
                                  ? AppColors.done
                                  : Colors.white,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── HELPERS ──────────────────────────────────────────────────────────────

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}
