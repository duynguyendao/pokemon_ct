import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/account.dart';
import '../models/proxy.dart';
import '../models/filter_rule.dart';
import '../models/result_snapshot.dart';

class StorageService {
  static const _accountsKey = 'accounts';
  static const _proxiesKey = 'proxies';
  static const _groupsKey = 'groups';
  static const _filterRulesKey = 'filterRules';
  static const _imapConfigKey = 'imapConfig';
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

  Future<Map<String, String>> loadImapConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_imapConfigKey);
    if (raw == null) return _defaultImapConfig();
    return Map<String, String>.from(jsonDecode(raw) as Map);
  }

  Future<void> saveImapConfig(Map<String, String> config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_imapConfigKey, jsonEncode(config));
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

  Map<String, String> _defaultImapConfig() => {
    'host': 'imap.gmail.com',
    'port': '993',
    'username': 'duynguyenpk8793@gmail.com',
    'password': '',
    'pollInterval': '1',
  };

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

  Map<String, String> _defaultUrlConfig() => {
    'loginUrl': 'https://www.pokemoncenter-online.com/login/',
    'lotteryUrl': 'https://www.pokemoncenter-online.com/lottery/',
    'lotteryResultUrl': 'https://www.pokemoncenter-online.com/lottery-history/',
    'orderHistoryUrl': 'https://www.pokemoncenter-online.com/order-history/',
  };
}
