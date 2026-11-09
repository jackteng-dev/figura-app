typedef Json = Map<String, dynamic>;
Json object(dynamic v) => Map<String, dynamic>.from(v as Map);
List<Json> objects(dynamic v) => (v as List).map(object).toList();
String twd(num? value) => 'NT\$ ${value ?? 0}';
DateTime? shopTime(String? value) {
  if (value == null) return null;
  if (RegExp(r"^\d{4}-\d{2}-\d{2}$").hasMatch(value)) {
    return DateTime.tryParse("${value}T00:00:00+08:00");
  }
  final zoned = RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(value);
  return DateTime.tryParse(zoned ? value : '$value+08:00');
}

String dateLabel(String? value) {
  if (value != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return value.replaceAll('-', '/');
  }
  final d = shopTime(value)?.toUtc().add(const Duration(hours: 8));
  if (d == null) return '待確認';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

String statusLabel(String? s) =>
    const {
      'PENDING': '等待付款',
      'PENDING_PAYMENT': '等待付款',
      'PAID': '已付款',
      'CANCELLED': '已取消',
      'EXPIRED': '已逾期',
      'REFUNDED': '已退款',
      'UNFULFILLED': '等待出貨',
      'SHIPPED': '已出貨',
      'DELIVERED': '已送達',
      'NOT_ARRIVED': '等待到貨',
      'ARRIVED': '已到貨並分配',
      'INITIATED': '等待模擬結果',
      'SUCCEEDED': '付款成功',
      'FAILED': '付款失敗',
      'REVIEW_REQUIRED': '待人工核對',
      'REQUESTED': '已申請',
      'RECEIVED': '已驗收',
      'REJECTED': '已拒絕',
    }[s] ??
    s ??
    '待確認';

class Address {
  final Json json;
  Address(this.json);
  String get id => json['id'] as String;
  int get version => json['version'] as int;
  String get label =>
      '${json['recipientName']} · ${json['city']}${json['district']}${json['street']}';
}

class ShopOrder {
  final Json json;
  final bool preorder;
  ShopOrder(this.json, {required this.preorder});
  String get id => json['id'] as String;
  int get version => json['version'] as int;
  String get status => json['status'] as String;
  bool get pending => status == (preorder ? 'PENDING' : 'PENDING_PAYMENT');
  num get total => json['totalTwd'] as num;
  String get title =>
      preorder ? '${json['productTitle']} · ${json['batchName']}' : '現貨訂單';
  String get resource => preorder ? 'preorders' : 'orders';
}
