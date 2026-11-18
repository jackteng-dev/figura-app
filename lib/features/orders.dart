import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../core/models.dart';
import '../core/providers.dart';
import 'common.dart';

/// 統一訂單中心（後端 /order-center）：現貨與預購同一個列表，伺服器端篩選、排序與全域分頁。
/// 詳情、付款、取消等操作沿用原本的現貨／預購詳情畫面。
const orderStages = {
  'ALL': '全部狀態',
  'PENDING_PAYMENT': '待付款',
  'WAITING_ARRIVAL': '等待到貨',
  'TO_SHIP': '待出貨',
  'SHIPPED': '已出貨',
  'COMPLETED': '已完成',
  'RETURNING': '退貨處理中',
  'CANCELLED': '已取消',
  'REFUNDED': '已退款',
  'REVIEW': '付款待核對',
};
const orderSorts = {
  'NEWEST': '最新優先',
  'OLDEST': '最舊優先',
  'AMOUNT_DESC': '金額高到低',
  'AMOUNT_ASC': '金額低到高',
};

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});
  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  String kind = 'ALL', stage = 'ALL', sort = 'NEWEST';
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'ALL', label: Text('全部')),
            ButtonSegment(value: 'STOCK', label: Text('現貨')),
            ButtonSegment(value: 'PREORDER', label: Text('預購')),
          ],
          selected: {kind},
          onSelectionChanged: (v) => setState(() => kind = v.first),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                value: stage,
                items: [
                  for (final e in orderStages.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => stage = v ?? 'ALL'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                value: sort,
                items: [
                  for (final e in orderSorts.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => sort = v ?? 'NEWEST'),
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: PagedView(
          key: ValueKey('$kind/$stage/$sort'),
          load: (page) async => object(
            await ref
                .read(apiProvider)
                .request(
                  'GET',
                  'order-center?kind=$kind&stage=$stage&sort=$sort&page=$page&pageSize=10',
                ),
          ),
          empty: '這個篩選條件沒有訂單',
          item: (j) {
            final preorder = j['kind'] == 'PREORDER';
            final lines = (j['lineCount'] as num?)?.toInt() ?? 1;
            final pending = j['stage'] == 'PENDING_PAYMENT';
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                title: Text(
                  '${preorder ? '預購訂單' : '現貨訂單'} · ${orderStages[j['stage']] ?? j['stage']}',
                ),
                subtitle: Text(
                  [
                    '${j['title'] ?? '訂單'}${lines > 1 ? ' 等 $lines 款' : ''} · 共 ${j['quantity']} 件',
                    '${twd(j['totalTwd'])} · ${dateLabel(j['createdAt'])}',
                    if (j['balanceStatus'] == 'DUE' && j['status'] == 'PAID')
                      '訂金已付，待付尾款${j['balanceDueAt'] != null ? '（${dateLabel(j['balanceDueAt'])} 前）' : ''}'
                    else if (pending && j['expiresAt'] != null)
                      '請在 ${dateLabel(j['expiresAt'])} 前完成付款',
                    if (preorder && j['arrivalFrom'] != null)
                      '預計到貨 ${dateLabel(j['arrivalFrom'])} ～ ${dateLabel(j['arrivalTo'])}',
                    if (j['paymentReviewRequired'] == true) '付款通知待人工核對',
                  ].join('\n'),
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(
                  '/orders/${preorder ? 'preorder' : 'stock'}/${j['id']}',
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
              if (j['paidAt'] != null)
                Text(
                  '${j['paymentMode'] == 'DEPOSIT' ? '訂金付款' : '付款'} ${dateLabel(j['paidAt'])}',
                ),
            ]),
            // Phase 4：訂金制預購（訂金確保名額，到貨通知後付尾款）
            if (preorder && j['paymentMode'] == 'DEPOSIT')
              infoCard('訂金與尾款', [
                moneyRow('訂金', j['depositTwd']),
                moneyRow('尾款', j['balanceTwd']),
                Text(
                  j['status'] == 'REFUNDED'
                      ? '已退款'
                      : j['status'] == 'CANCELLED' || j['status'] == 'EXPIRED'
                      ? '未付款，訂單已結束'
                      : const {
                              'NOT_DUE': '訂金付款後，到貨時通知支付尾款',
                              'DUE': '待付尾款',
                              'PAID': '尾款已付清',
                            }[j['balanceStatus']] ??
                            '',
                ),
                if (j['balanceStatus'] == 'DUE' &&
                    j['status'] == 'PAID' &&
                    j['balanceDueAt'] != null)
                  Text('尾款期限 ${dateLabel(j['balanceDueAt'])}'),
                if (j['balancePaidAt'] != null)
                  Text('尾款付款 ${dateLabel(j['balancePaidAt'])}'),
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
                      // 到貨時程異動（只有對外說明與前後日期）
                      for (final s in objects(j['schedule']))
                        Text(
                          '${s['action'] == 'DELAY' ? '延期' : '調整'}：${dateLabel(s['arrivalFromBefore'])} ～ ${dateLabel(s['arrivalToBefore'])} → ${dateLabel(s['arrivalFromAfter'])} ～ ${dateLabel(s['arrivalToAfter'])}。${s['publicReason']}',
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
                  label: preorder && j['payNowTwd'] != null
                      ? '建立${j['balanceStatus'] == 'DUE' && j['status'] == 'PAID'
                            ? '尾款'
                            : j['paymentMode'] == 'DEPOSIT'
                            ? '訂金'
                            : ''}模擬付款（${twd(j['payNowTwd'])}）'
                      : '建立模擬付款',
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
                        '${p['provider'] == 'ECPAY' ? '綠界測試信用卡 · ' : ''}${const {'DEPOSIT': '訂金 · ', 'BALANCE': '尾款 · '}[p['stage']] ?? ''}${statusLabel(p['status'])} · ${twd(p['amountTwd'])}',
                      ),
                      // 綠界（網站建立）的付款不能在 App 模擬，結果以伺服器收到的綠界通知為準
                      if (p['provider'] == 'ECPAY' &&
                          p['status'] == 'INITIATED')
                        const Text('此筆為網站發起的綠界測試付款，請在網站完成或等待結果。'),
                      // 舊版或預購付款沒有 provider 欄位，一律視為模擬付款
                      if ((p['provider'] ?? 'MOCK') == 'MOCK' &&
                          p['status'] == 'INITIATED' &&
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
