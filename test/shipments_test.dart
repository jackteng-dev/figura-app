import 'dart:async';

import 'package:dio/dio.dart';
import 'package:figura/app.dart';
import 'package:figura/core/api.dart';
import 'package:figura/core/models.dart';
import 'package:figura/core/providers.dart';
import 'package:figura/core/storage.dart';
import 'package:figura/features/auth.dart';
import 'package:figura/features/shipments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'api_test.dart' show Adapter, apiFor, response;

Json item(
  String id, {
  int version = 3,
  String status = 'READY',
  String? waiting,
  bool held = false,
  bool mergeable = true,
}) => {
  'shipment': {
    'id': id,
    'version': version,
    'status': status,
    'waitingFor': waiting,
    'method': 'HOME',
    'methodName': '宅配',
    'feeTwd': 80,
    'goodsTwd': 1200,
    'heldAt': held ? '2026-11-25T10:00:00+08:00' : null,
    // Verify the date uses the shop's timezone, including across midnight.
    'storageUntil': held ? '2027-01-23T18:00:00Z' : null,
    'orders': [
      {'id': 'order-$id', 'kind': 'STOCK', 'title': '模型 $id'},
      {'id': 'pre-$id', 'kind': 'PREORDER', 'title': '預購 $id'},
    ],
  },
  'canHold': mergeable && !held,
  'canRelease': held,
  'mergeable': mergeable,
  'blockedReason': mergeable ? null : '有訂單付款待核對或退貨中',
};

Json page(List<Json> items, {int? total, int number = 1}) => {
  'items': items,
  'total': total ?? items.length,
  'page': number,
  'pageSize': 20,
  'storageDays': 45,
};

final uuid = matches(
  RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ),
);

List<RequestOptions> posts(Adapter adapter) =>
    adapter.requests.where((r) => r.method == 'POST').toList();

Future<Writes> mount(
  WidgetTester tester,
  Adapter adapter, {
  MemoryStore? store,
  bool account = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = apiFor(adapter, store ?? MemoryStore())
    ..accessToken = 'test-access'
    ..customer = {'id': 'owner'};
  final writes = Writes(api);
  await writes.restore();
  final router = GoRouter(
    initialLocation: account ? '/account' : '/account/shipments',
    routes: [
      ShellRoute(
        builder: (_, state, child) =>
            ShopShell(path: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/account', builder: (_, _) => const AccountScreen()),
          GoRoute(
            path: '/account/shipments',
            builder: (_, _) => const ShipmentsScreen(),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiProvider.overrideWith((_) => api),
        writesProvider.overrideWith((_) => writes),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return writes;
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    350,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> selectTwo(WidgetTester tester) async {
  await tapVisible(tester, find.byKey(const ValueKey('merge-a')));
  await tapVisible(tester, find.byKey(const ValueKey('merge-b')));
}

Future<void> confirmMerge(WidgetTester tester) async {
  await tester.tap(find.text('合併選取的出貨單'));
  await tester.pumpAndSettle();
  expect(
    find.textContaining('只合併寄送，不改訂單金額與付款；運費差額會由店家審核，目前不會自動退款'),
    findsOneWidget,
  );
  await tester.tap(find.text('確認合併'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('account entry opens shipments', (tester) async {
    final adapter = Adapter(
      (r) async => response(
        200,
        r.path.endsWith('/me')
            ? {
                'email': 'member@example.test',
                'phone': '0912345678',
                'emailVerified': true,
              }
            : r.path.contains('notifications?')
            ? {'unread': 0}
            : page([]),
      ),
    );
    await mount(tester, adapter, account: true);
    await tapVisible(tester, find.text('我的出貨'));
    expect(find.text('目前沒有出貨單'), findsOneWidget);
    expect(
      adapter.requests.last.path,
      'mobile/customer/shipments?page=1&pageSize=20',
    );
  });

  testWidgets(
    'list shows storage date, amounts, method, orders and blocked reason',
    (tester) async {
      final adapter = Adapter(
        (_) async => response(
          200,
          page([
            item(
              'a',
              held: true,
              mergeable: false,
              status: 'WAITING',
              waiting: 'REVIEW',
            ),
          ]),
        ),
      );
      await mount(tester, adapter);
      expect(find.text('暫存期間不會出貨，期限 45 天（測試設定，正式政策待核定）。'), findsOneWidget);
      expect(find.text('等待中 · 付款待核對或退貨中'), findsOneWidget);
      expect(find.text('暫存至 2027/01/24'), findsOneWidget);
      expect(find.text('配送方式：宅配'), findsOneWidget);
      expect(find.text('NT\$ 80'), findsOneWidget);
      expect(find.text('NT\$ 1200'), findsOneWidget);
      expect(find.text('現貨 模型 a · order-a'), findsOneWidget);
      expect(find.text('預購 預購 a · pre-a'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('merge-a')));
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const ValueKey('merge-a')))
            .onChanged,
        isNull,
      );
      expect(find.text('有訂單付款待核對或退貨中'), findsOneWidget);
    },
  );

  for (final entry in {
    'PAYMENT': '等待付款',
    'BALANCE': '等待尾款',
    'ARRIVAL': '等待到貨',
    'FEE': '承擔運費的訂單已取消，請聯絡客服',
  }.entries) {
    testWidgets('WAITING explains ${entry.key}', (tester) async {
      await mount(
        tester,
        Adapter(
          (_) async => response(
            200,
            page([item('a', status: 'WAITING', waiting: entry.key)]),
          ),
        ),
      );
      expect(find.text('等待中 · ${entry.value}'), findsOneWidget);
    });
  }

  for (final entry in {
    'READY': '可出貨',
    'SHIPPED': '已出貨',
    'DELIVERED': '已送達',
    'CANCELLED': '已取消',
  }.entries) {
    testWidgets('list labels ${entry.key}', (tester) async {
      await mount(
        tester,
        Adapter(
          (_) async => response(
            200,
            page([
              item('a', status: entry.key, mergeable: entry.key == 'READY'),
            ]),
          ),
        ),
      );
      expect(find.text(entry.value), findsOneWidget);
    });
  }

  for (final held in [false, true]) {
    testWidgets(
      '${held ? 'release' : 'hold'} sends UUID and displayed version with bearer',
      (tester) async {
        var changed = false;
        final adapter = Adapter((r) async {
          if (r.method == 'POST') {
            changed = true;
            return response(200, {
              'shipment': item('a', held: !held, version: 8),
              'replayed': false,
            });
          }
          return response(
            200,
            page([
              item('a', held: changed ? !held : held, version: changed ? 8 : 7),
            ]),
          );
        });
        final writes = await mount(tester, adapter);
        await tapVisible(tester, find.text(held ? '取消暫存、安排寄送' : '暫存到倉庫'));
        final request = posts(adapter).single;
        expect(
          request.path,
          'mobile/customer/shipments/a/${held ? 'release' : 'hold'}',
        );
        expect(request.headers['Authorization'], 'Bearer test-access');
        expect(request.data, {'requestId': uuid, 'expectedVersion': 7});
        expect(writes.pending, isNull);
        expect(adapter.requests.where((r) => r.method == 'GET'), hasLength(2));
        expect(find.text(held ? '暫存到倉庫' : '取消暫存、安排寄送'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'merge needs two, allows cancel, sends exact refs and displays adjustment',
    (tester) async {
      var merged = false;
      final adapter = Adapter((r) async {
        if (r.method == 'POST') {
          merged = true;
          return response(200, {
            'shipment': item('merged'),
            'adjustment': {'creditTwd': 80, 'status': 'PENDING_REVIEW'},
            'replayed': false,
          });
        }
        return response(
          200,
          page(merged ? [item('merged')] : [item('a'), item('b', version: 9)]),
        );
      });
      await mount(tester, adapter);
      FilledButton button() =>
          tester.widget(find.widgetWithText(FilledButton, '合併選取的出貨單'));
      expect(button().onPressed, isNull);
      await tapVisible(tester, find.byKey(const ValueKey('merge-a')));
      expect(button().onPressed, isNull);
      expect(posts(adapter), isEmpty);
      await tapVisible(tester, find.byKey(const ValueKey('merge-b')));
      expect(button().onPressed, isNotNull);
      await tester.tap(find.text('合併選取的出貨單'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(posts(adapter), isEmpty);
      await confirmMerge(tester);
      expect(posts(adapter).single.path, 'mobile/customer/shipments/merge');
      expect(posts(adapter).single.data, {
        'requestId': uuid,
        'shipments': [
          {'id': 'a', 'expectedVersion': 3},
          {'id': 'b', 'expectedVersion': 9},
        ],
      });
      expect(find.text('NT\$ 80 · 待店家審核\n目前不會自動退款。'), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.text('出貨單 merged'), findsOneWidget);
      expect(find.text('已選 0 張（合併需 2–10 張）'), findsOneWidget);
    },
  );

  for (final merge in [false, true]) {
    testWidgets(
      '409 on ${merge ? 'merge' : 'hold'} reloads and clears selected versions',
      (tester) async {
        var reads = 0;
        final adapter = Adapter((r) async {
          if (r.method == 'POST') return response(409, null);
          reads++;
          return response(200, page([item('a', version: reads), item('b')]));
        });
        final writes = await mount(tester, adapter);
        if (merge) {
          await selectTwo(tester);
          await confirmMerge(tester);
        } else {
          await tapVisible(tester, find.text('暫存到倉庫').first);
        }
        expect(find.text('出貨單已變更'), findsOneWidget);
        expect(reads, 2);
        expect(writes.pending, isNull);
        expect(find.text('已選 0 張（合併需 2–10 張）'), findsOneWidget);
        await tapVisible(tester, find.text('暫存到倉庫').first);
        expect(posts(adapter).last.data['expectedVersion'], 2);
      },
    );
  }

  for (final merge in [false, true]) {
    testWidgets(
      'unknown ${merge ? 'merge' : 'hold'} survives restore and only replays original body',
      (tester) async {
        var attempts = 0;
        final store = MemoryStore();
        final adapter = Adapter((r) async {
          if (r.method == 'POST') {
            attempts++;
            return attempts == 1
                ? response(503, null)
                : response(200, {
                    'shipment': item('result'),
                    if (merge)
                      'adjustment': {
                        'creditTwd': 50,
                        'status': 'PENDING_REVIEW',
                      },
                    'replayed': true,
                  });
          }
          return response(200, page([item('a'), item('b')]));
        });
        var writes = await mount(tester, adapter, store: store);
        if (merge) {
          await selectTwo(tester);
          await confirmMerge(tester);
        } else {
          await tapVisible(tester, find.text('暫存到倉庫').first);
        }
        expect(posts(adapter), hasLength(1));
        expect(writes.pending!.replayable, isTrue);
        expect(await store.read('pending_owner'), isNotNull);
        await tester.pumpWidget(const SizedBox());
        writes = await mount(tester, adapter, store: store);
        expect(writes.pending!.body, posts(adapter).first.data);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, '合併選取的出貨單'),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('以原編號核對／重試'));
        await tester.pumpAndSettle();
        expect(posts(adapter), hasLength(2));
        expect(posts(adapter).last.path, posts(adapter).first.path);
        expect(posts(adapter).last.data, posts(adapter).first.data);
        expect(writes.pending, isNull);
        expect(await store.read('pending_owner'), isNull);
        expect(adapter.requests.where((r) => r.method == 'GET'), hasLength(3));
        if (merge) {
          expect(find.textContaining('NT\$ 50 · 待店家審核'), findsOneWidget);
        }
      },
    );
  }

  testWidgets('409 during pending replay refreshes shipment screen', (
    tester,
  ) async {
    var attempts = 0, reads = 0;
    final adapter = Adapter((r) async {
      if (r.method == 'POST') {
        return response(++attempts == 1 ? 503 : 409, null);
      }
      reads++;
      return response(200, page([item('a', version: reads)]));
    });
    final writes = await mount(tester, adapter);
    await tapVisible(tester, find.text('暫存到倉庫'));
    await tester.tap(find.text('以原編號核對／重試'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(writes.pending, isNull);
    expect(posts(adapter).last.data, posts(adapter).first.data);
    // The first snackbar may still be queued ahead of the conflict notice.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('出貨單已變更'), findsOneWidget);
  });

  testWidgets('ACK followed by failed GET only retries reading', (
    tester,
  ) async {
    var reads = 0;
    final adapter = Adapter((r) async {
      if (r.method == 'POST') {
        return response(200, {'shipment': item('a', held: true)});
      }
      if (++reads == 2) return response(503, null);
      return response(200, page([item('a', held: reads > 1)]));
    });
    final writes = await mount(tester, adapter);
    await tapVisible(tester, find.text('暫存到倉庫'));
    expect(writes.pending, isNull);
    expect(find.text('以原編號核對／重試'), findsNothing);
    await tester.tap(find.text('重新讀取'));
    await tester.pumpAndSettle();
    expect(reads, 3);
    expect(posts(adapter), hasLength(1));
    expect(find.text('暫存至 2027/01/24'), findsOneWidget);
  });

  testWidgets(
    'pagination guards duplicate loads, retries failed page, stops at total',
    (tester) async {
      final gate = Completer<ResponseBody>();
      var secondAttempts = 0;
      final adapter = Adapter((r) async {
        final number = int.parse(Uri.parse(r.path).queryParameters['page']!);
        if (number == 1) {
          return response(
            200,
            page([for (var i = 0; i < 20; i++) item('s$i')], total: 21),
          );
        }
        if (++secondAttempts == 1) return gate.future;
        return response(200, page([item('last')], total: 21, number: 2));
      });
      await mount(tester, adapter);
      final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
      for (var i = 0; i < 40 && secondAttempts == 0; i++) {
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.drag(find.byType(ListView), const Offset(0, -1000));
      await tester.pump();
      expect(secondAttempts, 1);
      gate.complete(response(503, null));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('重新讀取'));
      expect(secondAttempts, 2);
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.text('出貨單 last'), findsOneWidget);
      expect(secondAttempts, 2);
      expect(
        adapter.requests.last.path,
        'mobile/customer/shipments?page=2&pageSize=20',
      );
    },
  );
}
