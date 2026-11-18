import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../core/models.dart';
import '../core/providers.dart';
import 'common.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => RequestView(
    load: () => ref.read(apiProvider).request('GET', 'cart'),
    render: (data, reload) {
      final cart = object(data),
          items = objects(cart['items']),
          preorders = objects(cart['preorders']);
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '我的購物車',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (items.isEmpty && preorders.isEmpty) const Text('購物車還沒有商品'),
          if (items.isNotEmpty && preorders.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('現貨', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ...items.map(
            (line) => infoCard(line['title'], [
              Text(line['label']),
              moneyRow('單價', line['unitPriceTwd']),
              Text('數量 ${line['quantity']}'),
              if (line['issue'] != null)
                Text(
                  const {
                        'UNAVAILABLE': '商品已下架',
                        'SOLD_OUT': '暫時售完',
                        'INSUFFICIENT_STOCK': '可售數量不足',
                      }[line['issue']] ??
                      '請重新核對商品',
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final delta in [-1, 1])
                    WriteButton(
                      label: delta == -1 ? '減少一件' : '增加一件',
                      enabled:
                          (line['quantity'] as int) + delta >= 1 &&
                          (line['quantity'] as int) + delta <= 99,
                      action: () async {
                        await ref.read(writesProvider).run(
                          'PUT',
                          'cart/items/${line['skuId']}',
                          {
                            'quantity': (line['quantity'] as int) + delta,
                            'expectedVersion': cart['version'],
                          },
                        );
                        reload();
                      },
                    ),
                  WriteButton(
                    label: '移除',
                    action: () async {
                      await ref
                          .read(writesProvider)
                          .run(
                            'DELETE',
                            'cart/items/${line['skuId']}?expectedVersion=${cart['version']}',
                            {},
                          );
                      reload();
                    },
                  ),
                ],
              ),
              moneyRow('小計', line['lineTotalTwd']),
            ]),
          ),
          if (preorders.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '預購（結帳時每個批次各成一張訂單）',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ...preorders.map(
            (line) => infoCard('預購 · ${line['title']}', [
              Text('批次：${line['batchName']} · ${line['label']}'),
              Text(
                '預估到貨 ${dateLabel(line['arrivalFrom'])} ～ ${dateLabel(line['arrivalTo'])}',
              ),
              moneyRow('單價', line['unitPriceTwd']),
              Text('數量 ${line['quantity']} · 剩餘名額 ${line['availableQuota']}'),
              if (line['issue'] != null)
                Text(
                  const {
                        'UNAVAILABLE': '預購商品已下架',
                        'CLOSED': '批次已截單或尚未開放',
                        'EXPIRED': '已過預購截止時間',
                        'INSUFFICIENT_QUOTA': '剩餘名額不足，請減少數量',
                      }[line['issue']] ??
                      '請重新核對商品',
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final delta in [-1, 1])
                    WriteButton(
                      label: delta == -1 ? '減少一件' : '增加一件',
                      enabled:
                          (line['quantity'] as int) + delta >= 1 &&
                          (line['quantity'] as int) + delta <= 100,
                      action: () async {
                        await ref.read(writesProvider).run(
                          'PUT',
                          'cart/preorders/${line['batchId']}',
                          {
                            'quantity': (line['quantity'] as int) + delta,
                            'expectedVersion': cart['version'],
                          },
                        );
                        reload();
                      },
                    ),
                  WriteButton(
                    label: '移除',
                    action: () async {
                      await ref
                          .read(writesProvider)
                          .run(
                            'DELETE',
                            'cart/preorders/${line['batchId']}?expectedVersion=${cart['version']}',
                            {},
                          );
                      reload();
                    },
                  ),
                ],
              ),
              moneyRow('小計', line['lineTotalTwd']),
            ]),
          ),
          if (preorders.isNotEmpty) ...[
            moneyRow('現貨小計', cart['subtotalTwd']),
            moneyRow('預購小計', cart['preorderSubtotalTwd']),
          ],
          moneyRow(
            '商品合計',
            cart['totalTwd'] ?? cart['subtotalTwd'],
            emphasis: true,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed:
                cart['checkoutReady'] == true &&
                    (items.isNotEmpty || preorders.isNotEmpty)
                ? () => context.push('/checkout/stock')
                : null,
            child: const Text('確認結帳'),
          ),
          const SizedBox(height: 16),
          const Text('購物車不保留庫存或預購名額。結帳時系統會自動拆成現貨訂單與各預購批次的訂單，並再次確認價格與數量。'),
        ],
      );
    },
  );
}

class AddressesScreen extends ConsumerWidget {
  const AddressesScreen({super.key});
  Future<bool?> edit(BuildContext context, WidgetRef ref, Json? initial) =>
      showDialog<bool>(
        context: context,
        builder: (_) => AddressEditor(initial: initial),
      );
  @override
  Widget build(BuildContext context, WidgetRef ref) => RequestView(
    load: () => ref.read(apiProvider).request('GET', 'addresses'),
    render: (data, reload) {
      final addresses = objects(data);
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '收件地址',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: ref.watch(writesProvider).pending != null
                ? null
                : () async {
                    if (await edit(context, ref, null) == true) reload();
                  },
            child: const Text('新增地址'),
          ),
          if (addresses.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('請新增一筆收件地址'),
            ),
          ...addresses.map(
            (j) => infoCard(j['recipientName'], [
              Text('${j['phone']}'),
              Text(
                '${j['postalCode']} ${j['city']}${j['district']}${j['street']}',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: ref.watch(writesProvider).pending != null
                        ? null
                        : () async {
                            if (await edit(context, ref, j) == true) reload();
                          },
                    child: const Text('編輯'),
                  ),
                  WriteButton(
                    label: '刪除',
                    action: () async {
                      await ref
                          .read(writesProvider)
                          .run(
                            'DELETE',
                            'addresses/${j['id']}?expectedVersion=${j['version']}',
                            {},
                          );
                      reload();
                    },
                  ),
                ],
              ),
            ]),
          ),
        ],
      );
    },
  );
}

class AddressEditor extends ConsumerStatefulWidget {
  final Json? initial;
  const AddressEditor({super.key, this.initial});
  @override
  ConsumerState<AddressEditor> createState() => _AddressEditorState();
}

class _AddressEditorState extends ConsumerState<AddressEditor> {
  final form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> fields;
  static const labels = {
    'recipientName': '收件人',
    'phone': '電話',
    'postalCode': '郵遞區號',
    'city': '縣市',
    'district': '行政區',
    'street': '詳細地址',
  };
  @override
  void initState() {
    super.initState();
    fields = {
      for (final k in labels.keys)
        k: TextEditingController(text: widget.initial?[k] ?? ''),
    };
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? '新增收件地址' : '編輯收件地址'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: labels.entries
                .map(
                  (e) => field(
                    fields[e.key]!,
                    e.value,
                    keyboard: e.key == 'phone' || e.key == 'postalCode'
                        ? TextInputType.phone
                        : null,
                    validator: (v) {
                      final s = v?.trim() ?? '';
                      if (s.isEmpty) return '請填寫${e.value}';
                      if (e.key == 'phone' &&
                          !RegExp(r'^\+?[0-9]{8,15}$').hasMatch(s)) {
                        return '電話需為 8–15 位數字';
                      }
                      if (e.key == 'postalCode' &&
                          !RegExp(r'^[0-9]{3}([0-9]{2}|[0-9]{3})?$')
                              .hasMatch(s)) {
                        return '郵遞區號需為 3、5 或 6 位數';
                      }
                      final max = e.key == 'street'
                          ? 200
                          : e.key == 'recipientName'
                          ? 80
                          : 40;
                      return s.length > max ? '內容過長' : null;
                    },
                  ),
                )
                .toList(),
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: ref.watch(writesProvider).busy
            ? null
            : () => Navigator.pop(context),
        child: const Text('返回'),
      ),
      WriteButton(
        label: '儲存地址',
        action: () async {
          if (!form.currentState!.validate()) return;
          final id = widget.initial?['id'] ?? const Uuid().v4();
          await ref.read(writesProvider).run('PUT', 'addresses/$id', {
            'expectedVersion': widget.initial?['version'] ?? 0,
            for (final e in fields.entries) e.key: e.value.text.trim(),
          });
          if (context.mounted) Navigator.pop(context, true);
        },
      ),
    ],
  );
}

class CheckoutScreen extends ConsumerStatefulWidget {
  final String? batchId;
  const CheckoutScreen({super.key, this.batchId});
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String? selected;
  int quantity = 1;
  // 配送（Phase 5，只用於購物車結帳）：方式、合併／分開寄、超商測試門市
  String method = 'HOME', strategy = 'SPLIT';
  String? store;
  @override
  Widget build(BuildContext context) => RequestView(
    // 換配送方式或寄送方式就重新向伺服器報價
    key: ValueKey('$method|$strategy'),
    load: () async {
      final api = ref.read(apiProvider);
      final values = await Future.wait([
        api.request('GET', 'addresses'),
        widget.batchId == null
            ? api.request(
                'GET',
                'checkout/quote?shippingMethod=$method&deliveryStrategy=$strategy',
              )
            : api.publicGet('preorders/${widget.batchId}'),
        if (widget.batchId == null)
          api.request('GET', 'checkout/pickup-stores'),
      ]);
      return {
        'addresses': values[0],
        'purchase': values[1],
        'stores': values.length > 2 ? values[2] : [],
      };
    },
    render: (data, reload) {
      final addresses = objects(data['addresses']).map(Address.new).toList(),
          purchase = object(data['purchase']);
      final preorder = widget.batchId != null;
      final selectedAddress =
          addresses.where((a) => a.id == selected).firstOrNull ??
          addresses.firstOrNull;
      final groups = preorder ? <Json>[] : objects(purchase['groups']);
      final subtotal = preorder
          ? (purchase['priceTwd'] as num) * quantity
          : purchase['totalTwd'] as num;
      final valid = preorder
          ? purchase['orderingEnabled'] == true &&
                quantity <= (purchase['availableQuota'] as int)
          : purchase['ready'] == true &&
                groups.isNotEmpty &&
                (method != 'CVS' || store != null);
      final stores = objects(data['stores']);
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            preorder ? '預購結帳' : '結帳',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          infoCard('確認商品', [
            if (preorder) ...[
              Text('${purchase['productTitle']} · ${purchase['skuLabel']}'),
              Text('${purchase['name']}'),
              DropdownButtonFormField<int>(
                initialValue: quantity,
                decoration: const InputDecoration(labelText: '數量'),
                items: List.generate(
                  100,
                  (i) =>
                      DropdownMenuItem(value: i + 1, child: Text('${i + 1} 件')),
                ),
                onChanged: ref.watch(writesProvider).pending != null
                    ? null
                    : (v) => setState(() => quantity = v!),
              ),
              Text(
                '預估到貨 ${dateLabel(purchase['arrivalFrom'])} ～ ${dateLabel(purchase['arrivalTo'])}',
              ),
              if (purchase['paymentMode'] == 'DEPOSIT')
                Text(
                  '訂金制：現在付訂金 ${twd((purchase['depositTwd'] as num) * quantity)}，尾款到貨通知後 ${purchase['balanceDays']} 天內支付',
                ),
            ] else ...[
              if (groups.length > 1)
                Text('這次結帳會拆成 ${groups.length} 張訂單：現貨一張、每個預購批次各一張，各自付款與出貨。'),
              for (final g in groups) ...[
                const SizedBox(height: 8),
                Text(
                  g['kind'] == 'PREORDER' ? '預購 · ${g['title']}' : '現貨訂單',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  g['arrivalFrom'] != null
                      ? '預估到貨 ${dateLabel(g['arrivalFrom'])} ～ ${dateLabel(g['arrivalTo'])}'
                      : '付款後出貨',
                ),
                ...objects(g['lines']).map(
                  (j) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '${j['title']} · ${j['label']} × ${j['quantity']} — ${twd(j['lineTotalTwd'])}${j['issue'] != null ? '（無法下單）' : ''}',
                    ),
                  ),
                ),
                moneyRow('這張訂單', g['totalTwd']),
                if ((g['payLaterTwd'] as num? ?? 0) > 0)
                  Text(
                    '訂金制：現在付 ${twd(g['payNowTwd'])}，尾款 ${twd(g['payLaterTwd'])} 到貨通知後支付',
                  ),
              ],
            ],
          ]),
          infoCard('收件地址', [
            if (selectedAddress != null)
              DropdownButtonFormField<String>(
                initialValue: selectedAddress.id,
                isExpanded: true,
                items: addresses
                    .map(
                      (a) => DropdownMenuItem(
                        value: a.id,
                        child: Text(a.label, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: ref.watch(writesProvider).pending != null
                    ? null
                    : (v) => setState(() => selected = v),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () async {
                await context.push('/addresses');
                reload();
              },
              child: const Text('管理收件地址'),
            ),
          ]),
          if (!preorder)
            infoCard('配送方式', [
              for (final m in objects(purchase['methods']))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    method == m['code']
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text('${m['name']}'),
                  subtitle: Text(
                    m['enabled'] == true
                        ? '運費 ${twd(m['feeTwd'])}${m['freeThresholdTwd'] != null ? '，滿 ${twd(m['freeThresholdTwd'])} 免運' : ''}'
                        : '暫停使用',
                  ),
                  enabled: m['enabled'] == true,
                  onTap: () => setState(() {
                    method = m['code'];
                    if (method != 'CVS') store = null;
                  }),
                ),
              if (method == 'CVS')
                DropdownButtonFormField<String>(
                  initialValue: store,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '取貨門市（測試門市）'),
                  items: stores
                      .map(
                        (s) => DropdownMenuItem(
                          value: s['storeId'] as String,
                          child: Text(
                            '${s['brandName']} ${s['storeName']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => store = v),
                ),
              if (groups.length > 1) ...[
                const SizedBox(height: 8),
                const Text(
                  '寄送方式',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final s in const [
                  ['SPLIT', '分開寄', '現貨先寄，預購到貨再各自寄出（各自計運費）'],
                  ['COMBINED', '一起寄', '全部到齊後一次寄出（只算一次運費）'],
                ])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      strategy == s[0]
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(s[1]),
                    subtitle: Text(s[2]),
                    onTap: () => setState(() => strategy = s[0]),
                  ),
              ],
              Text(
                '共 ${objects(purchase['shipments']).length} 個包裹。出貨與配送為測試物流，不會實際寄送。',
              ),
            ]),
          infoCard('金額確認', [
            if (groups.length > 1) Text('訂單數 ${groups.length} 張'),
            moneyRow('商品小計', preorder ? subtotal : purchase['subtotalTwd']),
            moneyRow('運費', preorder ? 0 : purchase['shippingTwd']),
            moneyRow('合計', subtotal, emphasis: true),
          ]),
          const Text(
            '目前採整筆付款的模擬流程。訂單建立後保留 30 分鐘，預購不晚於截單時間；多張訂單會一起建立，任一張無法建立就全部不建立。',
          ),
          const SizedBox(height: 16),
          WriteButton(
            label: '建立訂單',
            enabled: valid && selectedAddress != null,
            action: () async {
              final body = <String, dynamic>{
                'requestId': const Uuid().v4(),
                'addressId': selectedAddress!.id,
                'addressVersion': selectedAddress.version,
                if (preorder) ...{
                  'expectedSubtotalTwd': subtotal,
                  'batchId': widget.batchId,
                  'quantity': quantity,
                } else ...{
                  'cartVersion': purchase['cartVersion'],
                  'expectedTotalTwd': subtotal,
                  'shippingMethod': method,
                  'deliveryStrategy': purchase['deliveryStrategy'] ?? strategy,
                  if (method == 'CVS') 'pickupStoreId': store,
                },
              };
              final result = object(
                await ref
                    .read(writesProvider)
                    .run(
                      'POST',
                      preorder ? 'preorders' : 'checkout',
                      body,
                      replayable: true,
                    ),
              );
              if (!context.mounted) return;
              if (preorder) {
                context.go('/orders/preorder/${object(result['order'])['id']}');
                return;
              }
              final placed = objects(result['orders']);
              // 一張訂單直接到詳情付款；拆成多張時到統一訂單中心的待付款
              if (placed.length == 1) {
                context.go(
                  '/orders/${placed.first['kind'] == 'PREORDER' ? 'preorder' : 'stock'}/${placed.first['id']}',
                );
              } else {
                message(context, '已建立 ${placed.length} 張訂單，請逐一付款');
                context.go('/orders');
              }
            },
          ),
        ],
      );
    },
  );
}
