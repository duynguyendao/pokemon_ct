import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/account.dart';
import '../models/proxy.dart';
import '../models/otp_entry.dart';
import '../models/filter_rule.dart';
import '../services/storage_service.dart';
import '../services/imap_service.dart';
import '../services/background_service.dart';
export '../services/imap_service.dart' show EmailSearchResult;

class AppProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final ImapService _imap = ImapService();

  List<Account> _accounts = [];
  List<Proxy> _proxies = [];
  List<String> _groups = [];
  List<FilterRule> _filterRules = [];
  List<OtpEntry> _otpHistory = [];
  final Map<String, OtpEntry> _latestOtpByRecipient = {};
  OtpEntry? _latestOtpWithoutRecipient;
  Map<String, String> _imapConfig = {};
  Map<String, String> _urlConfig = {};

  String _defaultPassword = '';
  bool _proxyEnabled = false;
  bool _fakeBrowser = true;
  bool _imapRunning = false;
  bool _imapStarting = false;
  bool _imapStopping = false;
  String? _imapError;
  bool _loaded = false;
  Future<void>? _imapStartFuture;

  StreamSubscription<OtpEntry>? _otpSub;
  Timer? _bgOtpPollingTimer;

  // Getters
  List<Account> get accounts => _accounts;
  List<Proxy> get proxies => _proxies;
  List<String> get groups => _groups;
  List<FilterRule> get filterRules => _filterRules;
  List<OtpEntry> get otpHistory => _otpHistory;
  Stream<OtpEntry> get otpStream => _imap.otpStream;
  Map<String, String> get imapConfig => _imapConfig;
  Map<String, String> get urlConfig => _urlConfig;
  String get loginUrl =>
      _urlConfig['loginUrl'] ?? 'https://www.pokemoncenter-online.com/login/';
  String get lotteryUrl => _urlConfig['lotteryUrl'] ?? '';
  String get lotteryResultUrl => _urlConfig['lotteryResultUrl'] ?? '';
  String get defaultPassword => _defaultPassword;
  bool get proxyEnabled => _proxyEnabled;
  bool get fakeBrowser => _fakeBrowser;
  bool get imapRunning => _imapRunning && _imap.isRunning;
  bool get imapStarting => _imapStarting;
  bool get imapStopping => _imapStopping;
  String? get imapError => _imapError;
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
    _imapConfig = await _storage.loadImapConfig();
    _urlConfig = await _storage.loadUrlConfig();
    _defaultPassword = await _storage.loadDefaultPassword();
    _proxyEnabled = await _storage.loadProxyEnabled();
    _fakeBrowser = await _storage.loadFakeBrowser();
    _loaded = true;
    _imap.setRules(_filterRules);
    _setupOtpStream();
    notifyListeners();

    // Initialize background IMAP service
    await _initializeBackgroundService();

    // Auto-start IMAP if credentials are saved
    if (_imapConfig['password']?.isNotEmpty == true) {
      unawaited(startImap());
    }
  }

  Future<void> _initializeBackgroundService() async {
    final bgService = BackgroundServiceManager();
    try {
      await bgService.initializeBackground();

      if (_imapConfig['password']?.isNotEmpty == true) {
        await bgService.saveImapConfig(
          host: _imapConfig['host'] ?? '',
          port: int.tryParse(_imapConfig['port'] ?? '') ?? 993,
          username: _imapConfig['username'] ?? '',
          password: _imapConfig['password'] ?? '',
        );
      }
    } catch (e) {
      // Silently fail - background service is optional
    }
  }

  void _setupOtpStream() {
    _otpSub?.cancel();
    _otpSub = _imap.otpStream.listen((otp) {
      _cacheOtp(otp);
      if (!_isDuplicateOtp(otp)) {
        _otpHistory.insert(0, otp);
        if (_otpHistory.length > 50) _otpHistory.removeLast();
      }
      notifyListeners();
    });

    // Poll OTP from background service
    _bgOtpPollingTimer?.cancel();
    _bgOtpPollingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final bgService = BackgroundServiceManager();
      final bgStatus = await bgService.getBackgroundStatus();
      if (bgStatus != null) {
        final otp = OtpEntry(
          code: bgStatus['code'],
          recipient: bgStatus['recipient'],
          timestamp: bgStatus['timestamp'] ?? DateTime.now(),
        );
        if (!_isDuplicateOtp(otp)) {
          _cacheOtp(otp);
          _otpHistory.insert(0, otp);
          if (_otpHistory.length > 50) _otpHistory.removeLast();
          notifyListeners();
        }
        await bgService.clearBackgroundOtp();
      }
    });
  }

  void _cacheOtp(OtpEntry otp) {
    final recipient = otp.recipient?.trim() ?? '';
    if (recipient.isEmpty) {
      if (_latestOtpWithoutRecipient == null ||
          otp.timestamp.isAfter(_latestOtpWithoutRecipient!.timestamp)) {
        _latestOtpWithoutRecipient = otp;
      }
      return;
    }

    final key = _normalizeEmail(recipient);
    final current = _latestOtpByRecipient[key];
    if (current == null || otp.timestamp.isAfter(current.timestamp)) {
      _latestOtpByRecipient[key] = otp;
    }
  }

  bool _isDuplicateOtp(OtpEntry otp) {
    return _otpHistory.any(
      (e) =>
          e.code == otp.code &&
          otp.timestamp.difference(e.timestamp).abs().inSeconds < 30,
    );
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

  Future<void> setDefaultPassword(String pw) async {
    _defaultPassword = pw;
    await _storage.saveDefaultPassword(pw);
    notifyListeners();
  }

  // --- Filter Rules ---

  Future<void> saveFilterRules(List<FilterRule> rules) async {
    _filterRules = rules;
    _imap.setRules(rules);
    await _storage.saveFilterRules(rules);
    notifyListeners();
  }

  // --- URL Config ---

  Future<void> saveUrlConfig(Map<String, String> config) async {
    _urlConfig = config;
    await _storage.saveUrlConfig(config);
    notifyListeners();
  }

  // --- IMAP ---

  Future<void> saveImapConfig(Map<String, String> config) async {
    _imapConfig = config;
    await _storage.saveImapConfig(config);

    // Also save to background service
    if (config['password']?.isNotEmpty == true) {
      final bgService = BackgroundServiceManager();
      await bgService.saveImapConfig(
        host: config['host'] ?? '',
        port: int.tryParse(config['port'] ?? '') ?? 993,
        username: config['username'] ?? '',
        password: config['password'] ?? '',
      );
    }

    notifyListeners();
  }

  Future<bool> testImapConnection() async {
    final config = _buildImapConfig();
    if (config == null) return false;
    return _imap.testConnection(config);
  }

  Future<void> startImap() async {
    if (_imap.isRunning) {
      if (!_imapRunning) {
        _imapRunning = true;
        notifyListeners();
      }
      return;
    }

    final inFlight = _imapStartFuture;
    if (inFlight != null) return inFlight;

    final future = _startImapImpl();
    _imapStartFuture = future;
    future.whenComplete(() {
      if (identical(_imapStartFuture, future)) {
        _imapStartFuture = null;
      }
    });
    return future;
  }

  Future<void> _startImapImpl() async {
    final config = _buildImapConfig();
    if (config == null) return;
    _imapError = null;
    _imapStarting = true;
    notifyListeners();
    try {
      await _imap.start(config);
      _imapRunning = true;
    } catch (e) {
      _imapError = e.toString();
      _imapRunning = false;
    } finally {
      _imapStarting = false;
      notifyListeners();
    }
  }

  Future<bool> ensureOtpServerRunning() async {
    if (_imap.isRunning) {
      if (!_imapRunning) {
        _imapRunning = true;
        notifyListeners();
      }
      return true;
    }

    await startImap();
    return _imap.isRunning;
  }

  Future<void> stopImap() async {
    _imapStopping = true;
    _imapRunning = false; // immediate UI feedback
    notifyListeners();
    try {
      await _imap.stop();
    } finally {
      _imapStopping = false;
      notifyListeners();
    }
  }

  void clearOtpHistory() {
    _otpHistory.clear();
    _latestOtpByRecipient.clear();
    _latestOtpWithoutRecipient = null;
    notifyListeners();
  }

  Future<List<OtpEntry>> fetchOtpNow() async {
    final results = await _imap.fetchNow();
    for (final otp in results) {
      _cacheOtp(otp);
      if (!_isDuplicateOtp(otp)) {
        _otpHistory.insert(0, otp);
      }
    }
    if (_otpHistory.length > 50) {
      _otpHistory = _otpHistory.take(50).toList();
    }
    notifyListeners();
    return results;
  }

  Future<List<EmailSearchResult>> searchEmails({
    String subjectKeyword = '',
    String bodyKeyword = '',
    DateTime? from,
    DateTime? to,
    int maxMessages = 20,
  }) async {
    final config = _buildImapConfig();
    if (config == null) return [];
    return _imap.searchEmails(
      config: config,
      subjectKeyword: subjectKeyword,
      bodyKeyword: bodyKeyword,
      from: from,
      to: to,
      maxMessages: maxMessages,
    );
  }

  ImapConfig? _buildImapConfig() {
    final host = _imapConfig['host'];
    final portStr = _imapConfig['port'];
    final user = _imapConfig['username'];
    final pass = _imapConfig['password'];

    if (host == null || user == null || pass == null) return null;

    return ImapConfig(
      host: host,
      port: int.tryParse(portStr ?? '') ?? 993,
      username: user,
      password: pass,
      isSecure: (int.tryParse(portStr ?? '') ?? 993) == 993,
      pollIntervalSeconds: 1,
    );
  }

  String? get latestOtp =>
      _otpHistory.isNotEmpty ? _otpHistory.first.code : null;

  /// Lấy OTP mới nhất dành riêng cho account email này.
  /// [after]: chỉ lấy OTP có timestamp >= after (lọc theo thời điểm bấm ログイン).
  String? latestOtpForEmail(String accountEmail, {DateTime? after}) {
    return latestOtpEntryForEmail(accountEmail, after: after)?.code;
  }

  /// OTP entry mới nhất cho account email.
  /// [after]: chỉ lấy OTP có timestamp >= after.
  OtpEntry? latestOtpEntryForEmail(String accountEmail, {DateTime? after}) {
    final cached = _latestOtpByRecipient[_normalizeEmail(accountEmail)];
    if (cached != null &&
        (after == null || !cached.timestamp.isBefore(after))) {
      return cached;
    }

    final unknown = _latestOtpWithoutRecipient;
    if (unknown != null &&
        (after == null || !unknown.timestamp.isBefore(after))) {
      return unknown;
    }

    OtpEntry? unknownRecipientFallback;
    for (final otp in _otpHistory) {
      if (after != null && otp.timestamp.isBefore(after)) continue;
      final recipient = otp.recipient?.trim() ?? '';
      if (recipient.isEmpty) {
        unknownRecipientFallback ??= otp;
        _cacheOtp(otp);
        continue;
      }
      if (!_sameEmailAddress(recipient, accountEmail)) continue;
      _cacheOtp(otp);
      return otp;
    }
    return unknownRecipientFallback;
  }

  bool _sameEmailAddress(String a, String b) =>
      _normalizeEmail(a) == _normalizeEmail(b);

  String _normalizeEmail(String email) {
    final trimmed = email.toLowerCase().trim();
    final at = trimmed.lastIndexOf('@');
    if (at <= 0) return trimmed;

    var local = trimmed.substring(0, at);
    final domain = trimmed.substring(at + 1);
    final plus = local.indexOf('+');
    if (plus >= 0) local = local.substring(0, plus);

    if (domain == 'gmail.com' || domain == 'googlemail.com') {
      local = local.replaceAll('.', '');
      return '$local@gmail.com';
    }
    return '$local@$domain';
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
    _otpSub?.cancel();
    _bgOtpPollingTimer?.cancel();
    _imap.dispose();
    super.dispose();
  }
}
