import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpsy_shop/app.dart';
import 'package:elpsy_shop/core/providers.dart';
import 'package:elpsy_shop/core/storage.dart';

import 'api_test.dart' show Adapter, response, apiFor, tokens;

void main() {
  testWidgets(
    'catalog empty state and signed-out cart guard render at phone width',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = apiFor(
        Adapter(
          (_) async => response(200, {
            'items': [],
            'total': 0,
            'page': 1,
            'pageSize': 12,
          }),
        ),
        MemoryStore(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiProvider.overrideWith((_) => api)],
          child: const ShopApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('目前沒有上架商品'), findsOneWidget);
      await tester.tap(find.text('購物車'));
      await tester.pumpAndSettle();
      expect(find.text('收藏，從這裡開始。'), findsOneWidget);
      expect(tester.takeException(), null);
      await tester.tap(find.text('登入'));
      await tester.pumpAndSettle();
      expect(find.text('帳號需為 3–32 個英數或底線'), findsOneWidget);
      expect(find.text('請填寫密碼'), findsOneWidget);
    },
  );
  testWidgets(
    'read error offers a retry and does not render a false empty catalog',
    (tester) async {
      var calls = 0;
      final api = apiFor(
        Adapter((_) async {
          calls++;
          return calls == 1
              ? response(503, null)
              : response(200, {
                  'items': [],
                  'total': 0,
                  'page': 1,
                  'pageSize': 12,
                });
        }),
        MemoryStore(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiProvider.overrideWith((_) => api)],
          child: const ShopApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('重新讀取'), findsOneWidget);
      await tester.tap(find.text('重新讀取'));
      await tester.pumpAndSettle();
      expect(find.text('目前沒有上架商品'), findsOneWidget);
      expect(calls, 2);
    },
  );
  testWidgets(
    'login uses the native API and tokens stay out of general preferences',
    (tester) async {
      final store = MemoryStore();
      final adapter = Adapter(
        (o) async => o.path.endsWith('auth/login')
            ? response(200, tokens('a', 'r'))
            : response(200, {
                'items': [],
                'total': 0,
                'page': 1,
                'pageSize': 12,
              }),
      );
      final api = apiFor(adapter, store);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiProvider.overrideWith((_) => api)],
          child: const ShopApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('會員'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'member');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'synthetic-password',
      );
      await tester.tap(find.text('登入'));
      await tester.pumpAndSettle();
      expect(api.signedIn, true);
      expect(find.text('目前沒有上架商品'), findsOneWidget);
      expect(
        adapter.requests.any((o) => o.path == 'mobile/customer/auth/login'),
        true,
      );
      expect(store.values.containsKey('refresh_token'), true);
      expect(store.values.values.contains('synthetic-password'), false);
      expect(tester.takeException(), null);
    },
  );
}
