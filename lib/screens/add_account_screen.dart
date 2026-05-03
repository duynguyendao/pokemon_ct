import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../utils/app_theme.dart';

class AddAccountScreen extends StatefulWidget {
  const AddAccountScreen({super.key});

  @override
  State<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends State<AddAccountScreen> {
  final _textCtrl = TextEditingController();
  String? _selectedGroup;
  int _parsedCount = 0;

  void _onTextChanged(String v) {
    final lines = v.trim().split('\n');
    int count = 0;
    for (final line in lines) {
      if (line.trim().contains(':')) count++;
    }
    setState(() => _parsedCount = count);
  }

  Future<void> _import(AppProvider p) async {
    final accounts = p.parseAccountsText(_textCtrl.text, group: _selectedGroup);
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có dữ liệu hợp lệ!')),
      );
      return;
    }
    await p.addAccounts(accounts);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã thêm ${accounts.length} tài khoản!')),
      );
      Navigator.pop(context);
    }
  }

  void _showPresetHint() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Hướng dẫn định dạng', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Nhập mỗi tài khoản trên một dòng theo định dạng:\n\n'
          'email@example.com:password\n\n'
          'Ví dụ:\n'
          'trainer1@gmail.com:Pass@123\n'
          'trainer2@gmail.com:Pass@456\n\n'
          'Nếu không có mật khẩu, dùng mật khẩu mặc định đã cài.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Thêm tài khoản'),
        actions: [
          IconButton(icon: const Icon(Icons.help_outline), onPressed: _showPresetHint),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Group selector
            DropdownButtonFormField<String?>(
              value: _selectedGroup,
              dropdownColor: AppColors.surfaceVariant,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Nhóm (tùy chọn)',
                prefixIcon: Icon(Icons.group, color: AppColors.textSecondary),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Không có nhóm')),
                ...p.groups.map((g) => DropdownMenuItem(value: g, child: Text(g))),
              ],
              onChanged: (v) => setState(() => _selectedGroup = v),
            ),
            const SizedBox(height: 16),

            // Text input
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: TextField(
                  controller: _textCtrl,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'email@example.com:password\nemail2@example.com:password2\n...',
                    hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    contentPadding: EdgeInsets.all(12),
                    border: InputBorder.none,
                    filled: false,
                  ),
                  onChanged: _onTextChanged,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Count indicator
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Nhận diện: $_parsedCount tài khoản',
                    style: TextStyle(
                      color: _parsedCount > 0 ? AppColors.done : AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    _textCtrl.clear();
                    setState(() => _parsedCount = 0);
                  },
                  child: const Text('Xóa'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            ElevatedButton.icon(
              onPressed: _parsedCount > 0 ? () => _import(p) : null,
              icon: const Icon(Icons.download),
              label: Text('Nhập $_parsedCount tài khoản'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
