class OrderStatusEntry {
  final String accountEmail;
  final String productTitle;
  final String orderNum;
  final String status; // '注文受付済み' | '発送準備中' | '発送済み' | 'エラー' | '対象なし'
  final String time;

  const OrderStatusEntry({
    required this.accountEmail,
    required this.productTitle,
    required this.orderNum,
    required this.status,
    required this.time,
  });

  bool get isReceived => status == '注文受付済み';
  bool get isPreparing => status == '発送準備中';
  bool get isShipped => status == '発送済み';
  bool get isCancelled => status == 'キャンセル済み';
  bool get isError => status == 'エラー' || status == '対象なし';

  Map<String, dynamic> toJson() => {
        'accountEmail': accountEmail,
        'productTitle': productTitle,
        'orderNum': orderNum,
        'status': status,
        'time': time,
      };
}
