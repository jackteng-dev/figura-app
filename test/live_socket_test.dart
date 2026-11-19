// Opt-in real backend test. Fixtures and credentials must be private, disposable data.
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:figura/core/api.dart';
import 'package:figura/core/models.dart';
import 'package:figura/core/storage.dart';

void main() {
  const base = String.fromEnvironment('API_BASE_URL');
  test('real native cart/address/stock/preorder checkout, payment and own progress', () async {
    const username = String.fromEnvironment('APP_TEST_USERNAME'),
        password = String.fromEnvironment('APP_TEST_PASSWORD');
    const product = String.fromEnvironment('APP_TEST_PRODUCT'),
        sku = String.fromEnvironment('APP_TEST_SKU'),
        batch = String.fromEnvironment('APP_TEST_BATCH');
    final api = ShopApi(store: MemoryStore(), baseUrl: base, development: true),
        writes = Writes(api);
    await api.login(username, password);
    expect(object(await api.publicGet('products/$product'))['id'], product);
    final addressId = const Uuid().v4();
    final address = object(
      await writes.run('PUT', 'addresses/$addressId', {
        'expectedVersion': 0,
        'recipientName': '合成收件人',
        'phone': '0912345678',
        'postalCode': '100',
        'city': '測試市',
        'district': '測試區',
        'street': '合成路 1 號',
      }),
    );
    final cart = object(await api.request('GET', 'cart'));
    await writes.run('PUT', 'cart/items/$sku', {
      'expectedVersion': cart['version'],
      'quantity': 1,
    });
    final ready = object(await api.request('GET', 'cart'));
    final stockBody = <String, dynamic>{
      'requestId': const Uuid().v4(),
      'cartVersion': ready['version'],
      'addressId': addressId,
      'addressVersion': address['version'],
      'expectedSubtotalTwd': ready['subtotalTwd'],
    };
    final stock = object(
      object(
        await writes.run('POST', 'orders', stockBody, replayable: true),
      )['order'],
    );
    final replay = object(await api.request('POST', 'orders', body: stockBody));
    expect(object(replay['order'])['id'], stock['id']);
    Future<void> pay(Json order, bool pre) async {
      final res = pre ? 'preorders' : 'orders', id = order['id'];
      final p = object(
        object(
          await writes.run('POST', '$res/$id/mock-payments', {
            'requestId': const Uuid().v4(),
            'expectedOrderVersion': order['version'],
          }, replayable: true),
        )['payment'],
      );
      final r = object(
        await writes.run(
          'POST',
          '${pre ? 'preorder-payments' : 'mock-payments'}/${p['id']}/simulate',
          {'eventId': const Uuid().v4(), 'outcome': 'SUCCESS'},
          replayable: true,
        ),
      );
      expect(object(r['order'])['status'], 'PAID');
      expect(object(await api.request('GET', '$res/$id'))['status'], 'PAID');
    }

    await pay(stock, false);
    final pre = object(
      object(
        await writes.run('POST', 'preorders', {
          'requestId': const Uuid().v4(),
          'batchId': batch,
          'quantity': 1,
          'addressId': addressId,
          'addressVersion': address['version'],
          'expectedSubtotalTwd': 1800,
        }, replayable: true),
      )['order'],
    );
    await pay(pre, true);
    expect(
      object(
        await api.request('GET', 'preorders/${pre['id']}'),
      )['fulfillment']['allocatedQuantity'],
      0,
    );
    expect(
      objects(object(await api.request('GET', 'orders'))['items'])
          .any((o) => o['id'] == stock['id']),
      true,
    );
    expect(
      objects(object(await api.request('GET', 'preorders'))['items'])
          .any((o) => o['id'] == pre['id']),
      true,
    );
    // 統一訂單中心：同一個列表看得到剛建立的現貨與預購訂單
    final center = object(
      await api.request(
        'GET',
        'order-center?kind=ALL&stage=ALL&sort=NEWEST&page=1&pageSize=50',
      ),
    );
    final centerIds = objects(center['items']).map((o) => o['id']).toSet();
    expect(centerIds.containsAll({stock['id'], pre['id']}), true);
    expect(
      objects(
        object(
          await api.request('GET', 'order-center?kind=PREORDER&page=1'),
        )['items'],
      ).every((o) => o['kind'] == 'PREORDER'),
      true,
    );
    // 統一購物車：現貨＋預購同一購物車，一次結帳拆成兩張訂單
    var mixed = object(await api.request('GET', 'cart'));
    await writes.run('PUT', 'cart/items/$sku', {
      'expectedVersion': mixed['version'],
      'quantity': 1,
    });
    mixed = object(await api.request('GET', 'cart'));
    await writes.run('PUT', 'cart/preorders/$batch', {
      'expectedVersion': mixed['version'],
      'quantity': 1,
    });
    final quote = object(await api.request('GET', 'checkout/quote'));
    expect(objects(quote['groups']).length, 2);
    final placed = object(
      await writes.run('POST', 'checkout', {
        'requestId': const Uuid().v4(),
        'cartVersion': quote['cartVersion'],
        'addressId': addressId,
        'addressVersion': address['version'],
        'expectedTotalTwd': quote['totalTwd'],
      }, replayable: true),
    );
    expect(objects(placed['orders']).map((o) => o['kind']).toSet(), {
      'STOCK',
      'PREORDER',
    });
    final emptied = object(await api.request('GET', 'cart'));
    expect(objects(emptied['items']).isEmpty, true);
    expect(objects(emptied['preorders']).isEmpty, true);
    await api.refresh();
    // APP_TEST_USERNAME 是登入識別（Email）
    expect(object(await api.request('GET', 'me'))['email'], username);
    await api.logout();
    expect(api.signedIn, false);
  }, skip: base.isEmpty ? 'Requires private disposable live fixture' : false);

  test('real phone+email registration, login by email or phone, refresh, logout', () async {
    final store = MemoryStore();
    final api = ShopApi(store: store, baseUrl: base, development: true);
    final tag = const Uuid().v4().replaceAll('-', '').substring(0, 16);
    final email = 'app_$tag@example.test';
    final phone =
        '09${(DateTime.now().microsecondsSinceEpoch % 100000000).toString().padLeft(8, '0')}';
    final password = 'App-${const Uuid().v4()}';
    await api.register(email: email, phone: phone, password: password);
    // 同一 Email 再註冊：伺服器說明重複，不是「結果未知」
    await expectLater(
      api.register(email: email, phone: phone, password: password),
      throwsA(isA<ShopError>().having((e) => e.status, 'status', 409)),
    );
    await api.login(email.toUpperCase(), password);
    final me = object(await api.request('GET', 'me'));
    expect(me['email'], email);
    expect(me['phone'], phone);
    expect(me['emailVerified'], false);
    final firstRefresh = await store.read('refresh_token');
    await api.refresh();
    expect(await store.read('refresh_token'), isNot(firstRefresh));
    expect(object(await api.request('GET', 'me'))['email'], email);
    // 暱稱修改已停用
    await expectLater(
      api.request('PATCH', 'me', body: {'displayName': 'x'}),
      throwsA(isA<ShopError>().having((e) => e.status, 'status', 403)),
    );
    await api.logout();
    expect(api.signedIn, false);
    expect(await store.read('refresh_token'), null);
    // 重新登入（用手機）
    await api.login(phone, password);
    expect(object(await api.request('GET', 'me'))['phone'], phone);
    // 會員資料只回傳 ID／Email／手機／驗證狀態，不再有內部 username 或暱稱
    expect(me.containsKey('username') || me.containsKey('displayName'), false);
    await api.logout();
  }, skip: base.isEmpty ? 'Requires private disposable live fixture' : false);
}
