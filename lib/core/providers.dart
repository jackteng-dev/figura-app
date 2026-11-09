import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'api.dart';

final apiProvider = ChangeNotifierProvider<ShopApi>(
  (ref) => throw UnimplementedError('Inject ShopApi at startup'),
);
final writesProvider = ChangeNotifierProvider<Writes>(
  (ref) => Writes(ref.read(apiProvider)),
);
final startupProvider = FutureProvider<void>((ref) async {
  await ref.read(apiProvider).restore();
  await ref.read(writesProvider).restore();
});
