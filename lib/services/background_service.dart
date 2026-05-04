import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'imap_service.dart';

class BackgroundServiceManager {
  static final BackgroundServiceManager _instance = BackgroundServiceManager._internal();

  factory BackgroundServiceManager() {
    return _instance;
  }

  BackgroundServiceManager._internal();

  ImapService? _bgImapService;
  bool _initialized = false;

  Future<void> initializeBackground() async {
    if (_initialized) return;
    _initialized = true;

    final service = FlutterBackgroundService();

    // iOS setup
    await service.configure(
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: _onForeground,
        onBackground: _onBackground,
      ),
      androidConfiguration: AndroidConfiguration(
        autoStart: true,
        onStart: _onStart,
        isForegroundMode: false,
        autoStartOnBoot: true,
      ),
    );

    service.startService();
  }

  static Future<bool> _onBackground(ServiceInstance service) async {
    return true;
  }

  static void _onForeground(ServiceInstance service) {
    service.invoke("foreground");
  }

  static Future<void> _onStart(ServiceInstance service) async {
    final prefs = await SharedPreferences.getInstance();

    // Load IMAP config từ storage
    final host = prefs.getString('imap_host');
    if (host == null || host.isEmpty) return;

    try {
      final config = ImapConfig(
        host: prefs.getString('imap_host') ?? '',
        port: prefs.getInt('imap_port') ?? 993,
        username: prefs.getString('imap_username') ?? '',
        password: prefs.getString('imap_password') ?? '',
        isSecure: true,
        pollIntervalSeconds: 5,
      );

      if (config.username.isEmpty || config.password.isEmpty) return;

      final bgService = BackgroundServiceManager()._bgImapService ?? ImapService();
      BackgroundServiceManager()._bgImapService = bgService;

      // Start IMAP service
      await bgService.start(config);

      // Listen to OTP stream và lưu vào SharedPreferences
      bgService.otpStream.listen((otp) {
        prefs.setString('latest_otp_code', otp.code);
        prefs.setInt('latest_otp_timestamp', otp.timestamp.millisecondsSinceEpoch);
        if (otp.recipient != null) {
          prefs.setString('latest_otp_recipient', otp.recipient!);
        }

        // Notify foreground app qua service invoke
        service.invoke('otp_received', {
          'code': otp.code,
          'recipient': otp.recipient ?? '',
          'timestamp': otp.timestamp.millisecondsSinceEpoch,
        });
      });
    } catch (e) {
      // Log error
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('bg_service_error', e.toString());
    }
  }

  Future<void> saveImapConfig({
    required String host,
    required int port,
    required String username,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('imap_host', host);
    await prefs.setInt('imap_port', port);
    await prefs.setString('imap_username', username);
    await prefs.setString('imap_password', password);
  }

  Future<String?> getLatestOtp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('latest_otp_code');
  }

  Future<void> stopBackground() async {
    _bgImapService?.dispose();
    _bgImapService = null;
  }

  Future<Map<String, dynamic>?> getBackgroundStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('latest_otp_code');
    final timestamp = prefs.getInt('latest_otp_timestamp');
    final recipient = prefs.getString('latest_otp_recipient');
    final error = prefs.getString('bg_service_error');

    if (code == null) return null;

    return {
      'code': code,
      'recipient': recipient,
      'timestamp': timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp) : null,
      'error': error,
    };
  }

  Future<void> clearBackgroundOtp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('latest_otp_code');
    await prefs.remove('latest_otp_timestamp');
    await prefs.remove('latest_otp_recipient');
  }
}
