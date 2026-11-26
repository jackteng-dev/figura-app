import 'dart:async';

import 'package:dio/dio.dart';
import 'package:figura/core/api.dart';
import 'package:figura/core/models.dart';
import 'package:figura/core/providers.dart';
import 'package:figura/core/storage.dart';
import 'package:figura/features/auth.dart';
import 'package:figura/features/catalog.dart';
import 'package:figura/features/engagement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'api_test.dart' show Adapter, apiFor, response;

Json product(int id) => {
  'id': 'p$id',
  'title': '商品 $id',
  'brand': '品牌',
  'category': '模型',
  'description': '',
  'skus': <Json>[],
  'minPriceTwd': 1280,
  'availability': id.isEven ? 'SOLD_OUT' : 'IN_STOCK',
};

Json preferences({int version = 0, bool email = false}) => {
  'emailEnabled': email,
  'orderUpdates': true,
  'productAlerts': true,
  'emailVerified': false,
  'emailDeliveryActive': false,
  'version': version,
};

Json notice(int id, {String? target, bool read = false}) => {
  'id': 'n$id',
  'title': '通知 $id',
  'message': '事件內容 $id',
  'createdAt': '2026-11-25T10:00:00+08:00',
  'readAt': read ? '2026-11-25T11:00:00+08:00' : null,
  ?target: target == 'productId' ? 'p1' : 'o1',
};

Json page(List<Json> items, {int total = 1, int number = 1, int unread = 0}) =>
    {
      'items': items,
      'total': total,
      'page': number,
      'pageSize': 20,
      'unread': unread,
    };

Future<ShopApi> mount(
  WidgetTester tester,
  Adapter adapter,
  Widget screen, {
  bool signedIn = true,
  MemoryStore? store,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = apiFor(adapter, store ?? MemoryStore());
  if (signedIn) {
    api.accessToken = 'test-access';
    api.customer = {'id': 'owner'};
  }
  final router = GoRouter(
    initialLocation: '/screen',
    routes: [
      GoRoute(
        path: '/screen',
        builder: (_, _) => Scaffold(body: screen),
      ),
      for (final path in [
        '/login',
        '/products/:id',
        '/orders/stock/:id',
        '/orders/preorder/:id',
        '/account/favorites',
        '/account/notifications',
        '/account/notification-preferences',
      ])
        GoRoute(
          path: path,
          builder: (_, state) => Scaffold(body: Text('目的地 ${state.uri.path}')),
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiProvider.overrideWith((_) => api)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

List<RequestOptions> writes(Adapter adapter) =>
    adapter.requests.where((r) => r.method != 'GET').toList();

Future<void> secondPage(WidgetTester tester, Adapter adapter) async {
  for (
    var i = 0;
    i < 15 &&
        !adapter.requests.any(
          (r) => Uri.parse(r.path).queryParameters['page'] == '2',
        );
    i++
  ) {
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'product heart loads ids and sends PUT then DELETE with customer paths',
    (tester) async {
      var favorite = false;
      final adapter = Adapter((r) async {
        if (r.path == 'catalog/products/p1') return response(200, product(1));
        if (r.path == 'mobile/customer/product-alerts') {
          return response(200, []);
        }
        if (r.path == 'mobile/customer/favorites/p1') {
          favorite = r.method == 'PUT';
        }
        return response(200, {
          'productIds': favorite ? ['p1'] : [],
        });
      });
      await mount(tester, adapter, const ProductScreen(id: 'p1'));
      await tester.ensureVisible(find.byTooltip('加入收藏'));
      await tester.tap(find.byTooltip('加入收藏'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      await tester.tap(find.byTooltip('移除收藏'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(writes(adapter).map((r) => '${r.method} ${r.path}'), [
        'PUT mobile/customer/favorites/p1',
        'DELETE mobile/customer/favorites/p1',
      ]);
      expect(
        adapter.requests.any((r) => r.path == 'mobile/customer/favorites/ids'),
        true,
      );
      expect(
        writes(adapter)
            .every((r) => r.headers['Authorization'] == 'Bearer test-access'),
        true,
      );
    },
  );

  testWidgets(
    'guest heart shows login prompt and navigates without private requests',
    (tester) async {
      final adapter = Adapter((_) async => response(200, product(1)));
      await mount(
        tester,
        adapter,
        const ProductScreen(id: 'p1'),
        signedIn: false,
      );
      await tester.ensureVisible(find.byTooltip('加入收藏'));
      await tester.tap(find.byTooltip('加入收藏'));
      await tester.pumpAndSettle();
      expect(find.text('登入後才能收藏'), findsOneWidget);
      await tester.tap(find.text('前往登入'));
      await tester.pumpAndSettle();
      expect(find.text('目的地 /login'), findsOneWidget);
      expect(adapter.requests.map((r) => r.path), ['catalog/products/p1']);
    },
  );

  testWidgets(
    'alerts load this product and replace the complete set, including empty',
    (tester) async {
      var kinds = ['RESTOCK', 'RELEASE'];
      final adapter = Adapter((r) async {
        if (r.path == 'mobile/customer/favorites/ids') {
          return response(200, {'productIds': []});
        }
        if (r.method == 'PUT') {
          kinds = List<String>.from(r.data['kinds']);
          return response(200, kinds);
        }
        return response(200, [
          {
            'productId': 'other',
            'kinds': ['PREORDER_OPEN'],
          },
          {'productId': 'p1', 'kinds': kinds},
        ]);
      });
      await mount(tester, adapter, const ProductEngagement(id: 'p1'));
      expect(find.text('已訂閱：補貨、發售'), findsOneWidget);
      await tester.tap(find.text('到貨／開賣提醒'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, '補貨'),
            )
            .value,
        true,
      );
      await tester.tap(find.text('補貨'));
      await tester.tap(find.text('開放預購'));
      await tester.tap(find.text('預購即將截止'));
      await tester.tap(find.text('儲存提醒'));
      await tester.pumpAndSettle();
      expect(writes(adapter).single.path, 'mobile/customer/product-alerts/p1');
      expect(writes(adapter).single.method, 'PUT');
      expect(writes(adapter).single.data, {
        'kinds': ['PREORDER_CLOSING', 'PREORDER_OPEN', 'RELEASE'],
      });
      await tester.tap(find.text('到貨／開賣提醒'));
      await tester.pumpAndSettle();
      for (final label in ['開放預購', '預購即將截止', '發售']) {
        await tester.tap(find.text(label));
      }
      await tester.tap(find.text('儲存提醒'));
      await tester.pumpAndSettle();
      expect(writes(adapter).last.data, {'kinds': []});
      expect(find.text('尚未訂閱商品提醒'), findsOneWidget);
    },
  );

  testWidgets(
    'preferences conflict re-reads version and all switches send expectedVersion',
    (tester) async {
      var gets = 0, puts = 0;
      final adapter = Adapter((r) async {
        if (r.method == 'GET') {
          gets++;
          return response(
            200,
            preferences(version: gets == 1 ? 0 : 7, email: gets > 1),
          );
        }
        puts++;
        return puts == 1
            ? response(409, null)
            : response(200, preferences(version: 8));
      });
      await mount(tester, adapter, const NotificationPreferencesScreen());
      expect(find.text('需先驗證 Email 才能收到 Email 通知'), findsOneWidget);
      expect(find.text('目前為測試環境，Email 不會實際寄出'), findsOneWidget);
      await tester.tap(find.text('Email 通知'));
      await tester.pumpAndSettle();
      expect(find.text('設定已在其他裝置變更'), findsOneWidget);
      expect(gets, 2);
      expect(writes(adapter).single.data, {
        'emailEnabled': true,
        'orderUpdates': true,
        'productAlerts': true,
        'expectedVersion': 0,
      });
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Email 通知'),
            )
            .value,
        true,
      );
      await tester.tap(find.text('訂單通知'));
      await tester.pumpAndSettle();
      expect(writes(adapter).last.data, {
        'emailEnabled': true,
        'orderUpdates': false,
        'productAlerts': true,
        'expectedVersion': 7,
      });
      await tester.tap(find.text('商品提醒'));
      await tester.pumpAndSettle();
      expect(writes(adapter).last.data['productAlerts'], false);
      expect(
        writes(adapter).every(
          (r) =>
              r.path == 'mobile/customer/notification-preferences' &&
              r.method == 'PUT',
        ),
        true,
      );
    },
  );

  testWidgets(
    'unknown preference result is securely retained and never auto resent',
    (tester) async {
      final store = MemoryStore();
      final adapter = Adapter(
        (r) async => response(
          r.method == 'GET' ? 200 : 503,
          r.method == 'GET' ? preferences() : null,
        ),
      );
      await mount(
        tester,
        adapter,
        const NotificationPreferencesScreen(),
        store: store,
      );
      await tester.tap(find.text('Email 通知'));
      await tester.pumpAndSettle();
      expect(writes(adapter), hasLength(1));
      expect(
        store.values['pending_owner'],
        contains('notification-preferences'),
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Email 通知'),
            )
            .onChanged,
        null,
      );
      expect(adapter.requests.where((r) => r.method == 'GET'), hasLength(2));
    },
  );

  testWidgets(
    'favorites scroll append page, retry failure, display price and status, remove',
    (tester) async {
      var fail = true, removed = false;
      final adapter = Adapter((r) async {
        if (r.method == 'DELETE') {
          removed = true;
          return response(200, {'productIds': []});
        }
        final number = int.parse(Uri.parse(r.path).queryParameters['page']!);
        if (number == 2 && fail) {
          fail = false;
          return response(503, null);
        }
        return response(
          200,
          page(
            [
              if (!removed)
                for (
                  var i = (number - 1) * 20 + 1;
                  i <= number * 20 && i <= 21;
                  i++
                )
                  {'product': product(i), 'alerts': []},
            ],
            total: removed ? 0 : 21,
            number: number,
          ),
        );
      });
      await mount(tester, adapter, const FavoritesScreen());
      expect(find.text('NT\$ 1280'), findsWidgets);
      expect(find.text('現貨'), findsWidgets);
      expect(find.text('售完'), findsWidgets);
      await secondPage(tester, adapter);
      expect(find.text('連線失敗，請稍後重試'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('重新讀取'), 200);
      await tester.tap(find.text('重新讀取'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('商品 21'), 200);
      expect(find.text('商品 21'), findsOneWidget);
      expect(
        adapter.requests.where(
          (r) => Uri.parse(r.path).queryParameters['page'] == '2',
        ),
        hasLength(2),
      );
      await tester.tap(find.byTooltip('移除收藏').last);
      await tester.pumpAndSettle();
      expect(writes(adapter).single.path, 'mobile/customer/favorites/p21');
      expect(find.text('目前沒有收藏商品'), findsOneWidget);
    },
  );

  testWidgets('favorite opens product detail', (tester) async {
    final adapter = Adapter(
      (_) async => response(
        200,
        page([
          {'product': product(1)},
        ]),
      ),
    );
    await mount(tester, adapter, const FavoritesScreen());
    await tester.tap(find.text('商品 1'));
    await tester.pumpAndSettle();
    expect(find.text('目的地 /products/p1'), findsOneWidget);
  });

  testWidgets(
    'notifications mark individual without target then all read and refresh styling',
    (tester) async {
      var read = false, all = false;
      final adapter = Adapter((r) async {
        if (r.method == 'POST') {
          read = true;
          all = r.data['all'] == true;
          return response(200, {'updated': 1, 'unread': all ? 0 : 1});
        }
        return response(
          200,
          page(
            [notice(1, read: read), notice(2, read: all)],
            total: 2,
            unread: 2,
          ),
        );
      });
      await mount(tester, adapter, const NotificationsScreen());
      expect(
        tester.widget<Text>(find.text('通知 1')).style!.fontWeight,
        FontWeight.bold,
      );
      await tester.tap(find.text('通知 1'));
      await tester.pumpAndSettle();
      expect(writes(adapter).single.data, {
        'ids': ['n1'],
      });
      expect(
        tester.widget<Text>(find.text('通知 1')).style!.fontWeight,
        FontWeight.normal,
      );
      await tester.tap(find.text('全部標為已讀'));
      await tester.pumpAndSettle();
      expect(writes(adapter).last.data, {'all': true});
      expect(
        writes(adapter).every(
          (r) =>
              r.method == 'POST' &&
              r.path == 'mobile/customer/notifications/read',
        ),
        true,
      );
      expect(
        tester.widget<Text>(find.text('通知 2')).style!.fontWeight,
        FontWeight.normal,
      );
    },
  );

  for (final target in {
    'productId': '/products/p1',
    'orderId': '/orders/stock/o1',
    'preorderOrderId': '/orders/preorder/o1',
  }.entries) {
    testWidgets('notification routes ${target.key} after read ACK', (
      tester,
    ) async {
      final gate = Completer<ResponseBody>();
      final adapter = Adapter(
        (r) async => r.method == 'POST'
            ? gate.future
            : response(200, page([notice(1, target: target.key)])),
      );
      await mount(tester, adapter, const NotificationsScreen());
      await tester.tap(find.text('通知 1'));
      await tester.pump();
      expect(find.text('目的地 ${target.value}'), findsNothing);
      gate.complete(response(200, {'updated': 1, 'unread': 0}));
      await tester.pumpAndSettle();
      expect(find.text('目的地 ${target.value}'), findsOneWidget);
    });
  }

  testWidgets(
    'notification pagination requests second page once and stops at total',
    (tester) async {
      final adapter = Adapter((r) async {
        final number = int.parse(Uri.parse(r.path).queryParameters['page']!);
        return response(
          200,
          page(
            [
              for (
                var i = (number - 1) * 20 + 1;
                i <= number * 20 && i <= 21;
                i++
              )
                notice(i),
            ],
            total: 21,
            number: number,
          ),
        );
      });
      await mount(tester, adapter, const NotificationsScreen());
      await secondPage(tester, adapter);
      await tester.drag(find.byType(ListView), const Offset(0, -4000));
      await tester.pumpAndSettle();
      expect(find.text('通知 21'), findsOneWidget);
      expect(adapter.requests.map((r) => r.path), [
        'mobile/customer/notifications?page=1&pageSize=20&unread=false',
        'mobile/customer/notifications?page=2&pageSize=20&unread=false',
      ]);
    },
  );

  testWidgets(
    'read failure stays in inbox and can retry; initial list failure can reload',
    (tester) async {
      var failGet = true, failPost = true;
      final adapter = Adapter((r) async {
        if (r.method == 'POST') {
          if (failPost) {
            failPost = false;
            return response(400, null);
          }
          return response(200, {'updated': 1, 'unread': 0});
        }
        if (failGet) {
          failGet = false;
          return response(503, null);
        }
        return response(200, page([notice(1, target: 'productId')]));
      });
      await mount(tester, adapter, const NotificationsScreen());
      expect(find.text('連線失敗，請稍後重試'), findsOneWidget);
      await tester.tap(find.text('重新讀取'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('通知 1'));
      await tester.pumpAndSettle();
      expect(find.text('請檢查輸入內容'), findsOneWidget);
      expect(find.text('目的地 /products/p1'), findsNothing);
      await tester.tap(find.text('通知 1'));
      await tester.pumpAndSettle();
      expect(find.text('目的地 /products/p1'), findsOneWidget);
    },
  );

  testWidgets('account shows engagement links and actual unread count', (
    tester,
  ) async {
    final adapter = Adapter(
      (r) async => response(
        200,
        r.path.endsWith('/me')
            ? {
                'email': 'member@example.test',
                'phone': '0912345678',
                'emailVerified': false,
              }
            : page([], total: 0, unread: 8),
      ),
    );
    await mount(tester, adapter, const AccountScreen());
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('通知設定'), findsOneWidget);
    expect(find.text('通知（8 則未讀）'), findsOneWidget);
    await tester.tap(find.text('通知（8 則未讀）'));
    await tester.pumpAndSettle();
    expect(find.text('目的地 /account/notifications'), findsOneWidget);
  });
}
