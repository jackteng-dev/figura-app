import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../core/models.dart';
import '../core/providers.dart';
import 'common.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});
  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  bool preorder = false;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('現貨訂單')),
            ButtonSegment(value: true, label: Text('預購訂單')),
          ],
          selected: {preorder},
          onSelectionChanged: (v) => setState(() => preorder = v.first),
        ),
      ),
      Expanded(
        child: PagedView(
          key: ValueKey(preorder),
          load: (page) async => object(
            await ref
                .read(apiProvider)
                .request(
                  'GET',
                  '${preorder ? 'preorders' : 'orders'}?page=$page&pageSize=10',
                ),
          ),
          empty: '目前沒有${preorder ? '預購' : '現貨'}訂單',
          item: (j) {
            final order = ShopOrder(j, preorder: preorder);
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                title: Text(order.title),
                subtitle: Text(
                  '${statusLabel(order.status)} · ${twd(order.total)}\n${dateLabel(j['createdAt'])}\n${order.id}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(
                  '/orders/${preorder ? 'preorder' : 'stock'}/${order.id}',
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}

class OrderScreen extends ConsumerWidget {
  final String id;
  final bool preorder;
  const OrderScreen({super.key, required this.id, required this.preorder});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resource = preorder ? 'preorders' : 'orders';
    return RequestView(
      load: () async {
        final api = ref.read(apiProvider);
        final values = await Future.wait([
          api.request('GET', '$resource/$id'),
          api.request('GET', '$resource/$id/mock-payments'),
        ]);
        return {'order': values[0], 'payments': values[1]};
      },
      render: (data, reload) {
        final order = ShopOrder(object(data['order']), preorder: preorder),
            j = order.json;
        final options = object(data['payments']),
            shipping = object(j['shipping']);
        final fulfillment = object(j['fulfillment']),
            paymentItems = objects(options['items']);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            infoCard(order.title, [
              SelectableText(order.id),
              const SizedBox(height: 12),
              Text(
                statusLabel(order.status),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              moneyRow('商品小計', j['subtotalTwd']),
              moneyRow('運費', j['shippingTwd']),
              moneyRow('訂單合計', order.total, emphasis: true),
              Text('建立 ${dateLabel(j['createdAt'])}'),
              if (order.pending) Text('付款期限 ${dateLabel(j['expiresAt'])}'),
              if (j['paidAt'] != null) Text('付款 ${dateLabel(j['paidAt'])}'),
            ]),
            infoCard(
              '商品快照',
              preorder
                  ? [
                      Text(
                        '${j['productTitle']} · ${j['skuLabel']} × ${j['quantity']}',
                      ),
                      Text(
                        '預估到貨 ${dateLabel(j['arrivalFrom'])} ～ ${dateLabel(j['arrivalTo'])}',
                      ),
                    ]
                  : objects(j['items'])
                        .map<Widget>(
                          (item) => Text(
                            '${item['title']} · ${item['label']} × ${item['quantity']}',
                          ),
                        )
                        .toList(),
            ),
            infoCard('收件資訊', [
              Text('${shipping['recipientName']} · ${shipping['phone']}'),
              Text(
                '${shipping['postalCode']} ${shipping['city']}${shipping['district']}${shipping['street']}',
              ),
            ]),
            infoCard('履約進度', [
              if (preorder) Text(statusLabel(j['arrivalStatus'])),
              Text(
                statusLabel(
                  preorder ? j['fulfillmentStatus'] : fulfillment['status'],
                ),
              ),
              if (preorder) Text('已分配 ${fulfillment['allocatedQuantity']} 件'),
              if ((fulfillment['trackingId'] ??
                      fulfillment['trackingNumber']) !=
                  null)
                Text(
                  '模擬貨件 ${fulfillment['trackingId'] ?? fulfillment['trackingNumber']}',
                ),
              if (fulfillment['shippedAt'] != null)
                Text('出貨 ${dateLabel(fulfillment['shippedAt'])}'),
              if (fulfillment['deliveredAt'] != null)
                Text('送達 ${dateLabel(fulfillment['deliveredAt'])}'),
              if (j['paymentReviewRequired'] == true) const Text('付款通知待人工核對'),
            ]),
            if (j['refund'] != null)
              infoCard('退款進度', [
                Text('模擬全額退款 ${twd(j['refund']['amountTwd'])}'),
                Text(dateLabel(j['refund']['refundedAt'])),
              ]),
            if (j['returnProgress'] != null)
              infoCard('退貨進度', [
                Text(statusLabel(j['returnProgress']['status'])),
              ]),
            if (order.pending)
              WriteButton(
                label: '取消訂單',
                action: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('取消這筆訂單？'),
                      content: const Text('取消後會釋放保留的庫存或預購名額。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('返回'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('確認取消'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  await ref.read(writesProvider).run(
                    'POST',
                    '$resource/$id/cancel',
                    {
                      'expectedVersion': order.version,
                      if (preorder) 'requestId': const Uuid().v4(),
                    },
                    replayable: preorder,
                  );
                  reload();
                },
              ),
            const SizedBox(height: 16),
            infoCard('模擬付款', [
              const Text('僅測試交易流程，不會收取款項。'),
              if (options['enabled'] != true) const Text('目前未開啟模擬付款'),
              if (options['canStart'] == true)
                WriteButton(
                  label: '建立模擬付款',
                  action: () async {
                    await ref.read(writesProvider).run(
                      'POST',
                      '$resource/$id/mock-payments',
                      {
                        'requestId': const Uuid().v4(),
                        'expectedOrderVersion': order.version,
                      },
                      replayable: true,
                    );
                    reload();
                  },
                ),
              ...paymentItems.map(
                (p) => Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${statusLabel(p['status'])} · ${twd(p['amountTwd'])}',
                      ),
                      if (p['status'] == 'INITIATED' &&
                          options['enabled'] == true)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final outcome in ['SUCCESS', 'FAILURE'])
                              WriteButton(
                                label: outcome == 'SUCCESS' ? '模擬成功' : '模擬失敗',
                                action: () async {
                                  await ref.read(writesProvider).run(
                                    'POST',
                                    '${preorder ? 'preorder-payments' : 'mock-payments'}/${p['id']}/simulate',
                                    {
                                      'eventId': const Uuid().v4(),
                                      'outcome': outcome,
                                    },
                                    replayable: true,
                                  );
                                  reload();
                                },
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ]),
          ],
        );
      },
    );
  }
}
