import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models.dart';
import '../core/providers.dart';
import 'common.dart';

class CatalogScreen extends ConsumerWidget {
  final bool preorder;
  const CatalogScreen({super.key, this.preorder = false});
  @override
  Widget build(BuildContext context, WidgetRef ref) => PagedView(
    load: (page) async => object(
      await ref
          .read(apiProvider)
          .publicGet(
            '${preorder ? 'preorders' : 'products'}?page=$page&pageSize=12',
          ),
    ),
    empty: preorder ? '目前沒有開放的預購批次' : '目前沒有上架商品',
    item: (j) => Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            context.push('/${preorder ? 'batches' : 'products'}/${j['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              if (!preorder) ProductImage(product: j, size: 96),
              if (!preorder) const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${preorder ? j['productTitle'] : j['title']}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('${preorder ? j['name'] : j['brand']}'),
                    const SizedBox(height: 8),
                    Text(preorder ? twd(j['priceTwd']) : '查看款式與價格'),
                    if (preorder) Text('截單 ${dateLabel(j['deadlineAt'])}'),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    ),
  );
}

class ProductImage extends ConsumerWidget {
  final Json product;
  final double size;
  const ProductImage({super.key, required this.product, this.size = 220});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.read(apiProvider).imageUrl(product);
    final placeholder = Container(
      width: size,
      height: size,
      color: const Color(0xffe5e7e3),
      child: const Icon(Icons.toys_outlined, size: 42),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: url.isEmpty
          ? placeholder
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.contain,
              semanticLabel: '${product['title']}',
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}

class ProductScreen extends ConsumerWidget {
  final String id;
  const ProductScreen({super.key, required this.id});
  @override
  Widget build(BuildContext context, WidgetRef ref) => RequestView(
    load: () => ref.read(apiProvider).publicGet('products/$id'),
    render: (data, reload) {
      final j = object(data);
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(child: ProductImage(product: j)),
          const SizedBox(height: 24),
          Text(
            j['title'],
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('${j['brand']} · ${j['category']}'),
          if (j['work'] != null) Text('${j['work']}'),
          const SizedBox(height: 16),
          Text(j['description'] ?? ''),
          const SizedBox(height: 24),
          ...objects(j['skus']).map(
            (sku) => infoCard(sku['label'], [
              moneyRow('價格', sku['priceTwd']),
              Text(sku['available'] == true ? '可購買' : '暫時售完'),
              const SizedBox(height: 12),
              ref.watch(apiProvider).signedIn
                  ? WriteButton(
                      label: '加入購物車',
                      enabled: sku['available'] == true,
                      action: () async {
                        final api = ref.read(apiProvider),
                            writes = ref.read(writesProvider);
                        final cart = object(await api.request('GET', 'cart'));
                        final existing = objects(cart['items'])
                            .where((v) => v['skuId'] == sku['id']);
                        final qty = existing.isEmpty
                            ? 1
                            : (existing.first['quantity'] as int) + 1;
                        if (qty > 99) {
                          if (context.mounted) message(context, '最多 99 件');
                          return;
                        }
                        await writes.run('PUT', 'cart/items/${sku['id']}', {
                          'quantity': qty,
                          'expectedVersion': cart['version'],
                        });
                        if (context.mounted) message(context, '已加入購物車');
                      },
                    )
                  : FilledButton(
                      onPressed: () => context.go('/login'),
                      child: const Text('登入後購買'),
                    ),
            ]),
          ),
        ],
      );
    },
  );
}

class BatchScreen extends ConsumerWidget {
  final String id;
  const BatchScreen({super.key, required this.id});
  @override
  Widget build(BuildContext context, WidgetRef ref) => RequestView(
    load: () => ref.read(apiProvider).publicGet('preorders/$id'),
    render: (data, reload) {
      final j = object(data);
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          infoCard(j['name'], [
            Text(j['productTitle'], style: const TextStyle(fontSize: 24)),
            Text(j['skuLabel']),
            const SizedBox(height: 16),
            Text(j['description'] ?? ''),
            moneyRow('單價', j['priceTwd'], emphasis: true),
            Text('剩餘預購名額 ${j['availableQuota']}'),
            Text('截單 ${dateLabel(j['deadlineAt'])}'),
            Text(
              '預估到貨 ${dateLabel(j['arrivalFrom'])} ～ ${dateLabel(j['arrivalTo'])}',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: j['orderingEnabled'] == true
                  ? () => context.push(
                      ref.read(apiProvider).signedIn
                          ? '/checkout/preorder/$id'
                          : '/login',
                    )
                  : null,
              child: const Text('預購結帳'),
            ),
          ]),
          const Text('預購名額獨立於現貨庫存。到貨日期為預估時間。'),
        ],
      );
    },
  );
}
