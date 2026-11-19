// 會員識別：手機與 Email。規則與後端 CustomerPayloads.normalizePhone／normalizeEmail 一致，
// App 端只做格式檢查與正規化，是否存在、是否重複仍由伺服器判斷。

final RegExp _email = RegExp(
  r'^[A-Za-z0-9._%+\-]{1,64}@[A-Za-z0-9](?:[A-Za-z0-9\-]{0,62}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9\-]{0,62}[A-Za-z0-9])?)+$',
);

/// 台灣手機正規化為 09xxxxxxxx；接受 0912345678、0912-345-678、+886912345678、886 912 345 678、912345678。不合法回傳 null。
String? normalizePhone(String? raw) {
  if (raw == null) return null;
  var digits = raw.replaceAll(RegExp(r'[\s\-()]'), '');
  if (digits.startsWith('+886')) {
    digits = digits.substring(4);
  } else if (digits.startsWith('886') && digits.length == 12) {
    digits = digits.substring(3);
  }
  if (RegExp(r'^9\d{8}$').hasMatch(digits)) digits = '0$digits';
  return RegExp(r'^09\d{8}$').hasMatch(digits) ? digits : null;
}

/// Email 正規化（去空白、轉小寫）；不合法回傳 null。
String? normalizeEmail(String? raw) {
  if (raw == null) return null;
  final e = raw.trim();
  return e.length <= 254 && _email.hasMatch(e) ? e.toLowerCase() : null;
}

/// 登入識別：手機或 Email，正規化後送出；兩者皆不合法回傳 null。
String? normalizeLoginId(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.contains('@')) return normalizeEmail(value);
  return normalizePhone(value);
}
