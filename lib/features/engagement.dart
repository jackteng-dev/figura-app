import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/providers.dart';
import 'catalog_specs.dart';
import 'common.dart';

const alertLabels = {
  'RESTOCK': '補貨',
  'PREORDER_OPEN': '開放預購',
  'PREORDER_CLOSING': '預購即將截止',
  'RELEASE': '發售',
};

Future<void> _loginPrompt(BuildContext context, String text) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.push('/login');
            },
            child: const Text('前往登入'),
          ),
        ],
      ),
    );

class ProductEngagement extends ConsumerWidget {
  final String id;
  const ProductEngagement({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiProvider);
    if (!api.signedIn) {
      return Wrap(
        spacing: 8,
        children: [
          IconButton(
            tooltip: '加入收藏',
            onPressed: () => _loginPrompt(context, '登入後才能收藏'),
            icon: const Icon(Icons.favorite_border),
          ),
          TextButton.icon(
            onPressed: () => _loginPrompt(context, '登入後才能設定商品提醒'),
            icon: const Icon(Icons.notifications_none),
            label: const Text('到貨／開賣提醒'),
          ),
        ],
      );
    }
    return RequestView(
      key: ValueKey('engagement-$id-${api.customer!['id']}'),
      load: () async => Future.wait([
        api.request('GET', 'favorites/ids'),
        api.request('GET', 'product-alerts'),
      ]),
      render: (data, reload) {
        final favorite = (data[0]['productIds'] as List).contains(id);
        final alerts = objects(data[1]).where((p) => p['productId'] == id);
        final kinds = alerts.isEmpty
            ? <String>[]
            : List<String>.from(alerts.first['kinds']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _ActionIcon(
                  label: favorite ? '移除收藏' : '加入收藏',
                  icon: favorite ? Icons.favorite : Icons.favorite_border,
                  action: () async {
                    await ref
                        .read(writesProvider)
                        .run(favorite ? 'DELETE' : 'PUT', 'favorites/$id', {});
                    reload();
                  },
                ),
                TextButton.icon(
                  onPressed: () async {
                    final saved = await showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => _AlertSheet(id: id, kinds: kinds),
                    );
                    if (saved == true) reload();
                  },
                  icon: Icon(
                    kinds.isEmpty
                        ? Icons.notifications_none
                        : Icons.notifications_active,
                  ),
                  label: const Text('到貨／開賣提醒'),
                ),
              ],
            ),
            Text(
              kinds.isEmpty
                  ? '尚未訂閱商品提醒'
                  : '已訂閱：${kinds.map((k) => alertLabels[k] ?? k).join('、')}',
            ),
          ],
        );
      },
    );
  }
}

class _ActionIcon extends ConsumerStatefulWidget {
  final String label;
  final IconData icon;
  final Future<void> Function() action;
  const _ActionIcon({
    required this.label,
    required this.icon,
    required this.action,
  });
  @override
  ConsumerState<_ActionIcon> createState() => _ActionIconState();
}

class _ActionIconState extends ConsumerState<_ActionIcon> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final writes = ref.watch(writesProvider);
    return IconButton(
      tooltip: widget.label,
      icon: Icon(widget.icon),
      onPressed: busy || writes.busy || writes.pending != null
          ? null
          : () async {
              setState(() => busy = true);
              try {
                await widget.action();
              } catch (e) {
                if (context.mounted) message(context, e);
              } finally {
                if (mounted) setState(() => busy = false);
              }
            },
    );
  }
}

class _AlertSheet extends ConsumerStatefulWidget {
  final String id;
  final List<String> kinds;
  const _AlertSheet({required this.id, required this.kinds});
  @override
  ConsumerState<_AlertSheet> createState() => _AlertSheetState();
}

class _AlertSheetState extends ConsumerState<_AlertSheet> {
  late final selected = widget.kinds.toSet();
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('到貨／開賣提醒', style: TextStyle(fontSize: 20)),
          for (final entry in alertLabels.entries)
            CheckboxListTile(
              title: Text(entry.value),
              value: selected.contains(entry.key),
              onChanged: (value) => setState(() {
                if (value == true) {
                  selected.add(entry.key);
                } else {
                  selected.remove(entry.key);
                }
              }),
            ),
          WriteButton(
            label: '儲存提醒',
            action: () async {
              await ref.read(writesProvider).run(
                'PUT',
                'product-alerts/${widget.id}',
                {'kinds': selected.toList()..sort()},
              );
              if (context.mounted) Navigator.pop(context, true);
            },
          ),
        ],
      ),
    ),
  );
}

/// Append pages on demand; a failed page is retried only by explicit user action.
class EngagementList extends StatefulWidget {
  final Future<Json> Function(int) load;
  final Widget Function(Json, VoidCallback) item;
  final String title, empty;
  final List<Widget> actions;
  const EngagementList({
    super.key,
    required this.load,
    required this.item,
    required this.title,
    required this.empty,
    this.actions = const [],
  });
  @override
  State<EngagementList> createState() => _EngagementListState();
}

class _EngagementListState extends State<EngagementList> {
  final scroll = ScrollController();
  final items = <Json>[];
  int nextPage = 1, total = 0, generation = 0;
  bool loading = false;
  Object? error;
  @override
  void initState() {
    super.initState();
    scroll.addListener(() {
      if (scroll.position.extentAfter < 240 &&
          error == null &&
          items.length < total) {
        load();
      }
    });
    load();
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (loading) return;
    final current = generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final page = await widget.load(nextPage);
      if (!mounted || current != generation) return;
      setState(() {
        items.addAll(objects(page['items']));
        total = page['total'] as int;
        nextPage++;
      });
    } catch (e) {
      if (mounted && current == generation) setState(() => error = e);
    } finally {
      if (mounted && current == generation) setState(() => loading = false);
    }
  }

  Future<void> reload() async {
    if (!mounted) return;
    generation++;
    setState(() {
      items.clear();
      nextPage = 1;
      total = 0;
      loading = false;
      error = null;
    });
    await load();
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: reload,
    child: ListView(
      controller: scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          widget.title,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        ...widget.actions,
        for (final item in items) widget.item(item, reload),
        if (loading) const Center(child: CircularProgressIndicator()),
        if (error != null) ...[
          Text(error is ShopError ? (error as ShopError).message : '無法讀取資料'),
          TextButton(onPressed: load, child: const Text('重新讀取')),
        ],
        if (!loading && error == null && items.isEmpty) Text(widget.empty),
        if (!loading && error == null && items.length < total)
          TextButton(onPressed: load, child: const Text('載入更多')),
      ],
    ),
  );
}

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => EngagementList(
    title: '我的收藏',
    empty: '目前沒有收藏商品',
    load: (page) async => object(
      await ref
          .read(apiProvider)
          .request('GET', 'favorites?page=$page&pageSize=20'),
    ),
    item: (favorite, reload) {
      final product = object(favorite['product']);
      return Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: Text(product['title']),
              subtitle: Text(
                product['minPriceTwd'] == null
                    ? '價格待確認'
                    : twd(product['minPriceTwd']),
              ),
              trailing: _ActionIcon(
                label: '移除收藏',
                icon: Icons.favorite,
                action: () async {
                  await ref
                      .read(writesProvider)
                      .run('DELETE', 'favorites/${product['id']}', {});
                  reload();
                },
              ),
              onTap: () async {
                await context.push('/products/${product['id']}');
                reload();
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ProductAvailability(product: product),
            ),
          ],
        ),
      );
    },
  );
}

class NotificationPreferencesScreen extends ConsumerWidget {
  const NotificationPreferencesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => RequestView(
    load: () =>
        ref.read(apiProvider).request('GET', 'notification-preferences'),
    render: (data, reload) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        infoCard('通知設定', [
          const Text('以下偏好只控制 Email，站內通知一律保留。'),
          if (data['emailVerified'] != true)
            const Text('需先驗證 Email 才能收到 Email 通知'),
          if (data['emailDeliveryActive'] != true)
            const Text('目前為測試環境，Email 不會實際寄出'),
          for (final entry in const {
            'emailEnabled': 'Email 通知',
            'orderUpdates': '訂單通知',
            'productAlerts': '商品提醒',
          }.entries)
            SwitchListTile(
              title: Text(entry.value),
              value: data[entry.key] == true,
              onChanged:
                  ref.watch(writesProvider).busy ||
                      ref.watch(writesProvider).pending != null
                  ? null
                  : (value) async {
                      try {
                        await ref.read(writesProvider).run(
                          'PUT',
                          'notification-preferences',
                          {
                            'emailEnabled': data['emailEnabled'],
                            'orderUpdates': data['orderUpdates'],
                            'productAlerts': data['productAlerts'],
                            entry.key: value,
                            'expectedVersion': data['version'],
                          },
                        );
                        reload();
                      } on ShopError catch (e) {
                        if (!context.mounted) return;
                        message(context, e.status == 409 ? '設定已在其他裝置變更' : e);
                        // Never resend a versioned write after conflict or an unknown result.
                        reload();
                      } catch (e) {
                        if (context.mounted) message(context, e);
                      }
                    },
            ),
        ]),
      ],
    ),
  );
}

class NotificationsEntry extends ConsumerWidget {
  const NotificationsEntry({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => RequestView(
    load: () => ref
        .read(apiProvider)
        .request('GET', 'notifications?page=1&pageSize=1&unread=false'),
    render: (data, reload) => OutlinedButton.icon(
      onPressed: () async {
        await context.push('/account/notifications');
        reload();
      },
      icon: const Icon(Icons.notifications_outlined),
      label: Text('通知（${data['unread']} 則未讀）'),
    ),
  );
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  int revision = 0;
  @override
  Widget build(BuildContext context) => EngagementList(
    key: ValueKey(revision),
    title: '通知',
    empty: '目前沒有通知',
    load: (page) async => object(
      await ref
          .read(apiProvider)
          .request('GET', 'notifications?page=$page&pageSize=20&unread=false'),
    ),
    actions: [
      WriteButton(
        label: '全部標為已讀',
        action: () async {
          await ref.read(writesProvider).run('POST', 'notifications/read', {
            'all': true,
          });
          if (mounted) setState(() => revision++);
        },
      ),
    ],
    item: (notice, reload) => Card(
      child: ListTile(
        title: Text(
          notice['title'],
          style: TextStyle(
            fontWeight: notice['readAt'] == null
                ? FontWeight.bold
                : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          '${notice['message']}\n${dateLabel(notice['createdAt'])}',
        ),
        isThreeLine: true,
        onTap:
            ref.watch(writesProvider).busy ||
                ref.watch(writesProvider).pending != null
            ? null
            : () async {
                try {
                  if (notice['readAt'] == null) {
                    await ref.read(writesProvider).run(
                      'POST',
                      'notifications/read',
                      {
                        'ids': [notice['id']],
                      },
                    );
                  }
                  if (!context.mounted) return;
                  reload();
                  final product = notice['productId'],
                      order = notice['orderId'],
                      preorder = notice['preorderOrderId'];
                  if (product != null) {
                    await context.push(
                      '/products/${Uri.encodeComponent(product as String)}',
                    );
                  } else if (order != null) {
                    await context.push(
                      '/orders/stock/${Uri.encodeComponent(order as String)}',
                    );
                  } else if (preorder != null) {
                    await context.push(
                      '/orders/preorder/${Uri.encodeComponent(preorder as String)}',
                    );
                  }
                } catch (e) {
                  if (context.mounted) message(context, e);
                }
              },
      ),
    ),
  );
}
