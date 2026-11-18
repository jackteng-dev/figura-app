// 後端 contact-only-login：註冊只收手機＋Email＋密碼，登入用手機或 Email，暱稱修改停用。
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:figura/app.dart';
import 'package:figura/core/api.dart';
import 'package:figura/core/identity.dart';
import 'package:figura/core/providers.dart';
import 'package:figura/core/storage.dart';

import 'api_test.dart' show Adapter, response, apiFor, tokens;

ResponseBody failure(int status, String message) => ResponseBody.fromString(
  jsonEncode({'code': 1, 'message': message, 'data': null}),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

Future<void> pumpApp(WidgetTester tester, ShopApi api) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiProvider.overrideWith((_) => api)],
      child: const ShopApp(),
    ),
  );
  await tester.pumpAndSettle();
}

const emptyPage = {'items': [], 'total': 0, 'page': 1, 'pageSize': 12};

void main() {
  group('identity rules match the backend', () {
    test('phone normalization', () {
      expect(normalizePhone('0912345678'), '0912345678');
      expect(normalizePhone('0912-345-678'), '0912345678');
      expect(normalizePhone('+886912345678'), '0912345678');
      expect(normalizePhone('886 912 345 678'), '0912345678');
      expect(normalizePhone('912345678'), '0912345678');
      expect(normalizePhone('0212345678'), null);
      expect(normalizePhone('09123'), null);
    });
    test('email normalization and login identifier', () {
      expect(normalizeEmail(' Member@Example.TEST '), 'member@example.test');
      expect(normalizeEmail('not-an-email'), null);
      expect(normalizeLoginId('Member@Example.test'), 'member@example.test');
      expect(normalizeLoginId('0912-345-678'), '0912345678');
      // 舊的帳號名稱不是合法的登入識別
      expect(normalizeLoginId('member_01'), null);
    });
  });

  test('register sends only email, phone and password', () async {
    final adapter = Adapter((_) async => response(201, {'id': 'x'}));
    final api = apiFor(adapter, MemoryStore());
    await api.register(
      email: 'a@example.test',
      phone: '0912345678',
      password: 'synthetic-password',
    );
    final body = adapter.requests.single.data as Map;
    expect(adapter.requests.single.path, 'mobile/customer/auth/register');
    expect(body.keys.toSet(), {'email', 'phone', 'password'});
  });

  test('register shows the server reason for a duplicate', () async {
    final api = apiFor(
      Adapter((_) async => failure(409, '此 Email 已被註冊')),
      MemoryStore(),
    );
    expect(
      () => api.register(
        email: 'a@example.test',
        phone: '0912345678',
        password: 'synthetic-password',
      ),
      throwsA(
        isA<ShopError>()
            .having((e) => e.message, 'message', '此 Email 已被註冊')
            .having((e) => e.uncertain, 'uncertain', false),
      ),
    );
  });

  testWidgets('login accepts an email and sends it normalized', (tester) async {
    final store = MemoryStore();
    final adapter = Adapter(
      (o) async => o.path.endsWith('auth/login')
          ? response(200, tokens('a', 'r'))
          : response(200, emptyPage),
    );
    final api = apiFor(adapter, store);
    await pumpApp(tester, api);
    await tester.tap(find.text('會員'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '手機或 Email'),
      ' Member@Example.TEST ',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '密碼'),
      'synthetic-password',
    );
    await tester.tap(find.text('登入'));
    await tester.pumpAndSettle();
    final login = adapter.requests.firstWhere(
      (o) => o.path == 'mobile/customer/auth/login',
    );
    expect((login.data as Map)['username'], 'member@example.test');
    expect(api.signedIn, true);
    expect(store.values.containsKey('refresh_token'), true);
    expect(store.values.values.contains('synthetic-password'), false);
    // 頁首不顯示系統產生的帳號名稱或暱稱
    expect(find.text('會員中心'), findsOneWidget);
    expect(find.text('會員'), findsWidgets);
    expect(find.textContaining('member'), findsNothing);
  });

  testWidgets('registration form asks for phone, email and password only', (
    tester,
  ) async {
    final adapter = Adapter((o) async {
      if (o.path.endsWith('auth/register')) return response(201, {'id': 'x'});
      if (o.path.endsWith('auth/login')) return response(200, tokens('a', 'r'));
      return response(200, emptyPage);
    });
    final api = apiFor(adapter, MemoryStore());
    await pumpApp(tester, api);
    await tester.tap(find.text('會員'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('建立新帳號'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '帳號'), findsNothing);
    expect(find.widgetWithText(TextFormField, '顯示名稱'), findsNothing);
    await tester.tap(find.text('註冊並登入'));
    await tester.pumpAndSettle();
    expect(find.text('請輸入 09 開頭的 10 碼手機'), findsOneWidget);
    expect(find.text('Email 格式不正確'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, '手機號碼'),
      '0912-345-678',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'New@Example.test',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '密碼'),
      'synthetic-password-1',
    );
    await tester.tap(find.text('註冊並登入'));
    await tester.pumpAndSettle();
    final register = adapter.requests.firstWhere(
      (o) => o.path.endsWith('auth/register'),
    );
    expect(register.data, {
      'email': 'new@example.test',
      'phone': '0912345678',
      'password': 'synthetic-password-1',
    });
    final login = adapter.requests.firstWhere(
      (o) => o.path.endsWith('auth/login'),
    );
    expect((login.data as Map)['username'], 'new@example.test');
    expect(api.signedIn, true);
  });

  testWidgets('account shows email, phone and verification, no nickname edit', (
    tester,
  ) async {
    final adapter = Adapter((o) async {
      if (o.path.endsWith('auth/login')) return response(200, tokens('a', 'r'));
      if (o.path == 'mobile/customer/me') {
        return response(200, {
          'id': 'owner',
          'email': 'member@example.test',
          'phone': '0912345678',
          'emailVerified': false,
        });
      }
      return response(200, emptyPage);
    });
    final api = apiFor(adapter, MemoryStore());
    await pumpApp(tester, api);
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
    await tester.tap(find.text('會員'));
    await tester.pumpAndSettle();
    expect(find.text('Email：member@example.test'), findsOneWidget);
    expect(find.text('Email 尚未驗證'), findsOneWidget);
    expect(find.text('手機：0912345678'), findsOneWidget);
    expect(find.text('更新名稱'), findsNothing);
    expect(adapter.requests.any((o) => o.method == 'PATCH'), false);
  });

  test('register keeps the generic message for 5xx (result unknown)', () async {
    final api = apiFor(
      Adapter((_) async => failure(503, 'internal detail')),
      MemoryStore(),
    );
    await expectLater(
      api.register(
        email: 'a@example.test',
        phone: '0912345678',
        password: 'synthetic-password',
      ),
      throwsA(
        isA<ShopError>()
            .having((e) => e.message, 'message', '連線失敗，請稍後重試')
            .having((e) => e.uncertain, 'uncertain', true),
      ),
    );
  });

  testWidgets('wrong credentials show one neutral message', (tester) async {
    final api = apiFor(
      Adapter(
        (o) async => o.path.endsWith('auth/login')
            ? failure(401, '帳號或密碼錯誤')
            : response(200, emptyPage),
      ),
      MemoryStore(),
    );
    await pumpApp(tester, api);
    await tester.tap(find.text('會員'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '手機或 Email'),
      '0912345678',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '密碼'),
      'wrong-password',
    );
    await tester.tap(find.text('登入'));
    await tester.pumpAndSettle();
    expect(find.text('手機／Email 或密碼不正確'), findsOneWidget);
    expect(api.signedIn, false);
  });

  Future<void> signIn(WidgetTester tester) async {
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
  }

  testWidgets(
    'an old saved nickname change is only re-read, never re-sent, and unlocks after confirmation',
    (tester) async {
      final store = MemoryStore();
      // 舊版 App 留下的未確認「修改暱稱」（不可重送）
      store.values['pending_owner'] = jsonEncode({
        'owner': 'owner',
        'method': 'PATCH',
        'path': 'me',
        'body': {'displayName': '舊暱稱'},
        'replayable': false,
      });
      final adapter = Adapter((o) async {
        if (o.path.endsWith('auth/login')) {
          return response(200, tokens('a', 'r'));
        }
        if (o.path == 'mobile/customer/me') {
          return response(200, {
            'id': 'owner',
            'email': 'member@example.test',
            'phone': '0912345678',
            'emailVerified': true,
          });
        }
        return response(200, emptyPage);
      });
      final api = apiFor(adapter, store);
      await pumpApp(tester, api);
      await signIn(tester);
      expect(find.text('上一筆操作尚未確認。新寫入已暫停，請先核對。'), findsOneWidget);
      expect(find.text('以原編號核對／重試'), findsNothing);
      await tester.tap(find.text('重讀目前資料並核對'));
      await tester.pumpAndSettle();
      expect(find.textContaining('暱稱功能已停用'), findsOneWidget);
      expect(find.textContaining('member@example.test'), findsWidgets);
      await tester.tap(find.text('保留待核對'));
      await tester.pumpAndSettle();
      expect(store.values.containsKey('pending_owner'), true);
      await tester.tap(find.text('重讀目前資料並核對'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('已核對，解除鎖定'));
      await tester.pumpAndSettle();
      expect(store.values.containsKey('pending_owner'), false);
      expect(find.text('上一筆操作尚未確認。新寫入已暫停，請先核對。'), findsNothing);
      expect(adapter.requests.any((o) => o.method == 'PATCH'), false);
    },
  );

  testWidgets(
    'ECPay payments started on the website cannot be simulated in the App',
    (tester) async {
      final adapter = Adapter((o) async {
        if (o.path.endsWith('auth/login')) {
          return response(200, tokens('a', 'r'));
        }
        if (o.path == 'mobile/customer/orders/o1') {
          return response(200, {
            'id': 'o1',
            'version': 1,
            'status': 'PENDING_PAYMENT',
            'subtotalTwd': 520,
            'shippingTwd': 0,
            'totalTwd': 520,
            'createdAt': '2026-11-18T10:00:00',
            'expiresAt': '2026-11-18T10:30:00',
            'paidAt': null,
            'items': [],
            'shipping': {
              'recipientName': '合成',
              'phone': '0912345678',
              'postalCode': '100',
              'city': '測試市',
              'district': '測試區',
              'street': '合成路 1 號',
            },
            'fulfillment': {'status': 'UNFULFILLED'},
            'refund': null,
            'returnProgress': null,
          });
        }
        if (o.path == 'mobile/customer/orders/o1/mock-payments') {
          return response(200, {
            'enabled': true,
            'canStart': false,
            'items': [
              {
                'id': 'p1',
                'status': 'INITIATED',
                'amountTwd': 520,
                'provider': 'ECPAY',
              },
              {
                'id': 'p2',
                'status': 'INITIATED',
                'amountTwd': 520,
                'provider': 'MOCK',
              },
              {'id': 'p3', 'status': 'INITIATED', 'amountTwd': 520},
            ],
          });
        }
        return response(200, emptyPage);
      });
      final api = apiFor(adapter, MemoryStore());
      await pumpApp(tester, api);
      tester.view.physicalSize = const Size(390, 3000);
      await tester.pumpAndSettle();
      await signIn(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp).first),
      );
      container.read(routerProvider).go('/orders/stock/o1');
      await tester.pumpAndSettle();
      expect(find.textContaining('綠界測試信用卡'), findsOneWidget);
      expect(find.text('此筆為網站發起的綠界測試付款，請在網站完成或等待結果。'), findsOneWidget);
      // 只有 MOCK 與沒有 provider 的兩筆可以模擬
      expect(find.text('模擬成功'), findsNWidgets(2));
      expect(find.text('模擬失敗'), findsNWidgets(2));
    },
  );
}
