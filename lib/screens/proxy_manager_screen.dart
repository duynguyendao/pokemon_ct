import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/proxy.dart';
import '../providers/app_provider.dart';
import '../utils/app_theme.dart';
import 'package:intl/intl.dart';

class ProxyManagerScreen extends StatefulWidget {
  const ProxyManagerScreen({super.key});

  @override
  State<ProxyManagerScreen> createState() => _ProxyManagerScreenState();
}

class _ProxyManagerScreenState extends State<ProxyManagerScreen> {
  void _showAddEditDialog({Proxy? existing}) {
    final p = context.read<AppProvider>();
    final hostCtrl = TextEditingController(text: existing?.host ?? '');
    final portCtrl = TextEditingController(text: existing?.port.toString() ?? '');
    final userCtrl = TextEditingController(text: existing?.username ?? '');
    final passCtrl = TextEditingController(text: existing?.password ?? '');
    final labelCtrl = TextEditingController(text: existing?.label ?? '');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          existing == null ? 'Thêm proxy' : 'Chỉnh sửa proxy',
          style: const TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Nhãn (tùy chọn)',
                  prefixIcon: Icon(Icons.label_outline, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: hostCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Host / IP'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: portCtrl,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Port'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: userCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Username (tùy chọn)',
                  prefixIcon: Icon(Icons.person_outline, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Password (tùy chọn)',
                  prefixIcon: Icon(Icons.lock_outline, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () {
              final host = hostCtrl.text.trim();
              final port = int.tryParse(portCtrl.text.trim()) ?? 0;
              if (host.isEmpty || port == 0) return;

              if (existing == null) {
                p.addProxy(Proxy(
                  host: host,
                  port: port,
                  username: userCtrl.text.trim().isEmpty ? null : userCtrl.text.trim(),
                  password: passCtrl.text.trim().isEmpty ? null : passCtrl.text.trim(),
                  label: labelCtrl.text.trim().isEmpty ? null : labelCtrl.text.trim(),
                ));
              } else {
                p.updateProxy(existing.copyWith(
                  host: host,
                  port: port,
                  username: userCtrl.text.trim().isEmpty ? null : userCtrl.text.trim(),
                  password: passCtrl.text.trim().isEmpty ? null : passCtrl.text.trim(),
                  label: labelCtrl.text.trim().isEmpty ? null : labelCtrl.text.trim(),
                ));
              }
              Navigator.pop(context);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _showBatchImport() {
    final p = context.read<AppProvider>();
    final ctrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Nhập hàng loạt proxy', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Định dạng: host:port hoặc host:port:user:pass',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: TextField(
                controller: ctrl,
                maxLines: null,
                expands: true,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: '192.168.1.1:8080\n192.168.1.2:8080:user:pass',
                  hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () {
              int count = 0;
              for (final line in ctrl.text.trim().split('\n')) {
                final parts = line.trim().split(':');
                if (parts.length < 2) continue;
                final port = int.tryParse(parts[1].trim());
                if (parts[0].trim().isEmpty || port == null) continue;
                p.addProxy(Proxy(
                  host: parts[0].trim(),
                  port: port,
                  username: parts.length > 2 ? parts[2].trim() : null,
                  password: parts.length > 3 ? parts[3].trim() : null,
                ));
                count++;
              }
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Đã thêm $count proxy')),
              );
            },
            child: const Text('Nhập'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final fmt = DateFormat('dd/MM HH:mm');

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text('Proxy (${p.proxies.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: _showBatchImport,
            tooltip: 'Nhập hàng loạt',
          ),
        ],
      ),
      body: Column(
        children: [
          // Global toggle
          Container(
            color: AppColors.surfaceVariant,
            child: SwitchListTile(
              value: p.proxyEnabled,
              onChanged: p.setProxyEnabled,
              title: const Text('Bật xoay proxy', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                p.proxyEnabled ? 'Tự động dùng proxy khi mở tài khoản' : 'Proxy đang tắt',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              activeThumbColor: AppColors.done,
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: p.proxies.isEmpty
                ? const Center(
                    child: Text('Chưa có proxy nào',
                        style: TextStyle(color: AppColors.textSecondary)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: p.proxies.length,
                    itemBuilder: (_, i) {
                      final proxy = p.proxies[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: proxy.enabled
                                  ? AppColors.done.withAlpha(30)
                                  : AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.vpn_lock,
                              color: proxy.enabled ? AppColors.done : AppColors.textSecondary,
                              size: 22,
                            ),
                          ),
                          title: Text(
                            proxy.displayLabel,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${proxy.host}:${proxy.port}',
                                style: const TextStyle(
                                    color: AppColors.textSecondary, fontSize: 11),
                              ),
                              Row(
                                children: [
                                  Text(
                                    'Dùng: ${proxy.usageCount}',
                                    style: const TextStyle(
                                        color: AppColors.textSecondary, fontSize: 11),
                                  ),
                                  if (proxy.lastUsed != null) ...[
                                    const Text(' · ',
                                        style: TextStyle(color: AppColors.textSecondary)),
                                    Text(
                                      fmt.format(proxy.lastUsed!),
                                      style: const TextStyle(
                                          color: AppColors.textSecondary, fontSize: 11),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: proxy.enabled,
                                onChanged: (v) =>
                                    p.updateProxy(proxy.copyWith(enabled: v)),
                                activeThumbColor: AppColors.done,
                              ),
                              PopupMenuButton<String>(
                                color: AppColors.surfaceVariant,
                                icon: const Icon(Icons.more_vert,
                                    color: AppColors.textSecondary),
                                onSelected: (v) {
                                  if (v == 'edit') _showAddEditDialog(existing: proxy);
                                  if (v == 'copy') {
                                    Clipboard.setData(
                                        ClipboardData(text: proxy.proxyUrl));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('Đã copy URL proxy'),
                                          duration: Duration(seconds: 1)),
                                    );
                                  }
                                  if (v == 'delete') p.deleteProxy(proxy.id);
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(children: [
                                      Icon(Icons.edit, size: 16, color: Colors.white),
                                      SizedBox(width: 8),
                                      Text('Chỉnh sửa',
                                          style: TextStyle(color: Colors.white)),
                                    ]),
                                  ),
                                  const PopupMenuItem(
                                    value: 'copy',
                                    child: Row(children: [
                                      Icon(Icons.copy, size: 16, color: Colors.white),
                                      SizedBox(width: 8),
                                      Text('Copy URL',
                                          style: TextStyle(color: Colors.white)),
                                    ]),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(children: [
                                      Icon(Icons.delete, size: 16, color: AppColors.error),
                                      SizedBox(width: 8),
                                      Text('Xóa',
                                          style: TextStyle(color: AppColors.error)),
                                    ]),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
