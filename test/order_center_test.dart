// 統一訂單中心：App 改用 /mobile/customer/order-center，篩選與排序交給伺服器。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:figura/app.dart';
import 'package:figura/core/providers.dart';
import 'package:figura/core/storage.dart';

import 'api_test.dart' show Adapter, response, apiFor, tokens;

void main() {
  testWidgets(
    'orders tab lists stock and preorder together and passes filters to the server',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final adapter = Adapter((o) async {
        if (o.path.endsWith('auth/login')) {
          return response(200, tokens('a', 'r'));
        }
        if (o.path.startsWith('mobile/customer/order-center')) {
          final preorderOnly = o.path.contains('kind=PREORDER');
          return response(200, {
            'items': [
              if (!preorderOnly)
                {
                  'kind': 'STOCK',
                  'id': 'stock-1',
                  'stage': 'TO_SHIP',
                  'status': 'PAID',
                  'createdAt': '2026-11-18T10:00:00+08:00',
                  'totalTwd': 2560,
                  'title': '月梨信差',
                  'lineCount': 2,
                  'quantity': 3,
                  'productId': 'p1',
                  'expiresAt': null,
                  'arrivalFrom': null,
                  'arrivalTo': null,
                  'arrivalStatus': null,
                  'fulfillmentStatus': 'UNFULFILLED',
                  'paymentReviewRequired': false,
                },
              {
                'kind': 'PREORDER',
                'id': 'pre-1',
                'stage': 'PENDING_PAYMENT',
                'status': 'PENDING',
                'createdAt': '2026-11-18T09:00:00+08:00',
                'totalTwd': 1800,
                'title': '秋季預購',
                'lineCount': 1,
                'quantity': 1,
                'productId': 'p2',
                'expiresAt': '2026-11-18T09:30:00+08:00',
                'arrivalFrom': '2026-12-18',
                'arrivalTo': '2026-12-28',
                'arrivalStatus': 'NOT_ARRIVED',
                'fulfillmentStatus': 'UNFULFILLED',
                'paymentReviewRequired': false,
              },
            ],
            'page': 1,
            'pageSize': 10,
            'total': preorderOnly ? 1 : 2,
            'counts': {},
          });
        }
        return response(200, {
          'items': [],
          'total': 0,
          'page': 1,
          'pageSize': 12,
        });
      });
      final api = apiFor(adapter, MemoryStore());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiProvider.overrideWith((_) => api)],
          child: const ShopApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('會員'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '手機或 Email'),
        'member@example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '密碼'),
        'synthetic-password',
      );
      await tester.tap(find.text('登入'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('訂單'));
      await tester.pumpAndSettle();
      expect(find.text('現貨訂單 · 待出貨'), findsOneWidget);
      expect(find.text('預購訂單 · 待付款'), findsOneWidget);
      expect(find.textContaining('月梨信差 等 2 款'), findsOneWidget);
      expect(find.textContaining('預計到貨'), findsOneWidget);
      final first = adapter.requests.lastWhere(
        (o) => o.path.startsWith('mobile/customer/order-center'),
      );
      expect(first.path, contains('kind=ALL&stage=ALL&sort=NEWEST&page=1'));
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<String>),
          matching: find.text('預購'),
        ),
      );
      await tester.pumpAndSettle();
      expect(adapter.requests.last.path, contains('kind=PREORDER'));
      expect(find.text('現貨訂單 · 待出貨'), findsNothing);
      expect(find.text('預購訂單 · 待付款'), findsOneWidget);
      // 狀態與排序由伺服器處理
      await tester.tap(find.text('全部狀態'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('待付款').last);
      await tester.pumpAndSettle();
      expect(adapter.requests.last.path, contains('stage=PENDING_PAYMENT'));
      await tester.tap(find.text('最新優先'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('金額高到低').last);
      await tester.pumpAndSettle();
      expect(
        adapter.requests.last.path,
        contains('kind=PREORDER&stage=PENDING_PAYMENT&sort=AMOUNT_DESC&page=1'),
      );
      // 舊的分開列表 API 不再被訂單分頁使用
      expect(
        adapter.requests.any(
          (o) =>
              o.path.startsWith('mobile/customer/orders?') ||
              o.path.startsWith('mobile/customer/preorders?'),
        ),
        false,
      );
    },
  );
}
