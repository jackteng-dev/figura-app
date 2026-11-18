// Phase 4：訂金制預購在 App 顯示訂金／尾款、延期紀錄，並以伺服器金額建立尾款付款。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:figura/app.dart';
import 'package:figura/core/providers.dart';
import 'package:figura/core/storage.dart';

import 'api_test.dart' show Adapter, response, apiFor, tokens;

Map<String, dynamic> depositOrder() => {
  'id': 'pre-1',
  'batchId': 'b1',
  'batchName': '秋季預購',
  'productTitle': '露珠採集員',
  'skuLabel': '展示款',
  'unitPriceTwd': 3000,
  'quantity': 2,
  'subtotalTwd': 6000,
  'shippingTwd': 0,
  'totalTwd': 6000,
  'shipping': {
    'recipientName': '測試收件人',
    'phone': '0912345678',
    'postalCode': '100',
    'city': '台北市',
    'district': '中正區',
    'street': '測試路 1 號',
  },
  'deadlineAt': '2026-12-01T00:00:00+08:00',
  'arrivalFrom': '2027-01-10',
  'arrivalTo': '2027-01-20',
  'status': 'PAID',
  'version': 5,
  'createdAt': '2026-11-18T09:00:00+08:00',
  'expiresAt': '2026-11-18T09:30:00+08:00',
  'closedAt': null,
  'paidAt': '2026-11-18T09:05:00+08:00',
  'arrivalStatus': 'NOT_ARRIVED',
  'fulfillmentStatus': 'UNFULFILLED',
  'paymentReviewRequired': false,
  'refund': null,
  'fulfillment': {
    'allocatedQuantity': 0,
    'allocatedAt': null,
    'provider': 'MOCK',
    'trackingNumber': null,
    'shippedAt': null,
    'deliveredAt': null,
  },
  'paymentMode': 'DEPOSIT',
  'depositTwd': 1000,
  'balanceTwd': 5000,
  'balanceStatus': 'DUE',
  'balanceDueAt': '2026-11-25T10:00:00+08:00',
  'balancePaidAt': null,
  'payNowTwd': 5000,
  'schedule': [
    {
      'action': 'DELAY',
      'publicReason': '原廠延後出貨',
      'arrivalFromBefore': '2026-12-20',
      'arrivalToBefore': '2026-12-30',
      'arrivalFromAfter': '2027-01-10',
      'arrivalToAfter': '2027-01-20',
      'createdAt': '2026-11-18T10:00:00+08:00',
    },
  ],
};

void main() {
  testWidgets(
    'deposit preorder shows balance due, delay history and pays the balance',
    (tester) async {
      tester.view.physicalSize = const Size(390, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? started;
      final adapter = Adapter((o) async {
        if (o.path.endsWith('auth/login')) {
          return response(200, tokens('a', 'r'));
        }
        if (o.path.startsWith('mobile/customer/order-center')) {
          return response(200, {
            'items': [
              {
                'kind': 'PREORDER',
                'id': 'pre-1',
                'stage': 'PENDING_PAYMENT',
                'status': 'PAID',
                'createdAt': '2026-11-18T09:00:00+08:00',
                'totalTwd': 6000,
                'title': '露珠採集員',
                'lineCount': 1,
                'quantity': 2,
                'productId': 'p2',
                'expiresAt': '2026-11-18T09:30:00+08:00',
                'arrivalFrom': '2027-01-10',
                'arrivalTo': '2027-01-20',
                'arrivalStatus': 'NOT_ARRIVED',
                'fulfillmentStatus': 'UNFULFILLED',
                'paymentReviewRequired': false,
                'balanceStatus': 'DUE',
                'balanceDueAt': '2026-11-25T10:00:00+08:00',
              },
            ],
            'page': 1,
            'pageSize': 10,
            'total': 1,
            'counts': {},
          });
        }
        if (o.path == 'mobile/customer/preorders/pre-1') {
          return response(200, depositOrder());
        }
        if (o.path == 'mobile/customer/preorders/pre-1/mock-payments') {
          if (o.method == 'POST') {
            started = Map<String, dynamic>.from(o.data as Map);
            return response(200, {
              'payment': {
                'id': 'pay-2',
                'orderId': 'pre-1',
                'status': 'INITIATED',
                'amountTwd': 5000,
                'stage': 'BALANCE',
              },
              'replayed': false,
            });
          }
          return response(200, {
            'enabled': true,
            'canStart': true,
            'items': [
              {
                'id': 'pay-1',
                'orderId': 'pre-1',
                'status': 'SUCCEEDED',
                'amountTwd': 1000,
                'currency': 'TWD',
                'provider': 'MOCK',
                'stage': 'DEPOSIT',
                'refund': null,
              },
            ],
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
      expect(find.textContaining('訂金已付，待付尾款'), findsOneWidget);
      await tester.tap(find.textContaining('預購訂單 ·'));
      await tester.pumpAndSettle();
      expect(find.text('訂金與尾款'), findsOneWidget);
      expect(find.text('待付尾款'), findsOneWidget);
      expect(find.textContaining('原廠延後出貨'), findsOneWidget);
      expect(find.textContaining('訂金 · '), findsOneWidget);
      final pay = find.textContaining('建立尾款模擬付款');
      expect(pay, findsOneWidget);
      await tester.tap(pay);
      await tester.pumpAndSettle();
      expect(started, isNotNull);
      expect(started!['expectedOrderVersion'], 5);
      // 金額由伺服器決定，App 不送金額
      expect(started!.containsKey('amountTwd'), false);
    },
  );
}
