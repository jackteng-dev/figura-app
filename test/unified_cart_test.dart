// 統一購物車：現貨與預購同一購物車，結帳走 /mobile/customer/checkout，伺服器分組拆單。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:figura/app.dart';
import 'package:figura/core/providers.dart';
import 'package:figura/core/storage.dart';

import 'api_test.dart' show Adapter, response, apiFor, tokens;

void main() {
  testWidgets(
    'mixed cart shows preorder lines and checkout places split orders atomically',
    (tester) async {
      tester.view.physicalSize = const Size(390, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? posted;
      final quotes = <String>[];
      final adapter = Adapter((o) async {
        if (o.path.endsWith('auth/login')) {
          return response(200, tokens('a', 'r'));
        }
        if (o.path == 'mobile/customer/cart') {
          return response(200, {
            'version': 4,
            'items': [
              {
                'productId': 'p1',
                'skuId': 's1',
                'title': '月梨信差',
                'label': '標準款',
                'quantity': 1,
                'unitPriceTwd': 1280,
                'lineTotalTwd': 1280,
                'issue': null,
              },
            ],
            'subtotalTwd': 1280,
            'ready': true,
            'preorders': [
              {
                'batchId': 'b1',
                'productId': 'p2',
                'skuId': 's2',
                'title': '露珠採集員',
                'batchName': '秋季預購',
                'label': '展示款',
                'quantity': 2,
                'unitPriceTwd': 1800,
                'lineTotalTwd': 3600,
                'deadlineAt': '2026-12-01T00:00:00+08:00',
                'arrivalFrom': '2026-12-18',
                'arrivalTo': '2026-12-28',
                'availableQuota': 20,
                'issue': null,
              },
            ],
            'preorderSubtotalTwd': 3600,
            'totalTwd': 4880,
            'checkoutReady': true,
          });
        }
        if (o.path.startsWith('mobile/customer/checkout/quote')) {
          final combined = o.path.contains('deliveryStrategy=COMBINED');
          quotes.add(o.path);
          return response(200, {
            'cartVersion': 4,
            'groups': [
              {
                'key': 'STOCK',
                'kind': 'STOCK',
                'title': '現貨',
                'batchId': null,
                'arrivalFrom': null,
                'arrivalTo': null,
                'lines': [
                  {
                    'productId': 'p1',
                    'skuId': 's1',
                    'batchId': null,
                    'title': '月梨信差',
                    'label': '標準款',
                    'quantity': 1,
                    'unitPriceTwd': 1280,
                    'lineTotalTwd': 1280,
                    'issue': null,
                  },
                ],
                'totalTwd': 1280,
                'ready': true,
              },
              {
                'key': 'PREORDER:b1',
                'kind': 'PREORDER',
                'title': '秋季預購',
                'batchId': 'b1',
                'arrivalFrom': '2026-12-18',
                'arrivalTo': '2026-12-28',
                'lines': [
                  {
                    'productId': 'p2',
                    'skuId': 's2',
                    'batchId': 'b1',
                    'title': '露珠採集員',
                    'label': '展示款',
                    'quantity': 2,
                    'unitPriceTwd': 1800,
                    'lineTotalTwd': 3600,
                    'issue': null,
                  },
                ],
                'totalTwd': 3600,
                'ready': true,
              },
            ],
            'subtotalTwd': 4880,
            'shippingTwd': 0,
            'totalTwd': 4880,
            'ready': true,
            'shippingMethod': 'HOME',
            'deliveryStrategy': combined ? 'COMBINED' : 'SPLIT',
            'shipments': [
              {
                'key': 'SHIPMENT:STOCK',
                'groupKeys': ['STOCK'],
                'carrierKey': 'STOCK',
                'goodsTwd': 1280,
                'feeTwd': 0,
              },
              {
                'key': 'SHIPMENT:PREORDER:b1',
                'groupKeys': ['PREORDER:b1'],
                'carrierKey': 'PREORDER:b1',
                'goodsTwd': 3600,
                'feeTwd': 0,
              },
            ],
            'methods': [
              {
                'code': 'HOME',
                'name': '宅配到府',
                'feeTwd': 120,
                'freeThresholdTwd': 1000,
                'enabled': true,
                'version': 1,
              },
              {
                'code': 'CVS',
                'name': '超商取貨',
                'feeTwd': 60,
                'freeThresholdTwd': 1500,
                'enabled': true,
                'version': 1,
              },
            ],
            'shippingAvailable': true,
          });
        }
        if (o.path == 'mobile/customer/checkout/pickup-stores') {
          return response(200, [
            {
              'brand': 'SEVEN',
              'brandName': '7-ELEVEN（測試）',
              'storeId': 'TEST-711-001',
              'storeName': '測試門市・台北信義',
              'address': '台北市',
            },
          ]);
        }
        if (o.path == 'mobile/customer/addresses') {
          return response(200, [
            {
              'id': 'addr-1',
              'version': 3,
              'recipientName': '測試收件人',
              'phone': '0912345678',
              'postalCode': '100',
              'city': '台北市',
              'district': '中正區',
              'street': '測試路 1 號',
            },
          ]);
        }
        if (o.path == 'mobile/customer/checkout' && o.method == 'POST') {
          posted = jsonDecode(jsonEncode(o.data)) as Map<String, dynamic>;
          return response(200, {
            'groupId': 'g1',
            'orders': [
              {
                'kind': 'STOCK',
                'id': 'o1',
                'status': 'PENDING_PAYMENT',
                'totalTwd': 1280,
                'title': '月梨信差',
              },
              {
                'kind': 'PREORDER',
                'id': 'o2',
                'status': 'PENDING_PAYMENT',
                'totalTwd': 3600,
                'title': '露珠採集員',
              },
            ],
            'totalTwd': 4880,
            'replayed': false,
          });
        }
        if (o.path.startsWith('mobile/customer/order-center')) {
          return response(200, {
            'items': [],
            'page': 1,
            'pageSize': 10,
            'total': 0,
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
      await tester.tap(find.text('購物車'));
      await tester.pumpAndSettle();
      expect(find.text('預購 · 露珠採集員'), findsOneWidget);
      expect(find.textContaining('批次：秋季預購'), findsOneWidget);
      expect(find.text('預購小計'), findsOneWidget);
      await tester.tap(find.text('確認結帳'));
      await tester.pumpAndSettle();
      expect(find.textContaining('這次結帳會拆成 2 張訂單'), findsOneWidget);
      expect(find.text('預購 · 秋季預購'), findsOneWidget);
      expect(find.text('現貨訂單'), findsOneWidget);
      // 選超商取貨＋測試門市＋一起寄：報價帶參數重讀
      await tester.tap(find.text('超商取貨'));
      await tester.pumpAndSettle();
      expect(quotes.last, contains('shippingMethod=CVS'));
      await tester.tap(find.text('一起寄'));
      await tester.pumpAndSettle();
      expect(quotes.last, contains('deliveryStrategy=COMBINED'));
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('測試門市・台北信義').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('建立訂單'));
      await tester.pumpAndSettle();
      expect(posted, isNotNull);
      expect(posted!['cartVersion'], 4);
      expect(posted!['expectedTotalTwd'], 4880);
      expect(posted!['addressId'], 'addr-1');
      expect(posted!.containsKey('expectedSubtotalTwd'), false);
      expect(posted!['shippingMethod'], 'CVS');
      expect(posted!['deliveryStrategy'], 'COMBINED');
      expect(posted!['pickupStoreId'], 'TEST-711-001');
      // 多張訂單：導到統一訂單中心
      expect(
        adapter.requests.last.path,
        startsWith('mobile/customer/order-center'),
      );
      // 舊的現貨購物車下單 API 不再被購物車結帳使用
      expect(
        adapter.requests.any(
          (o) => o.path == 'mobile/customer/orders' && o.method == 'POST',
        ),
        false,
      );
    },
  );
}
