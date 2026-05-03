import 'package:url_launcher/url_launcher.dart';

class ShortcutService {
  static Future<bool> triggerShortcut(String shortcutName) async {
    try {
      // iOS Shortcuts URL scheme
      final uri = Uri(
        scheme: 'shortcuts',
        host: 'run-shortcut',
        queryParameters: {'name': shortcutName},
      );
      return await launchUrl(uri);
    } catch (e) {
      return false;
    }
  }

  static Future<bool> is5GEnabled() async {
    // Can't directly check 5G status from iOS app
    // User needs to check Settings or Shortcut can return value
    return false;
  }
}
