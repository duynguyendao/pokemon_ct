import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/account.dart';
import '../models/proxy.dart';
import '../models/filter_rule.dart';
import '../models/lottery_apply_entry.dart';
import '../models/lottery_result_entry.dart';
import '../models/order_status_entry.dart';
import '../models/result_snapshot.dart';
import '../models/shipping_entry.dart';
import '../services/storage_service.dart';

class AppProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();

  List<Account> _accounts = [];
  List<Proxy> _proxies = [];
  List<String> _groups = [];
  List<FilterRule> _filterRules = [];
  Map<String, String> _urlConfig = {};

  String _defaultPassword = '';
  bool _proxyEnabled = false;
  bool _fakeBrowser = true;
  bool _incognitoMode = false;
  bool _shortcut5gEnabled = true;
  bool _blockImages = false;
  String _otpSource = 'clipboard'; // 'clipboard' or 'gas'
  String _gasScriptUrl = '';
  String _gasSecretKey = '';
  String _targetProductName = '';
  int _typingMinDelay = 80;
  int _typingMaxDelay = 180;
  int _otpWatchdogSeconds = 60;
  final List<LotteryResultEntry> _lotteryResults = [];
  final List<OrderStatusEntry> _orderStatusResults = [];
  final List<ShippingEntry> _shippingResults = [];
  final List<LotteryApplyEntry> _lotteryApplyResults = [];
  List<ResultSnapshot> _snapshots = [];
  static const int _maxSnapshots = 100;
  bool _loaded = false;

  // Getters
  List<Account> get accounts => _accounts;
  List<Proxy> get proxies => _proxies;
  List<String> get groups => _groups;
  List<FilterRule> get filterRules => _filterRules;
  Map<String, String> get urlConfig => _urlConfig;
  String get loginUrl =>
      _urlConfig['loginUrl'] ?? 'https://www.pokemoncenter-online.com/login/';
  String get lotteryUrl => _urlConfig['lotteryUrl']?.isNotEmpty == true
      ? _urlConfig['lotteryUrl']!
      : 'https://www.pokemoncenter-online.com/lottery/';
  String get lotteryResultUrl => _urlConfig['lotteryResultUrl']?.isNotEmpty == true
      ? _urlConfig['lotteryResultUrl']!
      : 'https://www.pokemoncenter-online.com/lottery-history/';
  String get orderHistoryUrl => _urlConfig['orderHistoryUrl']?.isNotEmpty == true
      ? _urlConfig['orderHistoryUrl']!
      : 'https://www.pokemoncenter-online.com/order-history/';
  String get defaultPassword => _defaultPassword;
  bool get proxyEnabled => _proxyEnabled;
  bool get fakeBrowser => _fakeBrowser;
  bool get incognitoMode => _incognitoMode;
  bool get shortcut5gEnabled => _shortcut5gEnabled;
  bool get blockImages => _blockImages;
  String get otpSource => _otpSource;
  bool get isClipboardOtpMode => _otpSource == 'clipboard';
  bool get isGasOtpMode => _otpSource == 'gas';
  String get gasScriptUrl => _gasScriptUrl;
  String get gasSecretKey => _gasSecretKey;
  String get targetProductName => _targetProductName;
  int get typingMinDelay => _typingMinDelay;
  int get typingMaxDelay => _typingMaxDelay;
  int get otpWatchdogSeconds => _otpWatchdogSeconds;
  List<LotteryResultEntry> get lotteryResults => List.unmodifiable(_lotteryResults);
  List<OrderStatusEntry> get orderStatusResults => List.unmodifiable(_orderStatusResults);
  List<ShippingEntry> get shippingResults => List.unmodifiable(_shippingResults);
  List<LotteryApplyEntry> get lotteryApplyResults => List.unmodifiable(_lotteryApplyResults);
  List<ResultSnapshot> get snapshots => List.unmodifiable(_snapshots);
  List<ResultSnapshot> snapshotsByType(SnapshotType type) =>
      _snapshots.where((s) => s.type == type).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  bool get loaded => _loaded;

  int get todoCount => _accounts.where((a) => a.status == 'todo').length;
  int get doneCount => _accounts.where((a) => a.status == 'done').length;

  Proxy? getProxyById(String? id) => id == null
      ? null
      : _proxies.cast<Proxy?>().firstWhere(
          (p) => p?.id == id,
          orElse: () => null,
        );

  Proxy? get nextProxy {
    final enabled = _proxies.where((p) => p.enabled).toList();
    if (enabled.isEmpty) return null;
    enabled.sort((a, b) => a.usageCount.compareTo(b.usageCount));
    return enabled.first;
  }

  Future<void> load() async {
    _accounts = await _storage.loadAccounts();
    _proxies = await _storage.loadProxies();
    _groups = await _storage.loadGroups();
    _filterRules = await _storage.loadFilterRules();
    _urlConfig = await _storage.loadUrlConfig();
    _defaultPassword = await _storage.loadDefaultPassword();
    _proxyEnabled = await _storage.loadProxyEnabled();
    _fakeBrowser = await _storage.loadFakeBrowser();
    _incognitoMode = await _storage.loadIncognitoMode();
    _shortcut5gEnabled = await _storage.loadShortcut5gEnabled();
    _blockImages = await _storage.loadBlockImages();
    _otpSource = await _storage.loadOtpSource();
    _gasScriptUrl = await _storage.loadGasScriptUrl();
    _gasSecretKey = await _storage.loadGasSecretKey();
    _targetProductName = await _storage.loadTargetProductName();
    _typingMinDelay = await _storage.loadTypingMinDelay();
    _typingMaxDelay = await _storage.loadTypingMaxDelay();
    _otpWatchdogSeconds = await _storage.loadOtpWatchdogSeconds();
    _snapshots = await _storage.loadSnapshots();
    _lotteryResults.addAll(await _storage.loadLotteryResults());
    _orderStatusResults.addAll(await _storage.loadOrderStatusResults());
    _shippingResults.addAll(await _storage.loadShippingResults());
    _lotteryApplyResults.addAll(await _storage.loadLotteryApplyResults());
    _loaded = true;
    notifyListeners();
  }

  // --- Accounts ---

  Future<void> addAccounts(List<Account> newAccounts) async {
    _accounts.addAll(newAccounts);
    await _storage.saveAccounts(_accounts);
    notifyListeners();
  }

  Future<void> updateAccount(Account updated) async {
    final idx = _accounts.indexWhere((a) => a.id == updated.id);
    if (idx >= 0) {
      _accounts[idx] = updated;
      await _storage.saveAccounts(_accounts);
      notifyListeners();
    }
  }

  Future<void> deleteAccount(String id) async {
    _accounts.removeWhere((a) => a.id == id);
    await _storage.saveAccounts(_accounts);
    notifyListeners();
  }

  Future<void> deleteAccounts(List<String> ids) async {
    _accounts.removeWhere((a) => ids.contains(a.id));
    await _storage.saveAccounts(_accounts);
    notifyListeners();
  }

  Future<void> toggleStatus(String id) async {
    final idx = _accounts.indexWhere((a) => a.id == id);
    if (idx >= 0) {
      _accounts[idx] = _accounts[idx].copyWith(
        status: _accounts[idx].status == 'todo' ? 'done' : 'todo',
      );
      await _storage.saveAccounts(_accounts);
      notifyListeners();
    }
  }

  Future<void> batchSetStatus(List<String> ids, String status) async {
    for (final id in ids) {
      final idx = _accounts.indexWhere((a) => a.id == id);
      if (idx >= 0) {
        _accounts[idx] = _accounts[idx].copyWith(status: status);
      }
    }
    await _storage.saveAccounts(_accounts);
    notifyListeners();
  }

  List<Account> parseAccountsText(String text, {String? group}) {
    final lines = text.trim().split('\n');
    final result = <Account>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split(':');
      if (parts.length >= 2) {
        final email = parts[0].trim();
        final password = parts.sublist(1).join(':').trim();
        result.add(
          Account(
            email: email,
            password: password.isNotEmpty ? password : _defaultPassword,
            group: group,
          ),
        );
      }
    }
    return result;
  }

  // --- Groups ---

  Future<void> addGroup(String name) async {
    if (!_groups.contains(name)) {
      _groups.add(name);
      await _storage.saveGroups(_groups);
      notifyListeners();
    }
  }

  Future<void> deleteGroup(String name) async {
    _groups.remove(name);
    for (final a in _accounts) {
      if (a.group == name) a.group = null;
    }
    await _storage.saveGroups(_groups);
    await _storage.saveAccounts(_accounts);
    notifyListeners();
  }

  // --- Proxies ---

  Future<void> addProxy(Proxy proxy) async {
    _proxies.add(proxy);
    await _storage.saveProxies(_proxies);
    notifyListeners();
  }

  Future<void> updateProxy(Proxy updated) async {
    final idx = _proxies.indexWhere((p) => p.id == updated.id);
    if (idx >= 0) {
      _proxies[idx] = updated;
      await _storage.saveProxies(_proxies);
      notifyListeners();
    }
  }

  Future<void> deleteProxy(String id) async {
    _proxies.removeWhere((p) => p.id == id);
    await _storage.saveProxies(_proxies);
    notifyListeners();
  }

  Future<void> markProxyUsed(String id) async {
    final idx = _proxies.indexWhere((p) => p.id == id);
    if (idx >= 0) {
      final p = _proxies[idx];
      _proxies[idx] = p.copyWith(
        usageCount: p.usageCount + 1,
        lastUsed: DateTime.now(),
      );
      await _storage.saveProxies(_proxies);
      notifyListeners();
    }
  }

  // --- Settings ---

  Future<void> setProxyEnabled(bool v) async {
    _proxyEnabled = v;
    await _storage.saveProxyEnabled(v);
    notifyListeners();
  }

  Future<void> setFakeBrowser(bool v) async {
    _fakeBrowser = v;
    await _storage.saveFakeBrowser(v);
    notifyListeners();
  }

  Future<void> setIncognitoMode(bool v) async {
    _incognitoMode = v;
    await _storage.saveIncognitoMode(v);
    notifyListeners();
  }

  Future<void> setShortcut5gEnabled(bool v) async {
    _shortcut5gEnabled = v;
    await _storage.saveShortcut5gEnabled(v);
    notifyListeners();
  }

  Future<void> setBlockImages(bool v) async {
    _blockImages = v;
    await _storage.saveBlockImages(v);
    notifyListeners();
  }

  Future<void> setTypingMinDelay(int v) async {
    _typingMinDelay = v.clamp(30, 500);
    await _storage.saveTypingMinDelay(_typingMinDelay);
    notifyListeners();
  }

  Future<void> setTypingMaxDelay(int v) async {
    _typingMaxDelay = v.clamp(30, 500);
    await _storage.saveTypingMaxDelay(_typingMaxDelay);
    notifyListeners();
  }

  Future<void> setOtpWatchdogSeconds(int v) async {
    _otpWatchdogSeconds = v.clamp(10, 300);
    await _storage.saveOtpWatchdogSeconds(_otpWatchdogSeconds);
    notifyListeners();
  }

  Future<void> setOtpSource(String source) async {
    _otpSource = source;
    await _storage.saveOtpSource(source);
    notifyListeners();
  }

  Future<void> setTargetProductName(String name) async {
    _targetProductName = name;
    await _storage.saveTargetProductName(name);
    notifyListeners();
  }

  void addLotteryResult(LotteryResultEntry entry) {
    _lotteryResults.removeWhere((e) => e.accountEmail == entry.accountEmail);
    _lotteryResults.add(entry);
    unawaited(_storage.saveLotteryResults(_lotteryResults));
    notifyListeners();
  }

  void clearLotteryResults() {
    _lotteryResults.clear();
    unawaited(_storage.saveLotteryResults(_lotteryResults));
    notifyListeners();
  }

  void addOrderStatusResult(OrderStatusEntry entry) {
    _orderStatusResults.removeWhere((e) => e.accountEmail == entry.accountEmail);
    _orderStatusResults.add(entry);
    unawaited(_storage.saveOrderStatusResults(_orderStatusResults));
    notifyListeners();
  }

  void clearOrderStatusResults() {
    _orderStatusResults.clear();
    unawaited(_storage.saveOrderStatusResults(_orderStatusResults));
    notifyListeners();
  }

  void addShippingResult(ShippingEntry entry) {
    _shippingResults.removeWhere((e) => e.accountEmail == entry.accountEmail);
    _shippingResults.add(entry);
    unawaited(_storage.saveShippingResults(_shippingResults));
    notifyListeners();
  }

  void clearShippingResults() {
    _shippingResults.clear();
    unawaited(_storage.saveShippingResults(_shippingResults));
    notifyListeners();
  }

  void addLotteryApplyResult(LotteryApplyEntry entry) {
    _lotteryApplyResults.removeWhere((e) => e.accountEmail == entry.accountEmail);
    _lotteryApplyResults.add(entry);
    unawaited(_storage.saveLotteryApplyResults(_lotteryApplyResults));
    notifyListeners();
  }

  void clearLotteryApplyResults() {
    _lotteryApplyResults.clear();
    unawaited(_storage.saveLotteryApplyResults(_lotteryApplyResults));
    notifyListeners();
  }

  // --- Result snapshots (history, max 100, persisted) ---

  Future<ResultSnapshot?> saveSnapshotFromCurrentResults(
    SnapshotType type, {
    String? keywordOverride,
  }) async {
    final keyword = keywordOverride ?? _targetProductName;
    List<Map<String, dynamic>> entries;
    switch (type) {
      case SnapshotType.lottery:
        if (_lotteryResults.isEmpty) return null;
        entries = _lotteryResults.map((e) => e.toJson()).toList();
        break;
      case SnapshotType.order:
        if (_orderStatusResults.isEmpty) return null;
        entries = _orderStatusResults.map((e) => e.toJson()).toList();
        break;
      case SnapshotType.shipping:
        if (_shippingResults.isEmpty) return null;
        entries = _shippingResults.map((e) => e.toJson()).toList();
        break;
      case SnapshotType.lotteryApply:
        if (_lotteryApplyResults.isEmpty) return null;
        entries = _lotteryApplyResults.map((e) => e.toJson()).toList();
        break;
    }
    final snapshot = ResultSnapshot(
      type: type,
      keyword: keyword,
      entries: entries,
    );
    _snapshots.add(snapshot);
    _enforceSnapshotLimit();
    await _storage.saveSnapshots(_snapshots);
    notifyListeners();
    return snapshot;
  }

  void _enforceSnapshotLimit() {
    if (_snapshots.length <= _maxSnapshots) return;
    _snapshots.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    while (_snapshots.length > _maxSnapshots) {
      _snapshots.removeAt(0);
    }
  }

  Future<void> deleteSnapshot(String id) async {
    _snapshots.removeWhere((s) => s.id == id);
    await _storage.saveSnapshots(_snapshots);
    notifyListeners();
  }

  Future<void> clearSnapshotsByType(SnapshotType type) async {
    _snapshots.removeWhere((s) => s.type == type);
    await _storage.saveSnapshots(_snapshots);
    notifyListeners();
  }

  Future<void> setDefaultPassword(String pw) async {
    _defaultPassword = pw;
    await _storage.saveDefaultPassword(pw);
    notifyListeners();
  }

  // --- Filter Rules ---

  Future<void> saveFilterRules(List<FilterRule> rules) async {
    _filterRules = rules;
    await _storage.saveFilterRules(rules);
    notifyListeners();
  }

  // --- URL Config ---

  Future<void> saveUrlConfig(Map<String, String> config) async {
    _urlConfig = config;
    await _storage.saveUrlConfig(config);
    notifyListeners();
  }

  // --- GAS Script ---

  Future<void> setGasScriptUrl(String url) async {
    _gasScriptUrl = url;
    await _storage.saveGasScriptUrl(url);
    notifyListeners();
  }

  Future<void> setGasSecretKey(String key) async {
    _gasSecretKey = key;
    await _storage.saveGasSecretKey(key);
    notifyListeners();
  }

  Future<void> setAllAccountsMode(AccountMode mode) async {
    for (var i = 0; i < _accounts.length; i++) {
      _accounts[i] = _accounts[i].copyWith(mode: mode);
    }
    await _storage.saveAccounts(_accounts);
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
