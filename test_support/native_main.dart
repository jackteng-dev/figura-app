// Debug-only native acceptance probe. Never use this entrypoint for distribution.
// Credentials come from an owned loopback controller, never from build defines.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:figura/core/api.dart';
import 'package:figura/core/models.dart';
import 'package:figura/core/storage.dart';

const base = String.fromEnvironment('API_BASE_URL');
final checks = <String>[];
void check(String name, bool passed) {
  if (!passed) throw StateError(name);
  checks.add(name);
}

Future<Json> control(String path, [Json? body]) async {
  final uri = validateBase(base, development: true).replace(path: path);
  final client = HttpClient();
  try {
    final request = await client.openUrl(body == null ? 'GET' : 'POST', uri);
    if (body != null) {
      final raw = utf8.encode(jsonEncode(body));
      request.headers.contentType = ContentType.json;
      request.contentLength = raw.length;
      request.add(raw);
    }
    final response = await request.close();
    if (response.statusCode != 200) throw StateError('controller unavailable');
    return object(jsonDecode(await response.transform(utf8.decoder).join()));
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode || kIsWeb) throw StateError('Native debug probe only');
  final uri = validateBase(base, development: true);
  if (!{'127.0.0.1', 'localhost', '10.0.2.2'}.contains(uri.host)) {
    throw StateError('Owned loopback controller required');
  }
  runApp(const MaterialApp(home: Scaffold(body: Text('原生裝置驗收中'))));
  String phase = 'startup';
  try {
    final fixture = await control('/__fixture');
    phase = fixture['phase'];
    await verify(fixture);
    await control('/__result', {
      'phase': phase,
      'passed': true,
      'checks': checks,
    });
    runApp(const MaterialApp(home: Scaffold(body: Text('原生裝置驗收通過'))));
  } catch (_) {
    // No exception/credential dumps: the last completed check identifies progress.
    await control('/__result', {
      'phase': phase,
      'passed': false,
      'checks': checks,
    });
    runApp(const MaterialApp(home: Scaffold(body: Text('原生裝置驗收失敗'))));
  }
}

Future<void> verify(Json f) async {
  final store = NativeStore();
  final api = ShopApi(store: store, baseUrl: base, development: true);
  final writes = Writes(api);
  final phase = f['phase'];
  if (phase == 'seed') {
    await api.login(f['APP_TEST_USERNAME'], f['APP_TEST_PASSWORD']);
    check(
      'native login stores refresh without persisting access',
      await store.read('refresh_token') != null &&
          await store.read('access_token') == null,
    );
    await store.write('probe_device', (await store.read('device_id'))!);
    await store.write('probe_refresh', (await store.read('refresh_token'))!);
    await store.write('probe_owner', api.customer!['id']);
    final aid = const Uuid().v4();
    final address = object(
      await writes.run('PUT', 'addresses/$aid', {
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
    await writes.run('PUT', 'cart/items/${f['APP_TEST_SKU']}', {
      'expectedVersion': cart['version'],
      'quantity': 1,
    });
    final ready = object(await api.request('GET', 'cart'));
    try {
      await writes.run('POST', 'orders', {
        'requestId': const Uuid().v4(),
        'cartVersion': ready['version'],
        'addressId': aid,
        'addressVersion': address['version'],
        'expectedSubtotalTwd': ready['subtotalTwd'],
      }, replayable: true);
      throw StateError('expected a lost response');
    } on ShopError catch (e) {
      check('lost committed response remains uncertain', e.uncertain);
    }
    check(
      'unknown order saved by native secure storage',
      writes.pending != null,
    );
    await store.write('probe_pending', jsonEncode(writes.pending!.toJson()));
    return;
  }
  await api.restore();
  if (phase == 'loggedout') {
    check('cold start after logout stays signed out', !api.signedIn);
    check(
      'logout removed secure refresh',
      await store.read('refresh_token') == null,
    );
    check(
      'device identity survives logout',
      await store.read('device_id') == await store.read('probe_device'),
    );
    for (final key in [
      'probe_device',
      'probe_refresh',
      'probe_owner',
      'probe_pending',
    ]) {
      await store.delete(key);
    }
    return;
  }
  check(
    'cold start restores the original customer',
    api.signedIn && api.customer!['id'] == await store.read('probe_owner'),
  );
  check(
    'cold start preserves Keystore device identity',
    await store.read('device_id') == await store.read('probe_device'),
  );
  check(
    'cold start rotates secure refresh',
    await store.read('refresh_token') != await store.read('probe_refresh'),
  );
  await writes.restore();
  if (phase == 'resume') {
    check(
      'pending UUID and payload survive process death',
      jsonEncode(writes.pending?.toJson()) == await store.read('probe_pending'),
    );
    try {
      await writes.run('PATCH', 'me', {'displayName': 'blocked'});
      throw StateError('new write should be frozen');
    } on ShopError {
      check('unconfirmed order freezes new writes', writes.pending != null);
    }
    final order = object(object(await writes.retry())['order']);
    await store.write('probe_order', order['id']);
    check(
      'confirmed replay clears native pending record',
      writes.pending == null &&
          await store.read('pending_${api.customer!['id']}') == null,
    );
    try {
      await api.request('GET', 'orders/${order['id']}');
      throw StateError('expected post-ack read failure');
    } on ShopError catch (e) {
      check(
        'read failure after ACK does not recreate pending write',
        e.status == 503 && writes.pending == null,
      );
    }
    check(
      'read recovery returns original order',
      object(await api.request('GET', 'orders/${order['id']}'))['id'] ==
          order['id'],
    );
  } else if (phase == 'version') {
    final cart = object(await api.request('GET', 'cart'));
    try {
      await writes.run('PUT', 'cart/items/${f['APP_TEST_SKU']}', {
        'expectedVersion': cart['version'],
        'quantity': 2,
      });
      throw StateError('expected lost versioned response');
    } on ShopError catch (e) {
      check(
        'lost versioned write is retained without automatic retry',
        e.uncertain && writes.pending != null && !writes.pending!.replayable,
      );
    }
    await store.write('probe_pending', jsonEncode(writes.pending!.toJson()));
  } else if (phase == 'resolve') {
    check(
      'versioned pending survives process death unchanged',
      jsonEncode(writes.pending?.toJson()) == await store.read('probe_pending'),
    );
    await api.register(f['OTHER_USERNAME'], f['OTHER_PASSWORD'], '合成第二會員');
    await api.logout();
    await api.login(f['OTHER_USERNAME'], f['OTHER_PASSWORD']);
    await writes.restore();
    check(
      'another customer cannot restore original pending operation',
      writes.pending == null,
    );
    await api.logout();
    await api.login(f['APP_TEST_USERNAME'], f['APP_TEST_PASSWORD']);
    await writes.restore();
    check(
      'original owner restores isolated pending operation',
      jsonEncode(writes.pending?.toJson()) == await store.read('probe_pending'),
    );
    try {
      await writes.retry();
      throw StateError('versioned retry must be refused');
    } on ShopError {
      check(
        'versioned write requires explicit read reconciliation',
        writes.pending != null,
      );
    }
    final cart = object(await api.request('GET', 'cart'));
    check(
      'read confirms server accepted versioned write once',
      objects(cart['items']).any(
        (item) => item['skuId'] == f['APP_TEST_SKU'] && item['quantity'] == 2,
      ),
    );
    await writes.confirmAfterRead();
    check(
      'explicit reconciliation clears secure pending',
      writes.pending == null &&
          await store.read('pending_${api.customer!['id']}') == null,
    );
  } else if (phase == 'logout') {
    await api.logout();
    check(
      'native logout clears in-memory session and secure refresh',
      !api.signedIn && await store.read('refresh_token') == null,
    );
    await store.delete('probe_order');
  } else {
    throw StateError('unknown phase');
  }
}
