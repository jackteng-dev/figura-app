import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/providers.dart';
import 'common.dart';

String shipmentStatus(Json shipment) {
  final status = shipment['status'] as String?;
  if (status == 'WAITING') {
    final reason = const {
      'PAYMENT': '等待付款',
      'BALANCE': '等待尾款',
      'ARRIVAL': '等待到貨',
      'REVIEW': '付款待核對或退貨中',
      'FEE': '承擔運費的訂單已取消，請聯絡客服',
    }[shipment['waitingFor']];
    return '等待中 · ${reason ?? shipment['waitingFor'] ?? '原因待確認'}';
  }
  return const {
        'READY': '可出貨',
        'SHIPPED': '已出貨',
        'DELIVERED': '已送達',
        'CANCELLED': '已取消',
        'MERGED': '已合併',
      }[status] ??
      status ??
      '待確認';
}

/// Also used after PendingBanner replays the original shipment command.
Future<void> showShipmentAdjustment(
  BuildContext context,
  dynamic result,
) async {
  if (result is! Map || result['adjustment'] == null) return;
  final adjustment = object(result['adjustment']);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('運費差額'),
      content: Text(
        '${twd(adjustment['creditTwd'])} · ${const {'PENDING_REVIEW': '待店家審核', 'CREDITED_MOCK': '已記錄模擬折抵', 'DISMISSED': '已結案'}[adjustment['status']] ?? adjustment['status']}\n目前不會自動退款。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

class ShipmentsScreen extends ConsumerStatefulWidget {
  const ShipmentsScreen({super.key});
  @override
  ConsumerState<ShipmentsScreen> createState() => _ShipmentsScreenState();
}

class _ShipmentsScreenState extends ConsumerState<ShipmentsScreen> {
  final items = <Json>[];
  final selected = <String, int>{};
  final scroll = ScrollController();
  int nextPage = 1, total = 0, generation = 0;
  int? storageDays;
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
      final page = object(
        await ref
            .read(apiProvider)
            .request('GET', 'shipments?page=$nextPage&pageSize=20'),
      );
      if (!mounted || current != generation) return;
      setState(() {
        items.addAll(objects(page['items']));
        total = page['total'] as int;
        storageDays = page['storageDays'] as int;
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
      selected.clear();
      nextPage = 1;
      total = 0;
      storageDays = null;
      loading = false;
      error = null;
    });
    if (scroll.hasClients) scroll.jumpTo(0);
    await load();
  }

  Future<void> write(String path, Json body) async {
    try {
      final result = await ref.read(writesProvider).run('POST', path, {
        'requestId': const Uuid().v4(),
        ...body,
      }, replayable: true);
      // ACK clears pending before any GET. A failed reload only offers reading again.
      await reload();
      if (mounted) await showShipmentAdjustment(context, result);
    } on ShopError catch (e) {
      if (!mounted) return;
      message(context, e.status == 409 ? '出貨單已變更' : e);
      if (e.status == 409) await reload();
    }
  }

  Future<void> merge() async {
    if (selected.length < 2 || selected.length > 10) return;
    // Capture the versions the customer reviewed; never substitute fresh versions.
    final shipments = [
      for (final entry in selected.entries)
        {'id': entry.key, 'expectedVersion': entry.value},
    ];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('合併 ${shipments.length} 張出貨單'),
        content: const Text(
          '只合併寄送，不改訂單金額與付款；運費差額會由店家審核，目前不會自動退款\n\n配送方式與收件資料須相同；任一張暫存中，合併後沿用最早的暫存期限。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('確認合併'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await write('shipments/merge', {'shipments': shipments});
    }
  }

  Widget shipmentCard(Json item) {
    final shipment = object(item['shipment']);
    final id = shipment['id'] as String;
    final writes = ref.watch(writesProvider);
    final enabled = !writes.busy && writes.pending == null;
    return infoCard('出貨單 $id', [
      Text(shipmentStatus(shipment)),
      if (shipment['status'] == 'SHIPPED' || shipment['status'] == 'DELIVERED')
        OutlinedButton(
          onPressed: () => context.push(
            '/account/shipments/${Uri.encodeComponent(id)}/tracking',
          ),
          child: const Text('物流追蹤'),
        ),
      Text('配送方式：${shipment['methodName'] ?? shipment['method']}'),
      moneyRow('運費', shipment['feeTwd']),
      moneyRow('商品金額', shipment['goodsTwd']),
      if (shipment['heldAt'] != null)
        Text('暫存至 ${dateLabel(shipment['storageUntil']).split(' ').first}'),
      const Text('內含訂單'),
      for (final order in objects(shipment['orders']))
        Text(
          '${order['kind'] == 'PREORDER' ? '預購' : '現貨'} ${order['title'] ?? ''} · ${order['id']}',
        ),
      CheckboxListTile(
        key: ValueKey('merge-$id'),
        contentPadding: EdgeInsets.zero,
        title: const Text('合併寄送'),
        value: selected.containsKey(id),
        onChanged:
            item['mergeable'] == true &&
                enabled &&
                (selected.containsKey(id) || selected.length < 10)
            ? (value) => setState(() {
                if (value == true) {
                  selected[id] = shipment['version'] as int;
                } else {
                  selected.remove(id);
                }
              })
            : null,
      ),
      if (item['mergeable'] != true && item['blockedReason'] != null)
        Text(item['blockedReason']),
      if (item['canHold'] == true)
        WriteButton(
          label: '暫存到倉庫',
          action: () => write('shipments/$id/hold', {
            'expectedVersion': shipment['version'],
          }),
        ),
      if (item['canRelease'] == true)
        WriteButton(
          label: '取消暫存、安排寄送',
          action: () => write('shipments/$id/release', {
            'expectedVersion': shipment['version'],
          }),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(writesProvider.select((writes) => writes.revision), (_, _) {
      reload();
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('我的出貨', style: TextStyle(fontSize: 24)),
              if (storageDays != null)
                Text('暫存期間不會出貨，期限 $storageDays 天（測試設定，正式政策待核定）。'),
              Text('已選 ${selected.length} 張（合併需 2–10 張）'),
              WriteButton(
                label: '合併選取的出貨單',
                enabled: selected.length >= 2 && selected.length <= 10,
                action: merge,
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              controller: scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                ...items.map(shipmentCard),
                if (loading) const Center(child: CircularProgressIndicator()),
                if (error != null) ...[
                  Text(
                    error is ShopError
                        ? (error as ShopError).message
                        : '無法讀取資料',
                  ),
                  TextButton(onPressed: load, child: const Text('重新讀取')),
                ],
                if (!loading && error == null && items.isEmpty)
                  const Text('目前沒有出貨單'),
                if (!loading && error == null && items.length < total)
                  TextButton(onPressed: load, child: const Text('載入更多')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
