import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/account.dart';
import '../models/proxy.dart';
import '../models/filter_rule.dart';

class StorageService {
  static const _accountsKey = 'accounts';
  static const _proxiesKey = 'proxies';
  static const _groupsKey = 'groups';
  static const _filterRulesKey = 'filterRules';
  static const _imapConfigKey = 'imapConfig';
  static const _defaultPasswordKey = 'defaultPassword';
  static const _proxyEnabledKey = 'proxyEnabled';
  static const _fakeBrowserKey = 'fakeBrowser';

  Future<List<Account>> loadAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_accountsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => Account.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveAccounts(List<Account> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountsKey, jsonEncode(accounts.map((a) => a.toJson()).toList()));
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
    await prefs.setString(_proxiesKey, jsonEncode(proxies.map((p) => p.toJson()).toList()));
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
    return list.map((e) => FilterRule.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveFilterRules(List<FilterRule> rules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_filterRulesKey, jsonEncode(rules.map((r) => r.toJson()).toList()));
  }

  Future<Map<String, String>> loadImapConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_imapConfigKey);
    if (raw == null) return {};
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

  List<FilterRule> _defaultRules() => [
        FilterRule(
          type: FilterType.sender,
          pattern: 'pokemon-center',
          extractPattern: r'\b(\d{6})\b',
          enabled: true,
        ),
        FilterRule(
          type: FilterType.subject,
          pattern: '認証',
          extractPattern: r'\b(\d{6})\b',
          enabled: true,
        ),
      ];
}
