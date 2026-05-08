import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/lottery_result_entry.dart';
import '../providers/app_provider.dart';
import '../utils/app_theme.dart';

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

  // Table filter / sort state
  String? _filterResult; // null = all, '当選', '落選', 'エラー'
  bool _sortWonFirst = false;

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

  // ─── Computed ──────────────────────────────────────────────────────────────

  List<LotteryResultEntry> _filtered(List<LotteryResultEntry> all) {
    var list = all.where((e) {
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q.isNotEmpty && !e.accountEmail.toLowerCase().contains(q)) return false;
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

  // ─── CSV / Export ──────────────────────────────────────────────────────────

  String _buildCsv(List<LotteryResultEntry> rows) {
    final lines = ['Email,Hàng,Thời gian,Kết quả'];
    for (final r in rows) {
      lines.add('"${r.accountEmail}","${r.productTitle}","${r.time}","${r.result}"');
    }
    return lines.join('\n');
  }

  void _copyResultsCsv(List<LotteryResultEntry> rows) {
    Clipboard.setData(ClipboardData(text: _buildCsv(rows)));
    _snack('Đã copy ${rows.length} dòng CSV');
  }

  Future<void> _exportCsvFile(List<LotteryResultEntry> rows) async {
    final csv = _buildCsv(rows);
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
    final file = File('${Directory.systemTemp.path}/lottery_results_$ts.csv');
    await file.writeAsString(csv);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Lottery Results $ts',
    );
  }

  void _copyWonEmails(List<LotteryResultEntry> rows) {
    final won = rows.where((r) => r.isWon).map((r) => r.accountEmail).join('\n');
    if (won.isEmpty) {
      _snack('Không có 当選 trong danh sách hiện tại');
      return;
    }
    Clipboard.setData(ClipboardData(text: won));
    _snack('Đã copy email 当選');
  }

  void _snack(String msg, {Duration duration = const Duration(seconds: 2)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: duration));
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
    return Consumer<AppProvider>(
      builder: (context, p, _) {
        final all = p.lotteryResults;
        final rows = _filtered(all);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildKeywordCard(p),
              const SizedBox(height: 16),
              if (all.isNotEmpty) _buildResultsSection(p, all, rows),
            ],
          ),
        );
      },
    );
  }

  Widget _buildKeywordCard(AppProvider p) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Từ khóa sản phẩm',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Set keyword → đổi mode account sang Result → Start All để check',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
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
                        onPressed: () => setState(() => _productCtrl.clear()),
                      )
                    : null,
              ),
              onChanged: (v) {
                setState(() {});
                p.setTargetProductName(v.trim());
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Result URL: ${p.lotteryResultUrl}',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Results section ───────────────────────────────────────────────────────

  Widget _buildResultsSection(
      AppProvider p, List<LotteryResultEntry> all, List<LotteryResultEntry> rows) {
    final wonCount = all.where((r) => r.isWon).length;
    final lostCount = all.where((r) => r.isLost).length;
    final errCount = all.where((r) => r.isError).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary row
        Row(
          children: [
            Text(
              rows.length == all.length
                  ? '${all.length} kết quả'
                  : '${rows.length} / ${all.length}',
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
            Tooltip(
              message: _sortWonFirst ? 'Sort: 当選 trên' : 'Sort 当選 lên trên',
              child: IconButton(
                icon: Icon(Icons.sort,
                    color: _sortWonFirst
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    size: 20),
                onPressed: () => setState(() => _sortWonFirst = !_sortWonFirst),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Search by email
        TextField(
          controller: _searchCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Tìm theo email...',
            hintStyle: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12),
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

        // Filter chips
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

        // Action buttons
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.copy_all,
                  color: AppColors.textSecondary, size: 20),
              tooltip: 'Copy CSV (filtered)',
              onPressed: () => _copyResultsCsv(rows),
            ),
            IconButton(
              icon: const Icon(Icons.ios_share,
                  color: AppColors.textSecondary, size: 20),
              tooltip: 'Export file CSV',
              onPressed: () => _exportCsvFile(rows),
            ),
            if (rows.any((r) => r.isWon))
              IconButton(
                icon: const Icon(Icons.emoji_events,
                    color: AppColors.done, size: 20),
                tooltip: 'Copy email 当選',
                onPressed: () => _copyWonEmails(rows),
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.error, size: 20),
              tooltip: 'Xóa tất cả',
              onPressed: () {
                p.clearLotteryResults();
                setState(() {
                  _filterResult = null;
                  _searchCtrl.clear();
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Table
        _buildTable(rows),
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
            text: '${e.accountEmail},${e.productTitle},${e.time},${e.result}'));
        _snack('Copied row', duration: const Duration(seconds: 1));
      },
      child: Container(
        color: e.isWon ? AppColors.done.withAlpha(15) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(e.accountEmail,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            ),
            Expanded(
              flex: 3,
              child: Text(e.productTitle.isEmpty ? '—' : e.productTitle,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            ),
            Expanded(
              flex: 2,
              child: Text(e.time.isEmpty ? '—' : e.time,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 10),
                  overflow: TextOverflow.ellipsis),
            ),
            SizedBox(
              width: 64,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: resultColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: resultColor.withAlpha(120)),
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

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withAlpha(120)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.bold)),
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
