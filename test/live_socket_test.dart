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
    await api.refresh();
    expect(object(await api.request('GET', 'me'))['username'], username);
    await api.logout();
    expect(api.signedIn, false);
  }, skip: base.isEmpty ? 'Requires private disposable live fixture' : false);
}
