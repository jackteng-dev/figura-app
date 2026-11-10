import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'storage.dart';

class ShopError implements Exception {
  final String message;
  final int? status;
  final bool uncertain;
  ShopError(this.message, {this.status, this.uncertain = false});
  @override
  String toString() => message;
}

Uri validateBase(String value, {required bool development}) {
  final uri = Uri.parse(value);
  final devHost = {
    'localhost',
    '127.0.0.1',
    '10.0.2.2',
    '::1',
  }.contains(uri.host);
  if (uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.scheme != 'https' &&
          !(development && devHost && uri.scheme == 'http')) ||
      !uri.path.endsWith('/figura/api/')) {
    throw ShopError('API 位址需為 HTTPS，並以 /figura/api/ 結尾');
  }
  return uri;
}

class ShopApi extends ChangeNotifier {
  final Dio dio;
  final PrivateStore store;
  String? accessToken;
  Json? customer;
  Future<void>? _refreshing;
  int _generation = 0;
  Future<void> _credentialQueue = Future.value();
  Future<void> _credentials(Future<void> Function() action) {
    final next = _credentialQueue.then((_) => action());
    _credentialQueue = next.catchError((Object _) {});
    return next;
  }

  ShopApi({
    required this.store,
    required String baseUrl,
    Dio? client,
    bool development = false,
  }) : dio = client ?? Dio() {
    dio.options.baseUrl = validateBase(
      baseUrl,
      development: development,
    ).toString();
    dio.options.connectTimeout = const Duration(seconds: 10);
    dio.options.receiveTimeout = const Duration(seconds: 20);
    dio.options.sendTimeout = const Duration(seconds: 20);
    // No logging/cookie/retry interceptors. Only a server-rejected 401 may refresh once.
  }
  bool get signedIn => customer != null && accessToken != null;
  Future<dynamic> _raw(
    String method,
    String path, {
    Json? body,
    String? token,
  }) async {
    try {
      final response = await dio.request<dynamic>(
        path,
        data: body,
        options: Options(
          method: method,
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        ),
      );
      final envelope = object(response.data);
      if (envelope['code'] != 0) throw ShopError('伺服器未接受操作');
      return envelope['data'];
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // A lost response or 5xx may follow a committed transaction.
      throw ShopError(
        status == 401
            ? '請重新登入'
            : status == 409
            ? '資料已更新，請重新核對'
            : status == 404
            ? '找不到資料'
            : status == 400
            ? '請檢查輸入內容'
            : status == 403
            ? '此操作目前無法使用'
            : '連線失敗，請稍後重試',
        status: status,
        uncertain: status == null || status >= 500,
      );
    }
  }

  Future<dynamic> publicGet(String path) => _raw('GET', 'catalog/$path');
  Future<dynamic> request(String method, String path, {Json? body}) async {
    if (!signedIn) throw ShopError('請先登入', status: 401);
    final token = accessToken;
    final generation = _generation;
    try {
      return await _raw(
        method,
        'mobile/customer/$path',
        body: body,
        token: token,
      );
    } on ShopError catch (e) {
      if (e.status != 401) rethrow;
      if (_generation != generation || !signedIn) rethrow;
      if (token == accessToken) await refresh();
      if (_generation != generation || !signedIn) {
        throw ShopError('請重新登入', status: 401);
      }
      return _raw(
        method,
        'mobile/customer/$path',
        body: body,
        token: accessToken,
      );
    }
  }

  Future<void> register(
    String username,
    String password,
    String displayName,
  ) async {
    await _raw(
      'POST',
      'mobile/customer/auth/register',
      body: {
        'username': username,
        'password': password,
        'displayName': displayName,
      },
    );
  }

  Future<void> login(String username, String password) async {
    final generation = ++_generation;
    var device = await store.read('device_id');
    device ??= const Uuid().v4();
    await store.write('device_id', device);
    final data = object(
      await _raw(
        'POST',
        'mobile/customer/auth/login',
        body: {
          'username': username,
          'password': password,
          'deviceId': device,
          'rememberMe': false,
        },
      ),
    );
    if (generation != _generation) return;
    await _accept(data, generation);
  }

  Future<void> _accept(Json data, int generation) => _credentials(() async {
    if (generation != _generation) return;
    // Refresh is one secure value. No password or access token is persisted.
    await store.write('refresh_token', data['refreshToken'] as String);
    if (generation != _generation) return;
    accessToken = data['accessToken'] as String;
    customer = object(data['customer']);
    notifyListeners();
  });

  Future<void> restore() async {
    if (await store.read('refresh_token') == null) return;
    try {
      await refresh();
    } on ShopError catch (e) {
      if (e.status != 401) rethrow;
    }
  }

  Future<void> refresh() {
    if (_refreshing != null) return _refreshing!;
    final generation = _generation;
    final future = _refresh(generation);
    _refreshing = future;
    return future.whenComplete(() {
      if (identical(_refreshing, future)) _refreshing = null;
    });
  }

  Future<void> _refresh(int generation) async {
    final refresh = await store.read('refresh_token');
    if (refresh == null) throw ShopError('請重新登入', status: 401);
    try {
      final data = object(
        await _raw(
          'POST',
          'mobile/customer/auth/refresh',
          body: {'refreshToken': refresh},
        ),
      );
      if (generation != _generation) {
        // A response may arrive after logout. Revoke the rotated pair before logout completes.
        await _raw(
          'POST',
          'mobile/customer/auth/logout',
          body: {'refreshToken': data['refreshToken']},
        );
        return;
      }
      await _accept(data, generation);
    } on ShopError catch (e) {
      if (generation == _generation && e.status == 401) {
        await _credentials(() async {
          if (generation != _generation) return;
          await store.delete('refresh_token');
          accessToken = null;
          customer = null;
          notifyListeners();
        });
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    final refreshing = _refreshing;
    ++_generation;
    accessToken = null;
    customer = null;
    notifyListeners();
    bool unconfirmed = false;
    if (refreshing != null) {
      try {
        await refreshing;
      } on ShopError catch (e) {
        unconfirmed = e.status != 401;
      }
    }
    String? refresh;
    await _credentials(() async {
      refresh = await store.read('refresh_token');
      await store.delete('refresh_token');
    });
    if (refresh != null) {
      try {
        await _raw(
          'POST',
          'mobile/customer/auth/logout',
          body: {'refreshToken': refresh},
        );
      } on ShopError catch (e) {
        if (e.status != 401) unconfirmed = true;
      }
    }
    if (unconfirmed) throw ShopError('本機已登出，伺服器撤銷尚未確認');
  }

  String imageUrl(Json product) {
    final image = product['image'];
    if (image == null) return '';
    // Rebuild a known public route, never attach bearer tokens or trust arbitrary image URLs.
    return '${dio.options.baseUrl}catalog/products/${Uri.encodeComponent(product['id'] as String)}/image/${Uri.encodeComponent(object(image)['id'] as String)}';
  }
}

class PendingWrite {
  final String owner, method, path;
  final Json body;
  final bool replayable;
  PendingWrite({
    required this.owner,
    required this.method,
    required this.path,
    required this.body,
    required this.replayable,
  });
  Json toJson() => {
    'owner': owner,
    'method': method,
    'path': path,
    'body': body,
    'replayable': replayable,
  };
  factory PendingWrite.fromJson(Json j) => PendingWrite(
    owner: j['owner'],
    method: j['method'],
    path: j['path'],
    body: object(j['body']),
    replayable: j['replayable'],
  );
}

class Writes extends ChangeNotifier {
  final ShopApi api;
  PendingWrite? pending;
  bool busy = false;
  int revision = 0;
  Writes(this.api);
  String get _key => 'pending_${api.customer!['id']}';
  Future<void> restore() async {
    pending = null;
    if (api.signedIn) {
      final value = await api.store.read(_key);
      if (value != null) {
        final p = PendingWrite.fromJson(object(jsonDecode(value)));
        if (p.owner == api.customer!['id']) pending = p;
      }
    }
    notifyListeners();
  }

  Future<dynamic> run(
    String method,
    String path,
    Json body, {
    bool replayable = false,
  }) async {
    if (busy || pending != null) throw ShopError('請先核對上一筆操作');
    if (!api.signedIn) throw ShopError('請先登入');
    pending = PendingWrite(
      owner: api.customer!['id'],
      method: method,
      path: path,
      body: Map.of(body),
      replayable: replayable,
    );
    return _send();
  }

  Future<dynamic> retry() async {
    if (busy || pending == null || !pending!.replayable) {
      throw ShopError('此操作請先重讀核對');
    }
    final result = await _send();
    revision++;
    notifyListeners();
    return result;
  }

  Future<dynamic> _send() async {
    final p = pending!;
    if (p.owner != api.customer?['id']) throw ShopError('請使用原帳號核對');
    busy = true;
    notifyListeners();
    final key = _key;
    try {
      await api.store.write(key, jsonEncode(p.toJson()));
      final result = await api.request(p.method, p.path, body: p.body);
      // Acknowledged writes never remain retryable because a later GET fails.
      await api.store.delete(key);
      pending = null;
      return result;
    } on ShopError catch (e) {
      if (!e.uncertain) {
        await api.store.delete(key);
        pending = null;
      }
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> confirmAfterRead() async {
    if (busy) return;
    await api.store.delete(_key);
    pending = null;
    revision++;
    notifyListeners();
  }
}
