import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:figura/app.dart';
import 'package:figura/core/api.dart';
import 'package:figura/core/models.dart';
import 'package:figura/core/providers.dart';
import 'package:figura/core/storage.dart';
import 'package:figura/features/support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'api_test.dart' show Adapter, apiFor, response;
import 'shipments_test.dart' show item, page;

const root = '/account/support-tickets';
const orderId = '11111111-1111-4111-8111-111111111111';
const timestamp = '2026-11-25T10:00:00+08:00';
Json ticket({String status = 'WAITING_STAFF', String id = 't1'}) => {
  'id': id,
  'subject': '出貨問題',
  'category': 'SHIPPING',
  'status': status,
  'updatedAt': timestamp,
};
Json detail({String status = 'WAITING_STAFF'}) => {
  'ticket': ticket(status: status),
  'messages': [
    {'authorType': 'CUSTOMER', 'body': '請協助查詢', 'createdAt': timestamp},
    {
      'authorType': 'STAFF',
      'staffUsername': 'staff-demo',
      'body': '測試回覆內容',
      'createdAt': timestamp,
    },
  ],
};
Json paged(List<Json> items) => {
  'items': items,
  'total': items.length,
  'page': 1,
  'pageSize': 20,
};
List<RequestOptions> posts(Adapter a) =>
    a.requests.where((r) => r.method == 'POST').toList();
final uuid = matches(
  RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ),
);

class Session {
  final ShopApi api;
  final Writes writes;
  final GoRouter router;
  Session(this.api, this.writes, this.router);
}

Future<Session> mount(
  WidgetTester tester,
  Adapter adapter,
  String path, {
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
  final writes = Writes(api);
  await writes.restore();
  final container = ProviderContainer(
    overrides: [
      apiProvider.overrideWith((_) => api),
      writesProvider.overrideWith((_) => writes),
    ],
  );
  final router = container.read(routerProvider);
  router.go(path);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return Session(api, writes, router);
}

Future<void> tap(WidgetTester tester, String text) async {
  final finder = find.text(text).last;
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextFormField, '主旨'), '  出貨問題  ');
  await tester.enterText(find.widgetWithText(TextFormField, '內容'), '  請協助查詢  ');
}

void main() {
  for (final kind in ['STOCK', 'PREORDER']) {
    testWidgets(
      'create ticket includes category and selected $kind order with Bearer and UUID',
      (tester) async {
        final adapter = Adapter((r) async {
          if (r.path.contains('order-center')) {
            return response(
              200,
              paged([
                {'id': orderId, 'kind': kind, 'title': '測試商品'},
              ]),
            );
          }
          if (r.method == 'POST') {
            return response(200, {'current': detail(), 'replayed': false});
          }
          if (r.path.endsWith('/t1')) return response(200, detail());
          return response(200, paged([]));
        });
        await mount(tester, adapter, '$root/new');
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tap(tester, '配送');
        await fill(tester);
        await tap(tester, '選擇關聯訂單');
        await tap(tester, '${kind == 'PREORDER' ? '預購' : '現貨'} 測試商品');
        await tap(tester, '送出客服單');
        final request = posts(adapter).single;
        final body = object(request.data);
        expect(request.path, 'mobile/customer/support-tickets');
        expect(request.headers['Authorization'], 'Bearer test-access');
        expect(body['requestId'], uuid);
        expect(body, {
          'requestId': body['requestId'],
          'category': 'SHIPPING',
          'subject': '出貨問題',
          'body': '請協助查詢',
          (kind == 'PREORDER' ? 'preorderOrderId' : 'orderId'): orderId,
        });
        expect(find.byType(SupportTicketScreen), findsOneWidget);
      },
    );
  }

  testWidgets(
    'order lookup failure is optional and empty ticket is validated',
    (tester) async {
      final adapter = Adapter((r) async {
        if (r.path.contains('order-center')) return response(503, null);
        if (r.method == 'POST') return response(200, {'current': detail()});
        return response(200, detail());
      });
      await mount(tester, adapter, '$root/new');
      await tap(tester, '送出客服單');
      expect(posts(adapter), isEmpty);
      expect(find.text('請填寫主旨'), findsOneWidget);
      await fill(tester);
      await tap(tester, '選擇關聯訂單');
      expect(find.text('重新讀取'), findsOneWidget);
      await tap(tester, '返回');
      await tap(tester, '送出客服單');
      expect(
        object(posts(adapter).single.data).keys,
        unorderedEquals(['requestId', 'category', 'subject', 'body']),
      );
    },
  );

  testWidgets(
    'CLOSED shows conversation with staff name and new ticket prompt without reply form',
    (tester) async {
      final adapter = Adapter(
        (_) async => response(200, detail(status: 'CLOSED')),
      );
      await mount(tester, adapter, '$root/t1');
      expect(find.text('已結案'), findsOneWidget);
      expect(find.text('顧客'), findsOneWidget);
      expect(find.text('客服 · staff-demo'), findsOneWidget);
      expect(find.text('測試回覆內容'), findsOneWidget);
      expect(find.text('客服單已結案，請建立新的客服單。'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('送出回覆'), findsNothing);
      expect(posts(adapter), isEmpty);
    },
  );

  testWidgets('reply ACK then failed GET offers read only without resending', (
    tester,
  ) async {
    var reads = 0;
    final adapter = Adapter((r) async {
      if (r.method == 'POST') return response(200, {'current': detail()});
      if (!r.path.endsWith('/t1')) return response(200, {});
      reads++;
      return reads == 2 ? response(503, null) : response(200, detail());
    });
    final session = await mount(tester, adapter, '$root/t1');
    await tester.enterText(
      find.widgetWithText(TextFormField, '回覆內容'),
      '  補充內容  ',
    );
    await tap(tester, '送出回覆');
    final request = posts(adapter).single;
    final body = object(request.data);
    expect(request.path, 'mobile/customer/support-tickets/t1/messages');
    expect(body, {'requestId': body['requestId'], 'body': '補充內容'});
    expect(body['requestId'], uuid);
    expect(session.writes.pending, isNull);
    await tap(tester, '重新讀取');
    expect(posts(adapter), hasLength(1));
    expect(reads, 3);
    expect(find.text('送出回覆'), findsOneWidget);
  });

  for (final reply in [false, true]) {
    testWidgets(
      'unknown ${reply ? 'reply' : 'creation'} survives restart and PendingBanner replays exact body',
      (tester) async {
        final store = MemoryStore();
        final adapter = Adapter((r) async {
          if (r.method == 'POST') return postsCountFailure(r);
          return response(200, detail());
        });
        final session = await mount(
          tester,
          adapter,
          reply ? '$root/t1' : '$root/new',
          store: store,
        );
        if (reply) {
          await tester.enterText(
            find.widgetWithText(TextFormField, '回覆內容'),
            '補充內容',
          );
        } else {
          await fill(tester);
        }
        await tap(tester, reply ? '送出回覆' : '送出客服單');
        expect(session.writes.pending, isNotNull);
        final original = jsonEncode(posts(adapter).single.data);
        expect(posts(adapter), hasLength(1));
        final nextAdapter = Adapter(
          (r) async => response(
            200,
            r.method == 'POST'
                ? {'current': detail(), 'replayed': true}
                : detail(),
          ),
        );
        // Recreate the provider container and restore the owner-scoped secure-store fixture.
        await tester.pumpWidget(const SizedBox());
        final next = await mount(
          tester,
          nextAdapter,
          reply ? '$root/t1' : '$root/new',
          store: store,
        );
        expect(next.writes.pending!.replayable, isTrue);
        final disabled = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, reply ? '送出回覆' : '送出客服單'),
        );
        expect(disabled.onPressed, isNull);
        await tap(tester, '以原編號核對／重試');
        expect(posts(nextAdapter), hasLength(1));
        expect(jsonEncode(posts(nextAdapter).single.data), original);
        expect(next.writes.pending, isNull);
        expect(await store.read('pending_owner'), isNull);
        expect(find.byType(SupportTicketScreen), findsOneWidget);
      },
    );
  }

  testWidgets(
    'tracking timeline uses all Chinese labels and test carrier disclaimer',
    (tester) async {
      final adapter = Adapter(
        (_) async => response(200, {
          'shipmentId': 's1',
          'method': 'CVS',
          'carrier': 'TEST',
          'trackingNumber': 'TEST123',
          'testCarrier': true,
          'events': [
            for (final code in trackingLabels.keys)
              {
                'code': code,
                'description': '測試事件 $code',
                'occurredAt': timestamp,
              },
          ],
        }),
      );
      await mount(tester, adapter, '/account/shipments/s1/tracking');
      expect(find.text('測試物流，非真實物流資訊'), findsOneWidget);
      expect(find.text('貨件號：TEST123'), findsOneWidget);
      for (final label in trackingLabels.values) {
        await tester.scrollUntilVisible(find.text(label), 160);
        expect(find.text(label), findsOneWidget);
      }
      expect(
        adapter.requests.last.path,
        'mobile/customer/shipments/s1/tracking',
      );
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer test-access',
      );
    },
  );

  testWidgets('only shipped or delivered cards have tracking entry', (
    tester,
  ) async {
    final adapter = Adapter((r) async {
      if (r.path.contains('/tracking')) {
        return response(200, {
          'shipmentId': 's1',
          'method': 'HOME',
          'testCarrier': false,
          'events': [],
        });
      }
      return response(
        200,
        page([
          item('s1', status: 'SHIPPED', mergeable: false),
          item('s2', status: 'READY'),
          item('s3', status: 'DELIVERED', mergeable: false),
        ]),
      );
    });
    await mount(tester, adapter, '/account/shipments');
    for (final id in ['s1', 's2', 's3']) {
      await tester.scrollUntilVisible(find.text('出貨單 $id'), 200);
      final card = find
          .ancestor(of: find.text('出貨單 $id'), matching: find.byType(Card))
          .first;
      expect(
        find.descendant(of: card, matching: find.text('物流追蹤')),
        id == 's2' ? findsNothing : findsOneWidget,
      );
    }
    await tap(tester, '物流追蹤');
    expect(find.text('目前沒有物流事件'), findsOneWidget);
    expect(find.text('測試物流，非真實物流資訊'), findsNothing);
    expect(adapter.requests.any((r) => r.path.endsWith('/tracking')), isTrue);
  });

  testWidgets(
    'pending reply 409 refreshes a now CLOSED ticket without another write',
    (tester) async {
      var closed = false;
      final adapter = Adapter((r) async {
        if (r.method == 'POST') {
          if (closed) return response(409, null);
          throw DioException(
            requestOptions: r,
            type: DioExceptionType.connectionError,
          );
        }
        return response(
          200,
          detail(status: closed ? 'CLOSED' : 'WAITING_STAFF'),
        );
      });
      final session = await mount(tester, adapter, '$root/t1');
      await tester.enterText(
        find.widgetWithText(TextFormField, '回覆內容'),
        '補充內容',
      );
      await tap(tester, '送出回覆');
      final original = jsonEncode(posts(adapter).single.data);
      closed = true;
      await tap(tester, '以原編號核對／重試');
      expect(posts(adapter), hasLength(2));
      expect(jsonEncode(posts(adapter).last.data), original);
      expect(session.writes.pending, isNull);
      expect(find.text('客服單已結案，請建立新的客服單。'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
    },
  );

  for (final signedIn in [false, true]) {
    testWidgets(
      'policy public requests omit Bearer (${signedIn ? 'member' : 'guest'}) and hide unpublished body',
      (tester) async {
        final adapter = Adapter((r) async {
          final policy = {
            'slug': 'privacy',
            'title': '隱私政策',
            'published': false,
            'body': '不應顯示的草稿',
          };
          return response(200, r.path == 'site-pages' ? [policy] : policy);
        });
        await mount(tester, adapter, '/account/site-pages', signedIn: signedIn);
        expect(find.text('條款審核中'), findsOneWidget);
        expect(find.text('不應顯示的草稿'), findsNothing);
        await tap(tester, '隱私政策');
        expect(find.text('條款審核中'), findsOneWidget);
        expect(find.text('不應顯示的草稿'), findsNothing);
        final publicRequests = adapter.requests
            .where((r) => r.path.startsWith('site-pages'))
            .toList();
        expect(publicRequests.map((r) => r.path), [
          'site-pages',
          'site-pages/privacy',
        ]);
        expect(
          publicRequests.every((r) => !r.headers.containsKey('Authorization')),
          isTrue,
        );
      },
    );
  }

  testWidgets('published policy preserves plain text and newlines', (
    tester,
  ) async {
    final adapter = Adapter(
      (r) async => response(
        200,
        r.path == 'site-pages'
            ? []
            : {
                'title': '測試政策',
                'published': true,
                'body': '第一行\n<b>純文字</b>\n第三行',
              },
      ),
    );
    await mount(tester, adapter, '/account/site-pages/terms', signedIn: false);
    expect(find.text('測試政策'), findsOneWidget);
    expect(find.text('第一行\n<b>純文字</b>\n第三行'), findsOneWidget);
    expect(find.text('條款審核中'), findsNothing);
  });

  testWidgets(
    'guest member page opens policies and protected support redirects to login',
    (tester) async {
      final adapter = Adapter((_) async => response(200, []));
      final session = await mount(tester, adapter, '/account', signedIn: false);
      expect(adapter.requests, isEmpty);
      await tap(tester, '政策與說明');
      expect(find.byType(SitePagesScreen), findsOneWidget);
      session.router.go(root);
      await tester.pumpAndSettle();
      expect(session.router.routeInformationProvider.value.uri.path, '/login');
      expect(adapter.requests.every((r) => r.path == 'site-pages'), isTrue);
    },
  );

  testWidgets('member entry and ticket list translate all statuses', (
    tester,
  ) async {
    final adapter = Adapter((r) async {
      if (r.path.endsWith('/me')) {
        return response(200, {
          'email': 'member@example.test',
          'phone': '0912345678',
        });
      }
      if (r.path.contains('notifications?')) {
        return response(200, {'unread': 0});
      }
      return response(
        200,
        paged([
          for (final status in supportStatuses.keys)
            ticket(status: status, id: status),
        ]),
      );
    });
    await mount(tester, adapter, '/account');
    await tap(tester, '客服中心');
    for (final status in supportStatuses.values) {
      await tester.scrollUntilVisible(find.textContaining(status), 100);
      expect(find.textContaining(status), findsOneWidget);
    }
  });
}

Future<ResponseBody> postsCountFailure(RequestOptions request) async =>
    throw DioException(
      requestOptions: request,
      type: DioExceptionType.connectionError,
    );
