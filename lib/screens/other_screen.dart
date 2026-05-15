import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/lottery_result_entry.dart';
import '../models/order_status_entry.dart';
import '../models/result_snapshot.dart';
import '../models/shipping_entry.dart';
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

  // Lottery result filter / sort state
  String? _filterResult; // null = all, '当選', '落選', 'エラー'
  bool _sortWonFirst = false;

  // Order status filter / search state
  late TextEditingController _orderSearchCtrl;
  String? _filterOrderStatus; // null = all

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    final p = context.read<AppProvider>();
    _productCtrl = TextEditingController(text: p.targetProductName);
    _searchCtrl = TextEditingController();
    _searchCtrl.addListener(() => setState(() {}));
    _orderSearchCtrl = TextEditingController();
    _orderSearchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _productCtrl.dispose();
    _searchCtrl.dispose();
    _orderSearchCtrl.dispose();
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

  // Escape 1 field CSV: bao bằng nháy kép, escape " thành ""
  String _csvField(String v) => '"${v.replaceAll('"', '""')}"';

  String _buildCsv(List<LotteryResultEntry> rows) {
    final lines = ['Email,商品名,日時,結果'];
    for (final r in rows) {
      lines.add([
        _csvField(r.accountEmail),
        _csvField(r.productTitle),
        _csvField(r.time),
        _csvField(r.result),
      ].join(','));
    }
    // \r\n line endings — Excel/Numbers đọc chuẩn hơn
    return lines.join('\r\n');
  }

  void _copyResultsCsv(List<LotteryResultEntry> rows) {
    Clipboard.setData(ClipboardData(text: _buildCsv(rows)));
    _snack('Đã copy ${rows.length} dòng CSV');
  }

  Future<void> _exportCsvFile(List<LotteryResultEntry> rows) async {
    final csv = _buildCsv(rows);
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
    final file = File('${Directory.systemTemp.path}/lottery_results_$ts.csv');
    // UTF-8 BOM (0xEF 0xBB 0xBF) + nội dung → Excel/Numbers nhận đúng encoding tiếng Nhật
    const bom = [0xEF, 0xBB, 0xBF];
    await file.writeAsBytes([...bom, ...utf8.encode(csv)]);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv; charset=utf-8')],
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
              icon: const Icon(Icons.save_alt,
                  color: AppColors.done, size: 20),
              tooltip: 'Save snapshot vào History',
              onPressed: () async {
                final s = await p.saveSnapshotFromCurrentResults(SnapshotType.lottery);
                _snack(s != null
                    ? 'Đã lưu snapshot (${s.count} entries)'
                    : 'Không có kết quả để lưu');
              },
            ),
            IconButton(
              icon: const Icon(Icons.history,
                  color: AppColors.secondary, size: 20),
              tooltip: 'Xem History',
              onPressed: () => _showHistorySheet(SnapshotType.lottery),
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
    return Consumer<AppProvider>(
      builder: (context, p, _) {
        final all = p.orderStatusResults;
        final rows = _filteredOrders(all);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildOrderKeywordCard(p),
              const SizedBox(height: 16),
              if (all.isNotEmpty) _buildOrderResultsSection(p, all, rows),
              if (p.shippingResults.isNotEmpty) ...[
                const SizedBox(height: 20),
                _buildShippingSection(p),
              ],
            ],
          ),
        );
      },
    );
  }

  List<OrderStatusEntry> _filteredOrders(List<OrderStatusEntry> all) {
    return all.where((e) {
      final q = _orderSearchCtrl.text.trim().toLowerCase();
      if (q.isNotEmpty && !e.accountEmail.toLowerCase().contains(q)) return false;
      if (_filterOrderStatus != null && e.status != _filterOrderStatus) return false;
      return true;
    }).toList();
  }

  Widget _buildOrderKeywordCard(AppProvider p) {
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
              'Set keyword → đổi mode account sang Order → Start All để check',
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
              'Order URL: ${p.orderHistoryUrl}',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderResultsSection(
      AppProvider p, List<OrderStatusEntry> all, List<OrderStatusEntry> rows) {
    final shippedCount = all.where((e) => e.isShipped).length;
    final preparingCount = all.where((e) => e.isPreparing).length;
    final receivedCount = all.where((e) => e.isReceived).length;
    final cancelledCount = all.where((e) => e.isCancelled).length;
    final errCount = all.where((e) => e.isError).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary chips
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
            if (shippedCount > 0) ...[
              _chip('発送済み $shippedCount', AppColors.done),
              const SizedBox(width: 5),
            ],
            if (preparingCount > 0) ...[
              _chip('準備中 $preparingCount', AppColors.secondary),
              const SizedBox(width: 5),
            ],
            if (receivedCount > 0) ...[
              _chip('受付 $receivedCount', AppColors.primary),
              const SizedBox(width: 5),
            ],
            if (cancelledCount > 0) ...[
              _chip('キャンセル $cancelledCount', Colors.grey),
              const SizedBox(width: 5),
            ],
            if (errCount > 0)
              _chip('エラー $errCount', AppColors.warning),
          ],
        ),
        const SizedBox(height: 8),

        // Search by email
        TextField(
          controller: _orderSearchCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Tìm theo email...',
            hintStyle: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12),
            prefixIcon: const Icon(Icons.search,
                color: AppColors.textSecondary, size: 18),
            suffixIcon: _orderSearchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear,
                        color: AppColors.textSecondary, size: 16),
                    onPressed: () => _orderSearchCtrl.clear(),
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
              _orderFilterChip('Tất cả', null),
              const SizedBox(width: 6),
              _orderFilterChip('注文受付済み', '注文受付済み'),
              const SizedBox(width: 6),
              _orderFilterChip('発送準備中', '発送準備中'),
              const SizedBox(width: 6),
              _orderFilterChip('発送済み', '発送済み'),
              const SizedBox(width: 6),
              _orderFilterChip('キャンセル済み', 'キャンセル済み'),
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
              tooltip: 'Copy CSV',
              onPressed: () => _copyOrderCsv(rows),
            ),
            IconButton(
              icon: const Icon(Icons.ios_share,
                  color: AppColors.accent, size: 20),
              tooltip: 'Export CSV file',
              onPressed: () => _exportOrderCsvFile(rows),
            ),
            IconButton(
              icon: const Icon(Icons.save_alt,
                  color: AppColors.done, size: 20),
              tooltip: 'Save snapshot vào History',
              onPressed: () async {
                final s = await p.saveSnapshotFromCurrentResults(SnapshotType.order);
                _snack(s != null
                    ? 'Đã lưu snapshot (${s.count} entries)'
                    : 'Không có kết quả để lưu');
              },
            ),
            IconButton(
              icon: const Icon(Icons.history,
                  color: AppColors.secondary, size: 20),
              tooltip: 'Xem History',
              onPressed: () => _showHistorySheet(SnapshotType.order),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.error, size: 20),
              tooltip: 'Xóa tất cả',
              onPressed: () {
                p.clearOrderStatusResults();
                setState(() {
                  _filterOrderStatus = null;
                  _orderSearchCtrl.clear();
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Table
        _buildOrderTable(rows),
      ],
    );
  }

  Widget _orderFilterChip(String label, String? value) {
    final selected = _filterOrderStatus == value;
    Color color;
    if (value == '発送済み') {
      color = AppColors.done;
    } else if (value == '発送準備中') {
      color = AppColors.secondary;
    } else if (value == '注文受付済み') {
      color = AppColors.primary;
    } else if (value == 'キャンセル済み') {
      color = Colors.grey;
    } else {
      color = AppColors.primary;
    }
    return GestureDetector(
      onTap: () => setState(() => _filterOrderStatus = value),
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

  String _buildOrderCsv(List<OrderStatusEntry> rows) {
    final lines = ['Email,商品名,注文番号,時間,ステータス'];
    for (final r in rows) {
      lines.add([
        _csvField(r.accountEmail),
        _csvField(r.productTitle),
        _csvField(r.orderNum),
        _csvField(r.time),
        _csvField(r.status),
      ].join(','));
    }
    return lines.join('\r\n');
  }

  void _copyOrderCsv(List<OrderStatusEntry> rows) {
    Clipboard.setData(ClipboardData(text: _buildOrderCsv(rows)));
    _snack('Đã copy ${rows.length} dòng CSV');
  }

  Future<void> _exportOrderCsvFile(List<OrderStatusEntry> rows) async {
    final csv = _buildOrderCsv(rows);
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
    final file = File('${Directory.systemTemp.path}/order_status_$ts.csv');
    const bom = [0xEF, 0xBB, 0xBF];
    await file.writeAsBytes([...bom, ...utf8.encode(csv)]);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv; charset=utf-8')],
      subject: 'Order Status $ts',
    );
  }

  Widget _buildOrderTable(List<OrderStatusEntry> rows) {
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
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: const Row(
            children: [
              Expanded(
                flex: 3,
                child: Text('Email',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
              Expanded(
                flex: 3,
                child: Text('Hàng',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
              Expanded(
                flex: 2,
                child: Text('Thời gian',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
              SizedBox(
                width: 76,
                child: Text('Trạng thái',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rows.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppColors.divider),
            itemBuilder: (_, i) => _buildOrderRow(rows[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderRow(OrderStatusEntry e) {
    Color statusColor;
    if (e.isShipped) {
      statusColor = AppColors.done;
    } else if (e.isPreparing) {
      statusColor = AppColors.secondary;
    } else if (e.isReceived) {
      statusColor = AppColors.primary;
    } else if (e.isCancelled) {
      statusColor = Colors.grey;
    } else {
      statusColor = AppColors.warning;
    }

    // Rút gọn label cho badge
    String shortStatus;
    if (e.status == '注文受付済み') {
      shortStatus = '受付済み';
    } else if (e.status == '発送準備中') {
      shortStatus = '準備中';
    } else if (e.status == '発送済み') {
      shortStatus = '発送済み';
    } else if (e.status == 'キャンセル済み') {
      shortStatus = 'キャンセル';
    } else {
      shortStatus = e.status;
    }

    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(
            text: '${e.accountEmail},${e.productTitle},${e.orderNum},${e.time},${e.status}'));
        _snack('Copied row', duration: const Duration(seconds: 1));
      },
      child: Container(
        color: e.isShipped ? AppColors.done.withAlpha(15) : Colors.transparent,
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
              width: 76,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor.withAlpha(120)),
                ),
                child: Text(
                  shortStatus,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
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

  // ─── Shipping section (発送済み tracking info) ──────────────────────────────

  Widget _buildShippingSection(AppProvider p) {
    final rows = p.shippingResults;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '🚚 発送済み — Mã vận chuyển',
              style: TextStyle(
                  color: AppColors.done,
                  fontWeight: FontWeight.bold,
                  fontSize: 14),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy_all,
                  color: AppColors.textSecondary, size: 18),
              tooltip: 'Copy CSV',
              onPressed: () => _copyShippingCsv(rows),
            ),
            IconButton(
              icon: const Icon(Icons.ios_share,
                  color: AppColors.accent, size: 18),
              tooltip: 'Export CSV file',
              onPressed: () => _exportShippingCsvFile(rows),
            ),
            IconButton(
              icon: const Icon(Icons.save_alt,
                  color: AppColors.done, size: 18),
              tooltip: 'Save snapshot vào History',
              onPressed: () async {
                final s = await p.saveSnapshotFromCurrentResults(SnapshotType.shipping);
                _snack(s != null
                    ? 'Đã lưu snapshot (${s.count} entries)'
                    : 'Không có kết quả để lưu');
              },
            ),
            IconButton(
              icon: const Icon(Icons.history,
                  color: AppColors.secondary, size: 18),
              tooltip: 'Xem History',
              onPressed: () => _showHistorySheet(SnapshotType.shipping),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.error, size: 18),
              tooltip: 'Xóa',
              onPressed: () => p.clearShippingResults(),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.done.withAlpha(60)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.done.withAlpha(25),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: const Row(
                  children: [
                    Expanded(flex: 3, child: Text('Email', style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold))),
                    Expanded(flex: 2, child: Text('送り状番号', style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold))),
                    Expanded(flex: 3, child: Text('お届け先', style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold))),
                    SizedBox(width: 40),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.divider),
              ...rows.asMap().entries.map((e) => Column(
                children: [
                  if (e.key > 0) const Divider(height: 1, color: AppColors.divider),
                  _buildShippingRow(e.value),
                ],
              )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShippingRow(ShippingEntry e) {
    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(
            text: '${e.accountEmail},${e.trackingNumDisplay},${e.deliveryInfo},${e.trackingLink}'));
        _snack('Copied', duration: const Duration(seconds: 1));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.accountEmail,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                  if (e.productTitle.isNotEmpty)
                    Text(e.productTitle,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: () => Clipboard.setData(
                    ClipboardData(text: e.trackingNum)),
                child: Text(
                  e.trackingNumDisplay.isEmpty ? '—' : e.trackingNumDisplay,
                  style: const TextStyle(
                      color: AppColors.done,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                e.deliveryInfo.isEmpty ? '—' : e.deliveryInfo,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (e.trackingLink.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.open_in_browser,
                    color: AppColors.accent, size: 18),
                tooltip: '配送状況を確認する',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () async {
                  final uri = Uri.parse(e.trackingLink);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              )
            else
              const SizedBox(width: 32),
          ],
        ),
      ),
    );
  }

  String _buildShippingCsv(List<ShippingEntry> rows) {
    final lines = ['Email,送り状番号,お届け先,注文番号,配送確認リンク'];
    for (final r in rows) {
      lines.add('${_csvField(r.accountEmail)},${_csvField(r.trackingNumDisplay)},${_csvField(r.deliveryInfo)},${_csvField(r.orderNum)},${_csvField(r.trackingLink)}');
    }
    return lines.join('\r\n');
  }

  void _copyShippingCsv(List<ShippingEntry> rows) {
    Clipboard.setData(ClipboardData(text: _buildShippingCsv(rows)));
    _snack('Đã copy ${rows.length} dòng CSV');
  }

  Future<void> _exportShippingCsvFile(List<ShippingEntry> rows) async {
    final csv = _buildShippingCsv(rows);
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
    final file = File('${Directory.systemTemp.path}/shipping_$ts.csv');
    const bom = [0xEF, 0xBB, 0xBF];
    await file.writeAsBytes([...bom, ...utf8.encode(csv)]);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv; charset=utf-8')],
      subject: 'Shipping $ts',
    );
  }

  // ─── History (snapshots) ─────────────────────────────────────────────────

  void _showHistorySheet(SnapshotType type) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _HistorySheet(
        type: type,
        downloadSnapshot: _downloadSnapshot,
      ),
    );
  }

  Future<void> _downloadSnapshot(ResultSnapshot s) async {
    final ts = s.createdAt.toIso8601String().replaceAll(':', '-').substring(0, 19);
    final typeStr = s.type.name;
    final csv = _buildSnapshotCsv(s);
    final file = File('${Directory.systemTemp.path}/${typeStr}_snapshot_$ts.csv');
    const bom = [0xEF, 0xBB, 0xBF];
    await file.writeAsBytes([...bom, ...utf8.encode(csv)]);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv; charset=utf-8')],
      subject: '${typeStr} snapshot ${s.keyword.isEmpty ? "(all)" : s.keyword}',
    );
  }

  String _buildSnapshotCsv(ResultSnapshot s) {
    String f(dynamic v) => _csvField((v ?? '').toString());
    final lines = <String>[];
    switch (s.type) {
      case SnapshotType.lottery:
        lines.add('Email,商品名,日時,結果');
        for (final e in s.entries) {
          lines.add([f(e['accountEmail']), f(e['productTitle']), f(e['time']), f(e['result'])].join(','));
        }
        break;
      case SnapshotType.order:
        lines.add('Email,商品名,注文番号,時間,ステータス');
        for (final e in s.entries) {
          lines.add([f(e['accountEmail']), f(e['productTitle']), f(e['orderNum']), f(e['time']), f(e['status'])].join(','));
        }
        break;
      case SnapshotType.shipping:
        lines.add('Email,送り状番号,お届け先,注文番号,配送確認リンク');
        for (final e in s.entries) {
          lines.add([f(e['accountEmail']), f(e['trackingNumDisplay']), f(e['deliveryInfo']), f(e['orderNum']), f(e['trackingLink'])].join(','));
        }
        break;
    }
    return lines.join('\r\n');
  }
}

class _HistorySheet extends StatefulWidget {
  final SnapshotType type;
  final Future<void> Function(ResultSnapshot) downloadSnapshot;
  const _HistorySheet({required this.type, required this.downloadSnapshot});

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _typeLabel() {
    switch (widget.type) {
      case SnapshotType.lottery: return 'Lottery';
      case SnapshotType.order: return 'Order';
      case SnapshotType.shipping: return 'Shipping';
    }
  }

  String _formatTime(DateTime t) {
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (ctx, p, _) {
        final q = _searchCtrl.text.trim().toLowerCase();
        final all = p.snapshotsByType(widget.type);
        final filtered = q.isEmpty
            ? all
            : all.where((s) => s.keyword.toLowerCase().contains(q)).toList();
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollCtrl) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.history, color: AppColors.secondary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '${_typeLabel()} History (${all.length})',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (all.isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(Icons.delete_sweep,
                            color: AppColors.error, size: 18),
                        label: const Text('Clear all',
                            style: TextStyle(color: AppColors.error, fontSize: 12)),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              backgroundColor: AppColors.card,
                              title: const Text('Xóa tất cả snapshot?',
                                  style: TextStyle(color: Colors.white)),
                              content: Text(
                                  'Sẽ xóa ${all.length} snapshot ${_typeLabel()}. Không thể hoàn tác.',
                                  style: const TextStyle(color: AppColors.textSecondary)),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Hủy')),
                                ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.error),
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('Xóa')),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await p.clearSnapshotsByType(widget.type);
                          }
                        },
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Tìm theo keyword...',
                    hintStyle: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                    prefixIcon: const Icon(Icons.search,
                        color: AppColors.textSecondary, size: 18),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                color: AppColors.textSecondary, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          all.isEmpty
                              ? 'Chưa có snapshot nào'
                              : 'Không khớp keyword "${_searchCtrl.text}"',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final s = filtered[i];
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _formatTime(s.createdAt),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        s.keyword.isEmpty
                                            ? '(no keyword)'
                                            : '🔍 ${s.keyword}',
                                        style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 11),
                                      ),
                                      Text(
                                        '${s.count} entries',
                                        style: const TextStyle(
                                            color: AppColors.secondary, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.ios_share,
                                      color: AppColors.accent, size: 20),
                                  tooltip: 'Download CSV',
                                  onPressed: () => widget.downloadSnapshot(s),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: AppColors.error, size: 20),
                                  tooltip: 'Xóa',
                                  onPressed: () => p.deleteSnapshot(s.id),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
