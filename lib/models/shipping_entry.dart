class ShippingEntry {
  final String accountEmail;
  final String orderNum;
  final String productTitle;
  final String trackingNumDisplay; // e.g. "5121-7735-2352"
  final String trackingNum;        // digits only e.g. "512177352352"
  final String trackingLink;       // kuronekoyamato URL
  final String deliveryInfo;
  final String time;

  const ShippingEntry({
    required this.accountEmail,
    required this.orderNum,
    required this.productTitle,
    required this.trackingNumDisplay,
    required this.trackingNum,
    required this.trackingLink,
    required this.deliveryInfo,
    required this.time,
  });

  bool get hasTracking => trackingNum.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'accountEmail': accountEmail,
        'orderNum': orderNum,
        'productTitle': productTitle,
        'trackingNumDisplay': trackingNumDisplay,
        'trackingNum': trackingNum,
        'trackingLink': trackingLink,
        'deliveryInfo': deliveryInfo,
        'time': time,
      };

  factory ShippingEntry.fromJson(Map<String, dynamic> j) => ShippingEntry(
        accountEmail: j['accountEmail'] as String? ?? '',
        orderNum: j['orderNum'] as String? ?? '',
        productTitle: j['productTitle'] as String? ?? '',
        trackingNumDisplay: j['trackingNumDisplay'] as String? ?? '',
        trackingNum: j['trackingNum'] as String? ?? '',
        trackingLink: j['trackingLink'] as String? ?? '',
        deliveryInfo: j['deliveryInfo'] as String? ?? '',
        time: j['time'] as String? ?? '',
      );
}
