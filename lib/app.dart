import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/api.dart';
import 'core/models.dart';
import 'core/providers.dart';
import 'features/auth.dart';
import 'features/catalog.dart';
import 'features/common.dart';
import 'features/orders.dart';
import 'features/shopping.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final api = ref.read(apiProvider);
  final router = GoRouter(
    initialLocation: '/products',
    refreshListenable: api,
    redirect: (context, state) {
      final path = state.uri.path;
      final public =
          path == '/login' ||
          path.startsWith('/products') ||
          path.startsWith('/batches');
      if (!public && !api.signedIn) return '/login';
      return null;
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            ShopShell(path: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/products',
            builder: (_, _) => const CatalogScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => ProductScreen(id: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/batches',
            builder: (_, _) => const CatalogScreen(preorder: true),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => BatchScreen(id: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
          GoRoute(path: '/cart', builder: (_, _) => const CartScreen()),
          GoRoute(
            path: '/addresses',
            builder: (_, _) => const AddressesScreen(),
          ),
          GoRoute(path: '/account', builder: (_, _) => const AccountScreen()),
          GoRoute(
            path: '/checkout/stock',
            builder: (_, _) => const CheckoutScreen(),
          ),
          GoRoute(
            path: '/checkout/preorder/:id',
            builder: (_, s) => CheckoutScreen(batchId: s.pathParameters['id']!),
          ),
          GoRoute(path: '/orders', builder: (_, _) => const OrdersScreen()),
          GoRoute(
            path: '/orders/:kind/:id',
            redirect: (_, s) =>
                {'stock', 'preorder'}.contains(s.pathParameters['kind'])
                ? null
                : '/orders',
            builder: (_, s) => OrderScreen(
              id: s.pathParameters['id']!,
              preorder: s.pathParameters['kind'] == 'preorder',
            ),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class ShopApp extends ConsumerWidget {
  const ShopApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(startupProvider);
    final theme = ThemeData(
      useMaterial3: true,
      fontFamily: "NotoSansTC",
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff284c42)),
      scaffoldBackgroundColor: const Color(0xfff5f4ef),
      cardTheme: const CardThemeData(color: Colors.white, elevation: 0),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xfff5f4ef),
        surfaceTintColor: Colors.transparent,
      ),
    );
    if (startup.isLoading || startup.hasError) {
      return MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: startup.isLoading
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('無法確認登入狀態'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => ref.invalidate(startupProvider),
                        child: const Text('重新連線'),
                      ),
                      TextButton(
                        onPressed: () async {
                          try {
                            await ref.read(apiProvider).logout();
                          } catch (_) {
                            /* Local sign-out still completes. */
                          }
                          ref.invalidate(startupProvider);
                        },
                        child: const Text('清除本機登入並繼續'),
                      ),
                    ],
                  ),
          ),
        ),
      );
    }
    return MaterialApp.router(
      title: 'ELPSY Shop',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'TW'),
      supportedLocales: const [Locale('zh', 'TW'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: theme,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

class ShopShell extends ConsumerWidget {
  final String path;
  final Widget child;
  const ShopShell({super.key, required this.path, required this.child});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final writes = ref.watch(writesProvider), api = ref.watch(apiProvider);
    final index = path.startsWith('/batches')
        ? 1
        : path.startsWith('/cart') || path.startsWith('/checkout')
        ? 2
        : path.startsWith('/orders')
        ? 3
        : path.startsWith('/account') ||
              path.startsWith('/addresses') ||
              path.startsWith('/login')
        ? 4
        : 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ELPSY Shop',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1),
        ),
        leading: context.canPop()
            ? BackButton(onPressed: () => context.pop())
            : null,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                api.signedIn ? '${api.customer!['displayName']}' : '收藏品商店',
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                if (writes.pending != null) const PendingBanner(),
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey(writes.revision),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(
          ['/products', '/batches', '/cart', '/orders', '/account'][i],
        ),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.toys_outlined), label: '現貨'),
          NavigationDestination(icon: Icon(Icons.schedule), label: '預購'),
          NavigationDestination(
            icon: Icon(Icons.shopping_bag_outlined),
            label: '購物車',
          ),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: '訂單'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: '會員'),
        ],
      ),
    );
  }
}

class PendingBanner extends ConsumerWidget {
  const PendingBanner({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final writes = ref.watch(writesProvider), p = writes.pending!;
    return Material(
      color: const Color(0xffffedd1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(writes.busy ? '正在確認操作…' : '上一筆操作尚未確認。新寫入已暫停，請先核對。'),
            if (!writes.busy)
              Wrap(
                spacing: 12,
                children: [
                  if (p.replayable)
                    TextButton(
                      onPressed: () async {
                        try {
                          final result = await writes.retry();
                          if (context.mounted) {
                            message(context, '已確認原操作');
                            if (result is Map && result['order'] != null) {
                              final preorder =
                                  p.path.startsWith('preorders') ||
                                  p.path.startsWith('preorder-payments');
                              context.go(
                                '/orders/${preorder ? 'preorder' : 'stock'}/${result['order']['id']}',
                              );
                            }
                          }
                        } catch (e) {
                          if (context.mounted) message(context, e);
                        }
                      },
                      child: const Text('以原編號核對／重試'),
                    ),
                  if (!p.replayable)
                    TextButton(
                      onPressed: () async {
                        try {
                          final resource = p.path.startsWith('cart')
                              ? 'cart'
                              : p.path.startsWith('addresses')
                              ? 'addresses'
                              : p.path.startsWith('orders/')
                              ? p.path.split('/').take(2).join('/')
                              : 'me';
                          final data = await ref
                              .read(apiProvider)
                              .request('GET', resource);
                          if (!context.mounted) return;
                          final summary = resource == 'cart'
                              ? objects(data['items'])
                                    .map(
                                      (i) => '${i['title']} × ${i['quantity']}',
                                    )
                                    .join('\n')
                              : resource == 'addresses'
                              ? objects(data)
                                    .map((a) => Address(a).label)
                                    .join('\n')
                              : resource == 'me'
                              ? '${data['displayName']}'
                              : statusLabel(data['status']);
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('目前伺服器資料'),
                              content: SingleChildScrollView(
                                child: Text(
                                  summary.isEmpty ? '目前沒有資料' : summary,
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('保留待核對'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('已核對，解除鎖定'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await writes.confirmAfterRead();
                          }
                        } catch (e) {
                          if (context.mounted) message(context, e);
                        }
                      },
                      child: const Text('重讀目前資料並核對'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

void runShopApp(ShopApi api) => runApp(
  ProviderScope(
    overrides: [apiProvider.overrideWith((ref) => api)],
    child: const ShopApp(),
  ),
);
