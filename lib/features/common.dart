import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/providers.dart';

void message(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        error is ShopError
            ? error.message
            : error is String
            ? error
            : '操作失敗，請稍後重試',
      ),
    ),
  );
}

Widget field(
  TextEditingController controller,
  String label, {
  bool secret = false,
  TextInputType? keyboard,
  String? Function(String?)? validator,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 16),
  child: TextFormField(
    controller: controller,
    obscureText: secret,
    autocorrect: !secret,
    enableSuggestions: !secret,
    keyboardType: keyboard,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    validator:
        validator ?? (v) => v == null || v.trim().isEmpty ? '請填寫$label' : null,
  ),
);
Widget moneyRow(String label, num? value, {bool emphasis = false}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 6),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label),
      Text(
        twd(value),
        style: TextStyle(
          fontSize: emphasis ? 20 : 16,
          fontWeight: emphasis ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    ],
  ),
);
Widget infoCard(String title, List<Widget> children) => Card(
  child: Padding(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  ),
);

class RequestView extends StatefulWidget {
  final Future<dynamic> Function() load;
  final Widget Function(dynamic, VoidCallback) render;
  const RequestView({super.key, required this.load, required this.render});
  @override
  State<RequestView> createState() => _RequestViewState();
}

class _RequestViewState extends State<RequestView> {
  late Future<dynamic> future;
  @override
  void initState() {
    super.initState();
    future = widget.load();
  }

  void reload() {
    if (!mounted) return;
    setState(() {
      future = widget.load();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                snapshot.error is ShopError
                    ? (snapshot.error as ShopError).message
                    : '無法讀取資料',
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: reload, child: const Text('重新讀取')),
            ],
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: () async {
          reload();
          await future;
        },
        child: widget.render(snapshot.data, reload),
      );
    },
  );
}

class PagedView extends StatefulWidget {
  final Future<Json> Function(int page) load;
  final Widget Function(Json item) item;
  final String empty;
  const PagedView({
    super.key,
    required this.load,
    required this.item,
    required this.empty,
  });
  @override
  State<PagedView> createState() => _PagedViewState();
}

class _PagedViewState extends State<PagedView> {
  int page = 1;
  @override
  Widget build(BuildContext context) => RequestView(
    key: ValueKey(page),
    load: () => widget.load(page),
    render: (data, reload) {
      final j = object(data), items = objects(j['items']);
      return ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(widget.empty),
            ),
          ...items.map(widget.item),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: page > 1 ? () => setState(() => page--) : null,
                child: const Text('上一頁'),
              ),
              Text('第 $page 頁 · 共 ${j['total']} 筆'),
              TextButton(
                onPressed: page * (j['pageSize'] as int) < (j['total'] as int)
                    ? () => setState(() => page++)
                    : null,
                child: const Text('下一頁'),
              ),
            ],
          ),
        ],
      );
    },
  );
}

class WriteButton extends ConsumerStatefulWidget {
  final String label;
  final Future<void> Function() action;
  final bool enabled;
  const WriteButton({
    super.key,
    required this.label,
    required this.action,
    this.enabled = true,
  });
  @override
  ConsumerState<WriteButton> createState() => _WriteButtonState();
}

class _WriteButtonState extends ConsumerState<WriteButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final writes = ref.watch(writesProvider);
    return FilledButton(
      onPressed:
          busy || writes.busy || writes.pending != null || !widget.enabled
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
      child: Text(busy ? '處理中…' : widget.label),
    );
  }
}
