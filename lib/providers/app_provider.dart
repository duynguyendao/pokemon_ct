import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/account.dart';
import '../models/proxy.dart';
import '../models/otp_entry.dart';
import '../models/filter_rule.dart';
import '../models/lottery_result_entry.dart';
import '../models/order_status_entry.dart';
import '../services/storage_service.dart';
import '../services/imap_service.dart';

class AppProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final ImapService _imap = ImapService();

  List<Account> _accounts = [];
  List<Proxy> _proxies = [];
  List<String> _groups = [];
  List<FilterRule> _filterRules = [];
  List<OtpEntry> _otpHistory = [];
  Map<String, String> _imapConfig = {};
  Map<String, String> _urlConfig = {};

  String _defaultPassword = '';
  bool _proxyEnabled = false;
  bool _fakeBrowser = true;
  bool _incognitoMode = false;
  bool _shortcut5gEnabled = true;
  bool _blockImages = false;
  String _otpSource = 'clipboard'; // 'imap' or 'clipboard'
  String _targetProductName = '';
  int _typingMinDelay = 80;
  int _typingMaxDelay = 180;
  int _otpWatchdogSeconds = 60;
  final List<LotteryResultEntry> _lotteryResults = [];
  final List<OrderStatusEntry> _orderStatusResults = [];
  bool _loaded = false;
  bool _imapStarting = false;
  bool _imapStopping = false;
  String? _imapError;

  final _otpController = StreamController<OtpEntry>.broadcast();
  StreamSubscription<OtpEntry>? _otpSub;

  // Getters
  List<Account> get accounts => _accounts;
  List<Proxy> get proxies => _proxies;
  List<String> get groups => _groups;
  List<FilterRule> get filterRules => _filterRules;
  List<OtpEntry> get otpHistory => _otpHistory;
  Map<String, String> get imapConfig => _imapConfig;
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
  String get targetProductName => _targetProductName;
  int get typingMinDelay => _typingMinDelay;
  int get typingMaxDelay => _typingMaxDelay;
  int get otpWatchdogSeconds => _otpWatchdogSeconds;
  List<LotteryResultEntry> get lotteryResults => List.unmodifiable(_lotteryResults);
  List<OrderStatusEntry> get orderStatusResults => List.unmodifiable(_orderStatusResults);
  bool get loaded => _loaded;
  Stream<OtpEntry> get otpStream => _otpController.stream;
  bool get imapRunning => _imap.isRunning;
  bool get imapStarting => _imapStarting;
  bool get imapStopping => _imapStopping;
  String? get imapError => _imapError;

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
    _incognitoMode = await _storage.loadIncognitoMode();
    _shortcut5gEnabled = await _storage.loadShortcut5gEnabled();
    _blockImages = await _storage.loadBlockImages();
    _otpSource = await _storage.loadOtpSource();
    _targetProductName = await _storage.loadTargetProductName();
    _typingMinDelay = await _storage.loadTypingMinDelay();
    _typingMaxDelay = await _storage.loadTypingMaxDelay();
    _otpWatchdogSeconds = await _storage.loadOtpWatchdogSeconds();
    _loaded = true;
    _setupOtpStream();
    notifyListeners();
  }

  void _setupOtpStream() {
    _otpSub?.cancel();
    _otpSub = _imap.otpStream.listen((otp) {
      addOtpEntry(otp);
      if (!_otpController.isClosed) {
        _otpController.add(otp);
      }
    });
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
    notifyListeners();
  }

  void clearLotteryResults() {
    _lotteryResults.clear();
    notifyListeners();
  }

  void addOrderStatusResult(OrderStatusEntry entry) {
    _orderStatusResults.removeWhere((e) => e.accountEmail == entry.accountEmail);
    _orderStatusResults.add(entry);
    notifyListeners();
  }

  void clearOrderStatusResults() {
    _orderStatusResults.clear();
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

  // --- IMAP Config ---

  Future<void> saveImapConfig(Map<String, String> config) async {
    _imapConfig = config;
    await _storage.saveImapConfig(config);
    notifyListeners();
  }

  // --- OTP History ---

  void addOtpEntry(OtpEntry otp) {
    _otpHistory.insert(0, otp);
    if (_otpHistory.length > 5) {
      _otpHistory.removeLast();
    }
    notifyListeners();
  }

  void clearOtpHistory() {
    _otpHistory.clear();
    notifyListeners();
  }

  OtpEntry? getLatestOtp(String email, {DateTime? after}) {
    final normalized = _normalizeEmail(email);

    for (final otp in _otpHistory) {
      if (after != null && otp.timestamp.isBefore(after)) continue;

      final recipient = otp.recipient?.trim() ?? '';
      if (recipient.isEmpty) {
        return otp;
      }

      if (_normalizeEmail(recipient) == normalized) {
        return otp;
      }
    }

    return null;
  }

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

  String? latestOtpForEmail(String email, {DateTime? after}) {
    return getLatestOtp(email, after: after)?.code;
  }

  // --- IMAP Control ---
  Future<void> startImap() async {
    final host = _imapConfig['host'];
    final portStr = _imapConfig['port'];
    final user = _imapConfig['username'];
    final pass = _imapConfig['password'];

    if (host == null || user == null || pass == null) return;

    _imapStarting = true;
    _imapError = null;
    notifyListeners();

    try {
      await _imap.start(
        host: host,
        port: int.tryParse(portStr ?? '') ?? 993,
        username: user,
        password: pass,
      );
    } catch (e) {
      _imapError = _friendlyImapError(e);
      rethrow;
    } finally {
      _imapStarting = false;
      notifyListeners();
    }
  }

  Future<void> stopImap() async {
    _imapStopping = true;
    notifyListeners();

    try {
      await _imap.stop();
    } finally {
      _imapStopping = false;
      notifyListeners();
    }
  }

  Future<bool> testImapConnection() async {
    final host = _imapConfig['host']?.trim();
    final portStr = _imapConfig['port']?.trim();
    final user = _imapConfig['username']?.trim();
    final pass = _imapConfig['password'];

    if (host == null || host.isEmpty) {
      _imapError = 'Host IMAP đang trống.';
      notifyListeners();
      return false;
    }
    if (user == null || user.isEmpty) {
      _imapError = 'Email IMAP đang trống.';
      notifyListeners();
      return false;
    }
    if (pass == null || pass.trim().isEmpty) {
      _imapError = 'App Password đang trống.';
      notifyListeners();
      return false;
    }

    _imapError = null;
    notifyListeners();

    try {
      await _imap.testConnection(
        host: host,
        port: int.tryParse(portStr ?? '') ?? 993,
        username: user,
        password: pass,
      );
      return true;
    } catch (e) {
      _imapError = _friendlyImapError(e);
      notifyListeners();
      return false;
    }
  }

  String _friendlyImapError(Object error) {
    final message = error.toString();
    final lower = message.toLowerCase();

    if (lower.contains('authentication') ||
        lower.contains('login') ||
        lower.contains('invalid credentials') ||
        lower.contains('username and password not accepted')) {
      return 'Đăng nhập IMAP thất bại. Với Gmail cần bật 2-Step Verification và dùng App Password 16 ký tự, không dùng mật khẩu Gmail thường.';
    }
    if (lower.contains('socket') ||
        lower.contains('failed host lookup') ||
        lower.contains('network')) {
      return 'Không kết nối được tới IMAP server. Kiểm tra mạng, host và port.';
    }
    if (lower.contains('certificate') || lower.contains('handshake')) {
      return 'Lỗi SSL/TLS khi kết nối IMAP. Với Gmail dùng host imap.gmail.com và port 993.';
    }

    return message;
  }

  Future<List<OtpEntry>> fetchOtpNow() async {
    final host = _imapConfig['host']?.trim();
    final portStr = _imapConfig['port']?.trim();
    final user = _imapConfig['username']?.trim();
    final pass = _imapConfig['password'];

    if (host == null || host.isEmpty || user == null || user.isEmpty) {
      return [];
    }
    if (pass == null || pass.trim().isEmpty) {
      return [];
    }

    final results = await _imap.fetchRecentOtps(
      host: host,
      port: int.tryParse(portStr ?? '') ?? 993,
      username: user,
      password: pass,
    );

    return results;
  }

  Future<List<EmailSearchResult>> searchEmails({
    String subjectKeyword = '',
    String bodyKeyword = '',
    DateTime? from,
    DateTime? to,
    int maxMessages = 20,
  }) async {
    final host = _imapConfig['host']?.trim();
    final portStr = _imapConfig['port']?.trim();
    final user = _imapConfig['username']?.trim();
    final pass = _imapConfig['password'];

    if (host == null || host.isEmpty) {
      throw StateError('Host IMAP đang trống.');
    }
    if (user == null || user.isEmpty) {
      throw StateError('Email IMAP đang trống.');
    }
    if (pass == null || pass.trim().isEmpty) {
      throw StateError('App Password đang trống.');
    }

    final results = await _imap.searchEmails(
      host: host,
      port: int.tryParse(portStr ?? '') ?? 993,
      username: user,
      password: pass,
      subjectKeyword: subjectKeyword,
      bodyKeyword: bodyKeyword,
      from: from,
      to: to,
      maxMessages: maxMessages,
    );

    return results
        .map(
          (result) => EmailSearchResult(
            subject: result.subject,
            sender: result.sender,
            body: result.body,
            date: result.date,
            otpFound: result.otpFound,
          ),
        )
        .toList();
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
    _otpController.close();
    _imap.dispose();
    super.dispose();
  }
}

class EmailSearchResult {
  final String subject;
  final String sender;
  final String body;
  final DateTime date;
  final String? otpFound;

  const EmailSearchResult({
    required this.subject,
    required this.sender,
    required this.body,
    required this.date,
    this.otpFound,
  });
}
