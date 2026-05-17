import 'dart:convert';
import 'package:http/http.dart' as http;

class DiscordService {
  static Future<void> sendLotterySuccess({
    required String webhookUrl,
    required String email,
    required String productTitle,
    String? imageUrl,
  }) async {
    if (webhookUrl.isEmpty) return;
    try {
      final embed = <String, dynamic>{
        'title': '🎁 応募成功',
        'color': 3066993, // green
        'fields': [
          {'name': 'Account', 'value': email, 'inline': true},
          {'name': 'Sản phẩm', 'value': productTitle, 'inline': false},
        ],
        'footer': {'text': 'PokemonCT'},
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };
      if (imageUrl != null && imageUrl.isNotEmpty) {
        embed['thumbnail'] = {'url': imageUrl};
      }
      await http
          .post(
            Uri.parse(webhookUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'embeds': [embed]}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Non-critical — ignore send failures
    }
  }
}
