class LotteryApplyEntry {
  final String accountEmail;
  final String productTitle;
  final String time;
  final String status; // '応募成功' | '応募失敗' | '受付終了' | '対象なし' | 'エラー' | 'ログイン失敗'

  const LotteryApplyEntry({
    required this.accountEmail,
    required this.productTitle,
    required this.time,
    required this.status,
  });

  bool get isSuccess => status == '応募成功';
  bool get isFailed => status == '応募失敗';
  bool get isClosed => status == '受付終了';
  bool get isNoMatch => status == '対象なし';
  bool get isError => status == 'エラー' || status == 'ログイン失敗';

  Map<String, dynamic> toJson() => {
        'accountEmail': accountEmail,
        'productTitle': productTitle,
        'time': time,
        'status': status,
      };

  factory LotteryApplyEntry.fromJson(Map<String, dynamic> j) => LotteryApplyEntry(
        accountEmail: j['accountEmail'] as String? ?? '',
        productTitle: j['productTitle'] as String? ?? '',
        time: j['time'] as String? ?? '',
        status: j['status'] as String? ?? '',
      );
}
