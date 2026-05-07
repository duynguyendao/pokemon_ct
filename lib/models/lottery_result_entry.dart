class LotteryResultEntry {
  final String accountEmail;
  final String productTitle;
  final String time;
  final String result; // '当選', '落選', '未定', 'エラー', '対象なし', 'ログイン失敗'

  const LotteryResultEntry({
    required this.accountEmail,
    required this.productTitle,
    required this.time,
    required this.result,
  });

  bool get isWon => result == '当選';
  bool get isLost => result == '落選';
  bool get isError => result == 'エラー' || result == 'ログイン失敗';
  bool get isNoResult => result == '対象なし' || result == '未定';
}
