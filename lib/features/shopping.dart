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
      final cart = object(data), items = objects(cart['items']);
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '我的購物車',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (items.isEmpty) const Text('購物車還沒有商品'),
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
          moneyRow('商品合計', cart['subtotalTwd'], emphasis: true),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: cart['ready'] == true && items.isNotEmpty
                ? () => context.push('/checkout/stock')
                : null,
            child: const Text('確認結帳'),
          ),
          const SizedBox(height: 16),
          const Text('購物車不保留庫存。建立訂單時會再次確認價格與可售數量。'),
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
  @override
  Widget build(BuildContext context) => RequestView(
    load: () async {
      final api = ref.read(apiProvider);
      final values = await Future.wait([
        api.request('GET', 'addresses'),
        widget.batchId == null
            ? api.request('GET', 'cart')
            : api.publicGet('preorders/${widget.batchId}'),
      ]);
      return {'addresses': values[0], 'purchase': values[1]};
    },
    render: (data, reload) {
      final addresses = objects(data['addresses']).map(Address.new).toList(),
          purchase = object(data['purchase']);
      final preorder = widget.batchId != null;
      final selectedAddress =
          addresses.where((a) => a.id == selected).firstOrNull ??
          addresses.firstOrNull;
      final subtotal = preorder
          ? (purchase['priceTwd'] as num) * quantity
          : purchase['subtotalTwd'] as num;
      final valid = preorder
          ? purchase['orderingEnabled'] == true &&
                quantity <= (purchase['availableQuota'] as int)
          : purchase['ready'] == true && objects(purchase['items']).isNotEmpty;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            preorder ? '預購結帳' : '現貨結帳',
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
            ] else
              ...objects(purchase['items']).map(
                (j) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${j['title']} · ${j['label']} × ${j['quantity']} — ${twd(j['lineTotalTwd'])}',
                  ),
                ),
              ),
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
          infoCard('金額確認', [
            moneyRow('商品小計', subtotal),
            moneyRow('展示運費', 0),
            moneyRow('合計', subtotal, emphasis: true),
          ]),
          const Text('目前採整筆付款的模擬流程。訂單建立後保留 30 分鐘，预購不晚於截單時間。'),
          const SizedBox(height: 16),
          WriteButton(
            label: '建立訂單',
            enabled: valid && selectedAddress != null,
            action: () async {
              final body = <String, dynamic>{
                'requestId': const Uuid().v4(),
                'addressId': selectedAddress!.id,
                'addressVersion': selectedAddress.version,
                'expectedSubtotalTwd': subtotal,
                if (preorder) 'batchId': widget.batchId,
                if (preorder) 'quantity': quantity,
                if (!preorder) 'cartVersion': purchase['version'],
              };
              final result = object(
                await ref
                    .read(writesProvider)
                    .run(
                      'POST',
                      preorder ? 'preorders' : 'orders',
                      body,
                      replayable: true,
                    ),
              );
              if (context.mounted) {
                context.go(
                  '/orders/${preorder ? 'preorder' : 'stock'}/${object(result['order'])['id']}',
                );
              }
            },
          ),
        ],
      );
    },
  );
}
