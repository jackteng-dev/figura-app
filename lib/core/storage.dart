import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class PrivateStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class NativeStore implements PrivateStore {
  final FlutterSecureStorage _store = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  @override
  Future<String?> read(String key) => _store.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _store.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _store.delete(key: key);
}

// Tests and browser harness only. Production main never selects this store.
class MemoryStore implements PrivateStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
