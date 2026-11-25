import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/providers.dart';
import 'common.dart';
import 'engagement.dart';

const supportCategories = {
  'ORDER': '訂單',
  'PREORDER': '預購',
  'SHIPPING': '配送',
  'RETURN_DEFECT': '退換貨／瑕疵',
  'PAYMENT': '付款',
  'ACCOUNT': '帳號',
  'PRODUCT': '商品',
  'OTHER': '其他',
};
const supportStatuses = {
  'WAITING_STAFF': '等待客服回覆',
  'WAITING_CUSTOMER': '客服已回覆',
  'RESOLVED': '已解決',
  'CLOSED': '已結案',
};

class SupportTicketsScreen extends ConsumerStatefulWidget {
  const SupportTicketsScreen({super.key});
  @override
  ConsumerState<SupportTicketsScreen> createState() => _SupportTicketsState();
}

class _SupportTicketsState extends ConsumerState<SupportTicketsScreen> {
  int revision = 0;
  @override
  Widget build(BuildContext context) => EngagementList(
    key: ValueKey('$revision-${ref.watch(writesProvider).revision}'),
    title: '客服中心',
    empty: '目前沒有客服單',
    load: (page) async => object(
      await ref
          .read(apiProvider)
          .request('GET', 'support-tickets?page=$page&pageSize=20'),
    ),
    actions: [
      OutlinedButton(
        onPressed: () async {
          await context.push('/account/support-tickets/new');
          if (mounted) setState(() => revision++);
        },
        child: const Text('建立客服單'),
      ),
    ],
    item: (ticket, reload) => Card(
      child: ListTile(
        title: Text(ticket['subject']),
        subtitle: Text(
          '${supportStatuses[ticket['status']] ?? ticket['status']} · ${supportCategories[ticket['category']] ?? ticket['category']}\n${dateLabel(ticket['updatedAt'])}',
        ),
        onTap: () async {
          await context.push(
            '/account/support-tickets/${Uri.encodeComponent(ticket['id'] as String)}',
          );
          reload();
        },
      ),
    ),
  );
}

class NewSupportTicketScreen extends ConsumerStatefulWidget {
  const NewSupportTicketScreen({super.key});
  @override
  ConsumerState<NewSupportTicketScreen> createState() =>
      _NewSupportTicketState();
}

class _NewSupportTicketState extends ConsumerState<NewSupportTicketScreen> {
  final form = GlobalKey<FormState>();
  final subject = TextEditingController(), body = TextEditingController();
  String category = 'ORDER';
  Json? order;
  @override
  void dispose() {
    subject.dispose();
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('建立客服單', style: TextStyle(fontSize: 24)),
        DropdownButtonFormField<String>(
          initialValue: category,
          decoration: const InputDecoration(labelText: '類別'),
          items: [
            for (final e in supportCategories.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (value) => setState(() => category = value ?? 'ORDER'),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: subject,
          decoration: const InputDecoration(labelText: '主旨'),
          maxLength: 120,
          validator: (v) => v == null || v.trim().isEmpty ? '請填寫主旨' : null,
        ),
        supportBodyField(body, '內容'),
        Text(
          order == null
              ? '未關聯訂單（選填）'
              : '關聯${order!['kind'] == 'PREORDER' ? '預購' : '現貨'}訂單：${order!['id']}',
        ),
        OutlinedButton(
          onPressed: () async {
            final selected = await showModalBottomSheet<Json>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const FractionallySizedBox(
                heightFactor: .8,
                child: _OrderPicker(),
              ),
            );
            if (selected != null && mounted) setState(() => order = selected);
          },
          child: const Text('選擇關聯訂單'),
        ),
        if (order != null)
          TextButton(
            onPressed: () => setState(() => order = null),
            child: const Text('移除關聯'),
          ),
        WriteButton(
          label: '送出客服單',
          action: () async {
            if (!form.currentState!.validate()) return;
            final result = object(
              await ref.read(writesProvider).run('POST', 'support-tickets', {
                'requestId': const Uuid().v4(),
                'category': category,
                'subject': subject.text.trim(),
                'body': body.text.trim(),
                if (order != null)
                  (order!['kind'] == 'PREORDER'
                          ? 'preorderOrderId'
                          : 'orderId'):
                      order!['id'],
              }, replayable: true),
            );
            if (context.mounted) {
              final ticket = object(object(result['current'])['ticket']);
              context.replace(
                '/account/support-tickets/${Uri.encodeComponent(ticket['id'] as String)}',
              );
            }
          },
        ),
      ],
    ),
  );
}

class _OrderPicker extends ConsumerWidget {
  const _OrderPicker();
  @override
  Widget build(BuildContext context, WidgetRef ref) => SafeArea(
    child: Column(
      children: [
        const Text('選擇本人訂單', style: TextStyle(fontSize: 20)),
        const Text('找不到訂單時可返回，不關聯訂單也能送出。'),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('返回'),
        ),
        Expanded(
          child: PagedView(
            load: (page) async => object(
              await ref
                  .read(apiProvider)
                  .request(
                    'GET',
                    'order-center?kind=ALL&stage=ALL&sort=NEWEST&page=$page&pageSize=20',
                  ),
            ),
            empty: '目前沒有可選訂單，可不關聯訂單',
            item: (order) => ListTile(
              title: Text(
                '${order['kind'] == 'PREORDER' ? '預購' : '現貨'} ${order['title'] ?? '訂單'}',
              ),
              subtitle: Text(order['id']),
              onTap: () => Navigator.pop(context, order),
            ),
          ),
        ),
      ],
    ),
  );
}

Widget supportBodyField(TextEditingController controller, String label) =>
    TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      minLines: 3,
      maxLines: 8,
      maxLength: 4000,
      validator: (v) => v == null || v.trim().isEmpty ? '請填寫$label' : null,
    );

class SupportTicketScreen extends ConsumerStatefulWidget {
  final String id;
  const SupportTicketScreen({super.key, required this.id});
  @override
  ConsumerState<SupportTicketScreen> createState() => _SupportTicketState();
}

class _SupportTicketState extends ConsumerState<SupportTicketScreen> {
  final form = GlobalKey<FormState>();
  final body = TextEditingController();
  @override
  void dispose() {
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RequestView(
    key: ValueKey('${widget.id}-${ref.watch(writesProvider).revision}'),
    load: () => ref
        .read(apiProvider)
        .request('GET', 'support-tickets/${Uri.encodeComponent(widget.id)}'),
    render: (data, reload) {
      final ticket = object(data['ticket']);
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          infoCard(ticket['subject'], [
            Text(supportStatuses[ticket['status']] ?? ticket['status']),
            Text(supportCategories[ticket['category']] ?? ticket['category']),
            if (ticket['orderId'] != null) Text('關聯現貨訂單：${ticket['orderId']}'),
            if (ticket['preorderOrderId'] != null)
              Text('關聯預購訂單：${ticket['preorderOrderId']}'),
          ]),
          for (final msg in objects(data['messages']))
            infoCard(
              msg['authorType'] == 'STAFF'
                  ? '客服 · ${msg['staffUsername'] ?? ''}'
                  : '顧客',
              [Text(dateLabel(msg['createdAt'])), SelectableText(msg['body'])],
            ),
          if (ticket['status'] == 'CLOSED') ...[
            const Text('客服單已結案，請建立新的客服單。'),
            OutlinedButton(
              onPressed: () => context.push('/account/support-tickets/new'),
              child: const Text('建立新單'),
            ),
          ] else
            Form(
              key: form,
              child: Column(
                children: [
                  supportBodyField(body, '回覆內容'),
                  WriteButton(
                    label: '送出回覆',
                    action: () async {
                      if (!form.currentState!.validate()) return;
                      try {
                        await ref.read(writesProvider).run(
                          'POST',
                          'support-tickets/${Uri.encodeComponent(widget.id)}/messages',
                          {
                            'requestId': const Uuid().v4(),
                            'body': body.text.trim(),
                          },
                          replayable: true,
                        );
                        body.clear();
                        reload();
                      } on ShopError catch (e) {
                        if (e.status == 409) reload();
                        rethrow;
                      }
                    },
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

const trackingLabels = {
  'PICKED_UP': '已收件',
  'IN_TRANSIT': '運送中',
  'ARRIVED_STORE': '已到門市',
  'OUT_FOR_DELIVERY': '配送中',
  'EXCEPTION': '配送異常',
  'RETURNED': '已退回',
};

class ShipmentTrackingScreen extends ConsumerWidget {
  final String id;
  const ShipmentTrackingScreen({super.key, required this.id});
  @override
  Widget build(BuildContext context, WidgetRef ref) => RequestView(
    load: () => ref
        .read(apiProvider)
        .request('GET', 'shipments/${Uri.encodeComponent(id)}/tracking'),
    render: (data, reload) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        infoCard('物流追蹤', [
          if (data['testCarrier'] == true)
            const Text(
              '測試物流，非真實物流資訊',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          Text('出貨單：${data['shipmentId']}'),
          Text(
            '配送方式：${const {'HOME': '宅配', 'CVS': '超商取貨'}[data['method']] ?? data['method']}',
          ),
          Text('物流商：${data['carrier'] ?? '尚未提供'}'),
          Text('貨件號：${data['trackingNumber'] ?? '尚未提供'}'),
        ]),
        if (objects(data['events']).isEmpty) const Text('目前沒有物流事件'),
        for (final event in objects(data['events']))
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Column(
                  children: [
                    Icon(Icons.circle, size: 14),
                    Expanded(child: VerticalDivider()),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(trackingLabels[event['code']] ?? event['code']),
                        Text(dateLabel(event['occurredAt'])),
                        if (event['description'] != null)
                          Text(event['description']),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class SitePagesScreen extends ConsumerWidget {
  const SitePagesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => RequestView(
    load: () => ref.read(apiProvider).publicPageGet('site-pages'),
    render: (data, reload) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('政策與說明', style: TextStyle(fontSize: 24)),
        for (final page in objects(data))
          Card(
            child: ListTile(
              title: Text(page['title']),
              subtitle: page['published'] != true ? const Text('條款審核中') : null,
              onTap: () => context.push(
                '/account/site-pages/${Uri.encodeComponent(page['slug'] as String)}',
              ),
            ),
          ),
        if (objects(data).isEmpty) const Text('目前沒有政策與說明'),
      ],
    ),
  );
}

class SitePageScreen extends ConsumerWidget {
  final String slug;
  const SitePageScreen({super.key, required this.slug});
  @override
  Widget build(BuildContext context, WidgetRef ref) => RequestView(
    load: () => ref
        .read(apiProvider)
        .publicPageGet('site-pages/${Uri.encodeComponent(slug)}'),
    render: (data, reload) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        infoCard(data['title'], [
          if (data['published'] != true)
            const Text('條款審核中')
          else
            SelectableText(data['body'] as String? ?? ''),
        ]),
      ],
    ),
  );
}
