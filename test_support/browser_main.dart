import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:figura/app.dart';
import 'package:figura/core/api.dart';
import 'package:figura/core/storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode) throw StateError('Browser test harness requires debug mode');
  runShopApp(
    ShopApi(
      store: MemoryStore(),
      baseUrl: const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://127.0.0.1:25178/figura/api/',
      ),
      development: true,
    ),
  );
}
