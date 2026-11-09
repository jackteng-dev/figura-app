import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/api.dart';
import 'core/storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const base = String.fromEnvironment('API_BASE_URL');
  try {
    if (kIsWeb) throw ShopError('顧客 App 請使用 Android 或 iOS。瀏覽器測試使用獨立測試入口。');
    runShopApp(
      ShopApi(store: NativeStore(), baseUrl: base, development: kDebugMode),
    );
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(e is ShopError ? e.message : 'App 設定無法載入'),
            ),
          ),
        ),
      ),
    );
  }
}
