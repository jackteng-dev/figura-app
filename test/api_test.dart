import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpsy_shop/core/api.dart';
import 'package:elpsy_shop/core/models.dart';
import 'package:elpsy_shop/core/storage.dart';

class Adapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) respond;
  final List<RequestOptions> requests = [];
  Adapter(this.respond);
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async {
    requests.add(o);
    return respond(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody response(int status, dynamic data) => ResponseBody.fromString(
  jsonEncode({'code': status < 300 ? 0 : 1, 'data': data}),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);
Json tokens(String access, String refresh) => {
  'accessToken': access,
  'refreshToken': refresh,
  'customer': {'id': 'owner', 'username': 'member', 'displayName': '會員'},
  'expiresIn': 900,
};
ShopApi apiFor(Adapter adapter, PrivateStore store) => ShopApi(
  store: store,
  baseUrl: 'https://shop.example/ELPSY/api/',
  client: Dio()..httpClientAdapter = adapter,
);
void main() {
  test('release requires HTTPS and debug HTTP is restricted to known loopback hosts', () {
    expect(
      () => validateBase('http://store.example/ELPSY/api/', development: true),
      throwsA(isA<ShopError>()),
    );
    expect(
      () => validateBase('http://127.0.0.1/ELPSY/api/', development: false),
      throwsA(isA<ShopError>()),
    );
    expect(
      validateBase('http://10.0.2.2/ELPSY/api/', development: true).host,
      '10.0.2.2',
    );
    expect(
      () => validateBase(
        'https://u:p@shop.example/ELPSY/api/',
        development: false,
      ),
      throwsA(isA<ShopError>()),
    );
  });
  test(
    'concurrent 401 share one refresh, retry only the rejected calls',
    () async {
      var refreshes = 0;
      final adapter = Adapter((o) async {
        if (o.path.endsWith('auth/refresh')) {
          refreshes++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return response(200, tokens('new', 'next'));
        }
        if (o.headers['Authorization'] == 'Bearer old') {
          return response(401, null);
        }
        return response(200, {'version': 1});
      });
      final store = MemoryStore();
      await store.write('refresh_token', 'old-refresh');
      final api = apiFor(adapter, store)
        ..accessToken = 'old'
        ..customer = {'id': 'owner'};
      await Future.wait([
        api.request('GET', 'cart'),
        api.request('GET', 'addresses'),
      ]);
      expect(refreshes, 1);
      expect(api.accessToken, 'new');
      expect(await store.read('refresh_token'), 'next');
      expect(store.values.keys, ['refresh_token']);
    },
  );
  test('network failure never retries a business write; refresh failure preserves credentials', () async {
    final adapter = Adapter(
      (o) async => throw DioException(
        requestOptions: o,
        type: DioExceptionType.connectionError,
      ),
    );
    final store = MemoryStore();
    await store.write('refresh_token', 'refresh');
    final api = apiFor(adapter, store)
      ..accessToken = 'access'
      ..customer = {'id': 'owner'};
    await expectLater(
      api.request('POST', 'orders', body: {'requestId': 'one'}),
      throwsA(isA<ShopError>().having((e) => e.uncertain, 'uncertain', true)),
    );
    expect(adapter.requests.length, 1);
    await expectLater(api.refresh(), throwsA(isA<ShopError>()));
    expect(await store.read('refresh_token'), 'refresh');
  });
  test('logout cannot be undone by a delayed refresh response', () async {
    final gate = Completer<void>();
    final adapter = Adapter((o) async {
      if (o.path.endsWith('auth/refresh')) {
        await gate.future;
        return response(200, tokens('late', 'late-refresh'));
      }
      return response(200, null);
    });
    final store = MemoryStore();
    await store.write('refresh_token', 'refresh');
    final api = apiFor(adapter, store)
      ..accessToken = 'access'
      ..customer = {'id': 'owner'};
    final refreshing = api.refresh();
    await Future<void>.delayed(Duration.zero);
    final loggingOut = api.logout();
    gate.complete();
    await Future.wait([refreshing, loggingOut]);
    expect(api.signedIn, false);
    expect(await store.read('refresh_token'), null);
    expect(
      adapter.requests.any(
        (o) =>
            o.path.endsWith('auth/logout') &&
            o.data['refreshToken'] == 'late-refresh',
      ),
      true,
    );
  });
  test('unknown acknowledged operation survives restart and replays the exact original body', () async {
    var attempts = 0;
    final adapter = Adapter((o) async {
      attempts++;
      return attempts == 1
          ? response(503, null)
          : response(200, {
              'order': {'id': 'same'},
            });
    });
    final store = MemoryStore();
    final api = apiFor(adapter, store)
      ..accessToken = 'access'
      ..customer = {'id': 'owner'};
    final writes = Writes(api);
    await expectLater(
      writes.run('POST', 'orders', {
        'requestId': 'original',
        'cartVersion': 2,
      }, replayable: true),
      throwsA(isA<ShopError>()),
    );
    expect(writes.pending, isNotNull);
    final restarted = Writes(api);
    await restarted.restore();
    await expectLater(
      restarted.run('POST', 'orders', {'requestId': 'new'}),
      throwsA(isA<ShopError>()),
    );
    await restarted.retry();
    expect(adapter.requests[0].data, adapter.requests[1].data);
    expect(restarted.pending, null);
    expect(await store.read('pending_owner'), null);
  });
  test(
    'versioned cart writes require read reconciliation, never blind retry',
    () async {
      final adapter = Adapter((o) async => response(503, null));
      final api = apiFor(adapter, MemoryStore())
        ..accessToken = 'a'
        ..customer = {'id': 'owner'};
      final writes = Writes(api);
      await expectLater(
        writes.run('PUT', 'cart/items/sku', {
          'quantity': 2,
          'expectedVersion': 1,
        }),
        throwsA(isA<ShopError>()),
      );
      await expectLater(writes.retry(), throwsA(isA<ShopError>()));
      expect(adapter.requests.length, 1);
      await writes.confirmAfterRead();
      expect(writes.pending, null);
    },
  );
  test('confirmed ACK is cleared before any later read failure', () async {
    final adapter = Adapter(
      (o) async => o.method == 'POST'
          ? response(200, {
              'order': {'id': 'o'},
            })
          : response(503, null),
    );
    final api = apiFor(adapter, MemoryStore())
      ..accessToken = 'a'
      ..customer = {'id': 'owner'};
    final writes = Writes(api);
    await writes.run('POST', 'orders', {'requestId': 'one'}, replayable: true);
    await expectLater(
      api.request('GET', 'orders/o'),
      throwsA(isA<ShopError>()),
    );
    expect(writes.pending, null);
    await expectLater(writes.retry(), throwsA(isA<ShopError>()));
  });
  test('pending data is isolated to its authenticated owner', () async {
    final store = MemoryStore();
    await store.write(
      'pending_owner',
      jsonEncode(
        PendingWrite(
          owner: 'owner',
          method: 'POST',
          path: 'orders',
          body: {'requestId': 'one'},
          replayable: true,
        ).toJson(),
      ),
    );
    final api = apiFor(Adapter((_) async => response(200, null)), store)
      ..accessToken = 'a'
      ..customer = {'id': 'other'};
    final writes = Writes(api);
    await writes.restore();
    expect(writes.pending, null);
    api.customer = {'id': 'owner'};
    await writes.restore();
    expect(writes.pending?.owner, 'owner');
  });
  test(
    'invalid restored refresh clears credentials; temporary failure does not',
    () async {
      final store = MemoryStore();
      await store.write('refresh_token', 'expired');
      final api = apiFor(Adapter((_) async => response(401, null)), store);
      await api.restore();
      expect(api.signedIn, false);
      expect(await store.read('refresh_token'), null);
    },
  );
  test(
    'stock local times and preorder offset times map to the same instant',
    () {
      expect(
        shopTime('2026-10-07T10:00:00'),
        shopTime('2026-10-07T10:00:00+08:00'),
      );
      expect(dateLabel('2026-10-07T02:00:00Z'), '2026/10/07 10:00');
      expect(dateLabel('2026-11-07'), '2026/11/07');
    },
  );
}
