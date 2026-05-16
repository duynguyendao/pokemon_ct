import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/account.dart';
import '../models/proxy.dart';
import '../models/filter_rule.dart';
import '../models/result_snapshot.dart';
import '../models/lottery_result_entry.dart';
import '../models/lottery_apply_entry.dart';
import '../models/order_status_entry.dart';
import '../models/shipping_entry.dart';

class StorageService {
  static const _accountsKey = 'accounts';
  static const _proxiesKey = 'proxies';
  static const _groupsKey = 'groups';
  static const _filterRulesKey = 'filterRules';
  static const _gasScriptUrlKey = 'gasScriptUrl';
  static const _gasSecretKeyKey = 'gasSecretKey';
  static const _urlConfigKey = 'urlConfig';
  static const _defaultPasswordKey = 'defaultPassword';
  static const _proxyEnabledKey = 'proxyEnabled';
  static const _fakeBrowserKey = 'fakeBrowser';
  static const _incognitoModeKey = 'incognitoMode';
  static const _shortcut5gEnabledKey = 'shortcut5gEnabled';
  static const _otpSourceKey = 'otpSource';
  static const _targetProductNameKey = 'targetProductName';
  static const _blockImagesKey = 'blockImages';
  static const _typingMinDelayKey = 'typingMinDelay';
  static const _typingMaxDelayKey = 'typingMaxDelay';
  static const _otpWatchdogSecondsKey = 'otpWatchdogSeconds';
  static const _snapshotsKey = 'resultSnapshots';
  static const _lotteryResultsKey = 'lotteryResults';
  static const _orderStatusResultsKey = 'orderStatusResults';
  static const _shippingResultsKey = 'shippingResults';
  static const _lotteryApplyResultsKey = 'lotteryApplyResults';
  static const _lotteryApplyKeywordsKey = 'lotteryApplyKeywords';

  Future<List<Account>> loadAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_accountsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => Account.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveAccounts(List<Account> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _accountsKey,
      jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
  }

  Future<List<Proxy>> loadProxies() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_proxiesKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => Proxy.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveProxies(List<Proxy> proxies) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _proxiesKey,
      jsonEncode(proxies.map((p) => p.toJson()).toList()),
    );
  }

  Future<List<String>> loadGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_groupsKey);
    return raw ?? [];
  }

  Future<void> saveGroups(List<String> groups) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_groupsKey, groups);
  }

  Future<List<FilterRule>> loadFilterRules() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_filterRulesKey);
    if (raw == null) return _defaultRules();
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => FilterRule.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveFilterRules(List<FilterRule> rules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _filterRulesKey,
      jsonEncode(rules.map((r) => r.toJson()).toList()),
    );
  }

  Future<String> loadGasScriptUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_gasScriptUrlKey) ?? '';
  }

  Future<void> saveGasScriptUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_gasScriptUrlKey, url);
  }

  Future<String> loadGasSecretKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_gasSecretKeyKey) ?? '';
  }

  Future<void> saveGasSecretKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_gasSecretKeyKey, key);
  }

  Future<String> loadDefaultPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_defaultPasswordKey) ?? '';
  }

  Future<void> saveDefaultPassword(String pw) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultPasswordKey, pw);
  }

  Future<bool> loadProxyEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_proxyEnabledKey) ?? false;
  }

  Future<void> saveProxyEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_proxyEnabledKey, v);
  }

  Future<bool> loadFakeBrowser() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_fakeBrowserKey) ?? true;
  }

  Future<void> saveFakeBrowser(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_fakeBrowserKey, v);
  }

  Future<bool> loadIncognitoMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_incognitoModeKey) ?? false;
  }

  Future<void> saveIncognitoMode(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_incognitoModeKey, v);
  }

  Future<bool> loadShortcut5gEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_shortcut5gEnabledKey) ?? true;
  }

  Future<void> saveShortcut5gEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_shortcut5gEnabledKey, v);
  }

  Future<String> loadOtpSource() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_otpSourceKey) ?? 'clipboard';
  }

  Future<void> saveOtpSource(String source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_otpSourceKey, source);
  }

  Future<String> loadTargetProductName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_targetProductNameKey) ?? '';
  }

  Future<void> saveTargetProductName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_targetProductNameKey, name);
  }

  Future<bool> loadBlockImages() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_blockImagesKey) ?? false;
  }

  Future<void> saveBlockImages(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_blockImagesKey, v);
  }

  Future<int> loadTypingMinDelay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_typingMinDelayKey) ?? 80;
  }

  Future<void> saveTypingMinDelay(int v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_typingMinDelayKey, v);
  }

  Future<int> loadTypingMaxDelay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_typingMaxDelayKey) ?? 180;
  }

  Future<void> saveTypingMaxDelay(int v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_typingMaxDelayKey, v);
  }

  Future<int> loadOtpWatchdogSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_otpWatchdogSecondsKey) ?? 60;
  }

  Future<void> saveOtpWatchdogSeconds(int v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_otpWatchdogSecondsKey, v);
  }

  List<FilterRule> _defaultRules() => [
    FilterRule(
      type: FilterType.sender,
      pattern: 'pokemoncenter-online',
      extractPattern: r'【パスコード】\s*(\d{6})',
      enabled: true,
    ),
    FilterRule(
      type: FilterType.subject,
      pattern: 'ログイン',
      extractPattern: r'【パスコード】\s*(\d{6})',
      enabled: true,
    ),
  ];

  Future<List<String>> loadLotteryApplyKeywords() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_lotteryApplyKeywordsKey) ?? ['', '', ''];
  }

  Future<void> saveLotteryApplyKeywords(List<String> keywords) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_lotteryApplyKeywordsKey, keywords);
  }

  Future<Map<String, String>> loadUrlConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_urlConfigKey);
    if (raw == null) return _defaultUrlConfig();
    return Map<String, String>.from(jsonDecode(raw) as Map);
  }

  Future<void> saveUrlConfig(Map<String, String> config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlConfigKey, jsonEncode(config));
  }

  Future<List<ResultSnapshot>> loadSnapshots() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_snapshotsKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ResultSnapshot.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSnapshots(List<ResultSnapshot> snapshots) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _snapshotsKey,
      jsonEncode(snapshots.map((s) => s.toJson()).toList()),
    );
  }

  Future<List<LotteryResultEntry>> loadLotteryResults() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lotteryResultsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => LotteryResultEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveLotteryResults(List<LotteryResultEntry> rows) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lotteryResultsKey,
      jsonEncode(rows.map((e) => e.toJson()).toList()),
    );
  }

  Future<List<OrderStatusEntry>> loadOrderStatusResults() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_orderStatusResultsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => OrderStatusEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveOrderStatusResults(List<OrderStatusEntry> rows) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _orderStatusResultsKey,
      jsonEncode(rows.map((e) => e.toJson()).toList()),
    );
  }

  Future<List<ShippingEntry>> loadShippingResults() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_shippingResultsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => ShippingEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveShippingResults(List<ShippingEntry> rows) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _shippingResultsKey,
      jsonEncode(rows.map((e) => e.toJson()).toList()),
    );
  }

  Future<List<LotteryApplyEntry>> loadLotteryApplyResults() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lotteryApplyResultsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => LotteryApplyEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveLotteryApplyResults(List<LotteryApplyEntry> rows) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lotteryApplyResultsKey,
      jsonEncode(rows.map((e) => e.toJson()).toList()),
    );
  }

  Map<String, String> _defaultUrlConfig() => {
    'loginUrl': 'https://www.pokemoncenter-online.com/login/',
    'lotteryUrl': 'https://www.pokemoncenter-online.com/lottery/',
    'lotteryResultUrl': 'https://www.pokemoncenter-online.com/lottery-history/',
    'orderHistoryUrl': 'https://www.pokemoncenter-online.com/order-history/',
  };
}
