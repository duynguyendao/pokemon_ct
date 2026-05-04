String? extractOtpFromText(String text) {
  final patterns = [
    r'【パスコード】\s*(\d{6})',
    r'(?:パスコード|認証コード|確認コード|コード)[:：\s]*([0-9０-９]{4,8})',
    r'(?:code|otp|passcode|verification code)[\s:：-]*([0-9]{4,8})',
    r'\b(\d{6})\b',
    r'(?<!\d)([０-９]{6})(?!\d)',
  ];

  for (final pattern in patterns) {
    try {
      final match = RegExp(pattern, caseSensitive: false).firstMatch(text);
      if (match == null) continue;
      final raw = match.group(1) ?? match.group(0);
      if (raw == null) continue;
      return _normalizeDigits(raw);
    } catch (_) {}
  }
  return null;
}

String _normalizeDigits(String value) {
  const fullWidthZero = 0xff10;
  const asciiZero = 0x30;
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    if (rune >= fullWidthZero && rune <= fullWidthZero + 9) {
      buffer.writeCharCode(asciiZero + rune - fullWidthZero);
    } else if (rune >= asciiZero && rune <= asciiZero + 9) {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}
