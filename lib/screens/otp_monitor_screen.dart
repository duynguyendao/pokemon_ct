import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../utils/app_theme.dart';

class OtpMonitorScreen extends StatefulWidget {
  const OtpMonitorScreen({super.key});

  @override
  State<OtpMonitorScreen> createState() => _OtpMonitorScreenState();
}

class _OtpMonitorScreenState extends State<OtpMonitorScreen> {
  // URL config
  final _loginUrlCtrl = TextEditingController();
  final _lotteryUrlCtrl = TextEditingController();
  final _lotteryResultUrlCtrl = TextEditingController();
  final _orderHistoryUrlCtrl = TextEditingController();

  // GAS Script
  final _gasUrlCtrl = TextEditingController();
  final _gasSecretCtrl = TextEditingController();
  bool _gasTesting = false;
  String? _gasTestResult;
  bool _gasTestOk = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _testGasUrl() async {
    final url = _gasUrlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _gasTesting = true;
      _gasTestResult = null;
    });
    try {
      final base = Uri.parse(url);
      final secret = _gasSecretCtrl.text.trim();
      final params = <String, String>{
        ...base.queryParameters,
        'after': '0',
      };
      if (secret.isNotEmpty) params['secret'] = secret;
      final uri = base.replace(queryParameters: params);
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['ok'] == true) {
          final otp = data['otp'];
          if (otp != null) {
            setState(() {
              _gasTestOk = true;
              _gasTestResult = '✅ Kết nối OK — OTP: $otp';
            });
          } else {
            final debug = data['debug'] ?? '';
            setState(() {
              _gasTestOk = true;
              _gasTestResult = '✅ Kết nối OK — Chưa có OTP mới ($debug)';
            });
          }
        } else {
          final err = data['error'] ?? 'unknown';
          setState(() {
            _gasTestOk = false;
            _gasTestResult = '❌ Script lỗi: $err';
          });
        }
      } else {
        setState(() {
          _gasTestOk = false;
          _gasTestResult = '❌ HTTP ${resp.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _gasTestOk = false;
        _gasTestResult = '❌ Lỗi kết nối: $e';
      });
    } finally {
      setState(() => _gasTesting = false);
    }
  }

  void _loadConfig() {
    final p = context.read<AppProvider>();
    if (p.gasScriptUrl.isNotEmpty) _gasUrlCtrl.text = p.gasScriptUrl;
    if (p.gasSecretKey.isNotEmpty) _gasSecretCtrl.text = p.gasSecretKey;
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
    _loginUrlCtrl.dispose();
    _lotteryUrlCtrl.dispose();
    _lotteryResultUrlCtrl.dispose();
    _orderHistoryUrlCtrl.dispose();
    _gasUrlCtrl.dispose();
    _gasSecretCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveUrlConfig(AppProvider p) async {
    await p.saveUrlConfig({
      'loginUrl': _loginUrlCtrl.text.trim(),
      'lotteryUrl': _lotteryUrlCtrl.text.trim(),
      'lotteryResultUrl': _lotteryResultUrlCtrl.text.trim(),
      'orderHistoryUrl': _orderHistoryUrlCtrl.text.trim(),
    });
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('OTP & Cài đặt')),
      body: SingleChildScrollView(
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
                      value: 'clipboard',
                      label: Text('Shortcut'),
                      icon: Icon(Icons.content_paste, size: 16),
                    ),
                    ButtonSegment(
                      value: 'gas',
                      label: Text('Google Script'),
                      icon: Icon(Icons.code, size: 16),
                    ),
                  ],
                  selected: {p.otpSource == 'imap' ? 'clipboard' : p.otpSource},
                  onSelectionChanged: (v) => p.setOtpSource(v.first),
                ),
                const SizedBox(height: 10),
                if (p.otpSource == 'clipboard' || p.otpSource == 'imap')
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: AppColors.primary.withAlpha(80)),
                    ),
                    child: const Text(
                      '📋 Shortcut iPhone tự phát hiện email → lấy OTP → copy vào Clipboard.\n'
                      'App tự điền mã 6 số mới trong Clipboard khi browser chờ OTP.\n'
                      'Clipboard xóa ngay sau khi dùng để tránh nhầm OTP cũ.',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.4),
                    ),
                  )
                else if (p.otpSource == 'gas') ...[
                  TextField(
                    controller: _gasUrlCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Google Apps Script URL',
                      hintText: 'https://script.google.com/macros/s/.../exec',
                      hintStyle: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11),
                      prefixIcon: Icon(Icons.link,
                          color: AppColors.textSecondary, size: 18),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _gasSecretCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Secret Key',
                      hintText: 'SECRET_KEY đã đặt trong GAS script',
                      hintStyle: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11),
                      prefixIcon: Icon(Icons.key,
                          color: AppColors.textSecondary, size: 18),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed:
                            _gasTesting || _gasUrlCtrl.text.trim().isEmpty
                                ? null
                                : _testGasUrl,
                        icon: _gasTesting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : const Icon(Icons.wifi_tethering, size: 16),
                        label: Text(
                            _gasTesting ? 'Đang test...' : 'Test kết nối'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: _gasUrlCtrl.text.trim().isEmpty
                            ? null
                            : () async {
                                await p.setGasScriptUrl(
                                    _gasUrlCtrl.text.trim());
                                await p.setGasSecretKey(
                                    _gasSecretCtrl.text.trim());
                                FocusScope.of(context).unfocus();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content:
                                          Text('Đã lưu GAS URL + Secret'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.save_alt, size: 16),
                        label: const Text('Lưu'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.done,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  if (_gasTestResult != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (_gasTestOk ? AppColors.done : AppColors.error)
                            .withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color:
                              (_gasTestOk ? AppColors.done : AppColors.error)
                                  .withAlpha(100),
                        ),
                      ),
                      child: Text(
                        _gasTestResult!,
                        style: TextStyle(
                          color:
                              _gasTestOk ? AppColors.done : AppColors.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  const Text(
                    '💡 App tự gửi secret + after + to khi poll OTP.',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
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
                    prefixIcon: Icon(Icons.login,
                        color: AppColors.primary, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _lotteryUrlCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Lottery URL',
                    hintText: 'https://...landing-page.html',
                    prefixIcon: Icon(Icons.casino_outlined,
                        color: AppColors.secondary, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _lotteryResultUrlCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Lottery Result URL',
                    prefixIcon: Icon(Icons.emoji_events_outlined,
                        color: AppColors.done, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _orderHistoryUrlCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Order History URL',
                    prefixIcon: Icon(Icons.receipt_long_outlined,
                        color: AppColors.secondary, size: 18),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await _saveUrlConfig(p);
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
      ),
    );
  }

  Widget _sectionCard(
      {required String title, required List<Widget> children}) {
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
