import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models.dart';
import '../core/providers.dart';
import 'catalog.dart' show ProductImage;
import 'catalog_specs.dart';
import 'common.dart';

String _path(String resource, Map<String, String> parameters) =>
    Uri(path: resource, queryParameters: parameters).toString();

const _sorts = {
  'NEWEST': '最新',
  'PRICE_ASC': '價格低到高',
  'PRICE_DESC': '價格高到低',
  'RELEASE_ASC': '發售日近到遠',
  'RELEASE_DESC': '發售日遠到近',
  'RELEVANCE': '相關度',
};

class ProductSearch extends ConsumerStatefulWidget {
  const ProductSearch({super.key});
  @override
  ConsumerState<ProductSearch> createState() => _ProductSearchState();
}

class _ProductSearchState extends ConsumerState<ProductSearch> {
  final _search = TextEditingController();
  String _q = '', _sort = 'NEWEST';
  Map<String, String> _filters = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    setState(() {
      _q = _search.text.trim();
      if (_q.isEmpty && _sort == 'RELEVANCE') _sort = 'NEWEST';
    });
  }

  Future<void> _filter() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .92,
        child: _FilterSheet(q: _q, filters: _filters),
      ),
    );
    if (result != null && mounted) setState(() => _filters = result);
  }

  @override
  Widget build(BuildContext context) {
    final parameters = {if (_q.isNotEmpty) 'q': _q, ..._filters, 'sort': _sort};
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _search,
            maxLength: 80,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: '搜尋商品',
              hintText: '名稱、角色、作品或品牌',
              counterText: '',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: '送出搜尋',
                onPressed: _submit,
                icon: const Icon(Icons.search),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_sort),
                  initialValue: _sort,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '排序'),
                  items: [
                    for (final entry in _sorts.entries)
                      if (entry.key != 'RELEVANCE' || _q.isNotEmpty)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _sort = value);
                  },
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: _filter,
                icon: const Icon(Icons.filter_list),
                label: Text(_filters.isEmpty ? '篩選' : '篩選（${_filters.length}）'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _ProductResults(
            key: ValueKey(_path('products', parameters)),
            parameters: parameters,
          ),
        ),
      ],
    );
  }
}

class _ProductResults extends ConsumerStatefulWidget {
  final Map<String, String> parameters;
  const _ProductResults({super.key, required this.parameters});
  @override
  ConsumerState<_ProductResults> createState() => _ProductResultsState();
}

class _ProductResultsState extends ConsumerState<_ProductResults> {
  final _scroll = ScrollController(keepScrollOffset: false);
  final _extra = <Json>[];
  int _page = 1, _generation = 0, _total = 0;
  bool _loading = false;
  Object? _error;
  bool get _hasMore => _page * 20 < _total && _page < 1000;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<dynamic> _load(int page) => ref
      .read(apiProvider)
      .publicGet(
        _path('products', {
          ...widget.parameters,
          'page': '$page',
          'pageSize': '20',
        }),
      );

  Future<dynamic> _first() async {
    final generation = ++_generation;
    _page = 1;
    _total = 0;
    _extra.clear();
    _loading = false;
    _error = null;
    final data = await _load(1);
    if (mounted && generation == _generation) {
      _total = (object(data)['total'] as num).toInt();
    }
    return data;
  }

  Future<void> _next() async {
    if (_loading || !_hasMore) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = object(await _load(_page + 1));
      if (!mounted || generation != _generation) return;
      setState(() {
        _extra.addAll(objects(data['items']));
        _page++;
        _total = (data['total'] as num).toInt();
      });
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => RequestView(
    load: _first,
    render: (data, reload) {
      final result = object(data);
      final items = [...objects(result['items']), ..._extra];
      final hasMore = _hasMore;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Text('共 $_total 筆'),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.axis == Axis.vertical &&
                    notification.metrics.extentAfter < 240 &&
                    hasMore &&
                    !_loading &&
                    _error == null) {
                  _next();
                }
                return false;
              },
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: items.length + 1,
                itemBuilder: (context, index) {
                  if (index == items.length) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          if (items.isEmpty) const Text('目前沒有上架商品'),
                          if (_loading)
                            const Center(child: CircularProgressIndicator()),
                          if (_error != null) ...[
                            const Text('無法載入更多商品'),
                            TextButton(
                              onPressed: _next,
                              child: const Text('重試載入更多'),
                            ),
                          ] else if (hasMore && !_loading)
                            TextButton(
                              onPressed: _next,
                              child: const Text('載入更多'),
                            ),
                        ],
                      ),
                    );
                  }
                  final product = items[index];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => context.push('/products/${product['id']}'),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            ProductImage(product: product, size: 80),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${product['title']}',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (product['brand'] != null)
                                    Text('${product['brand']}'),
                                  Text(
                                    product['minPriceTwd'] == null
                                        ? '價格未提供'
                                        : '${twd(product['minPriceTwd'])} 起',
                                  ),
                                  ProductAvailability(product: product),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      );
    },
  );
}

const _groups = [
  ('availability', 'availability', '可售狀態'),
  ('brandId', 'brands', '品牌'),
  ('workId', 'works', '作品'),
  ('categoryId', 'categories', '分類'),
  ('scale', 'scales', '比例'),
  ('material', 'materials', '材質'),
  ('productType', 'productTypes', '類型'),
  ('edition', 'editions', '版本'),
];

String _facetLabel(String key, String value, String label) => switch (key) {
  'availability' => availabilityLabels[value] ?? '未知',
  'scale' => scaleLabel(value),
  'material' => materialLabels[value] ?? '未知',
  'productType' => productTypeLabels[value] ?? '未知',
  'edition' => editionLabels[value] ?? '未知',
  _ => label,
};

class _FilterSheet extends ConsumerStatefulWidget {
  final String q;
  final Map<String, String> filters;
  const _FilterSheet({required this.q, required this.filters});
  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late final Map<String, String> _draft = {...widget.filters};
  late final _min = TextEditingController(text: _draft['priceMin']);
  late final _max = TextEditingController(text: _draft['priceMax']);
  final _form = GlobalKey<FormState>();
  final _labels = <String, Map<String, String>>{};
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  String? _priceError(String? value) {
    final text = value?.trim() ?? '';
    if (text.isNotEmpty &&
        (!RegExp(r'^\d+$').hasMatch(text) ||
            int.tryParse(text) == null ||
            int.parse(text) > 2147483647)) {
      return '請輸入有效的非負整數';
    }
    final min = int.tryParse(_min.text.trim()),
        max = int.tryParse(_max.text.trim());
    if (min != null && max != null && min > max) return '最低價不可高於最高價';
    return null;
  }

  bool _prices() {
    if (!_form.currentState!.validate()) return false;
    for (final pair in [('priceMin', _min), ('priceMax', _max)]) {
      final value = pair.$2.text.trim();
      if (value.isEmpty) {
        _draft.remove(pair.$1);
      } else {
        _draft[pair.$1] = '${int.parse(value)}';
      }
    }
    return true;
  }

  void _priceChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (_prices()) setState(() {});
    });
  }

  void _toggle(String key, String value) {
    final selected = (_draft[key]?.split(',') ?? []).toSet();
    if (!selected.add(value)) selected.remove(value);
    setState(() {
      if (selected.isEmpty) {
        _draft.remove(key);
      } else {
        _draft[key] = (selected.toList()..sort()).join(',');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // The facets contract excludes availability, sorting and pagination.
    final parameters = {
      if (widget.q.isNotEmpty) 'q': widget.q,
      for (final entry in _draft.entries)
        if (entry.key != 'availability') entry.key: entry.value,
    };
    final path = _path('facets', parameters);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '篩選商品',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          ),
          Form(
            key: _form,
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _min,
                    decoration: const InputDecoration(labelText: '最低價格（NT\$）'),
                    keyboardType: TextInputType.number,
                    validator: _priceError,
                    onChanged: _priceChanged,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _max,
                    decoration: const InputDecoration(labelText: '最高價格（NT\$）'),
                    keyboardType: TextInputType.number,
                    validator: _priceError,
                    onChanged: _priceChanged,
                  ),
                ),
              ],
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('只看限定'),
            value: _draft['limited'] == 'true',
            onChanged: (value) => setState(() {
              if (value) {
                _draft['limited'] = 'true';
              } else {
                _draft.remove('limited');
              }
            }),
          ),
          Expanded(
            child: RequestView(
              key: ValueKey(path),
              load: () => ref.read(apiProvider).publicGet(path),
              render: (data, reload) {
                final facets = object(data);
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    Text('目前條件共 ${facets['total']} 筆（未套用可售狀態）'),
                    if (facets['priceMin'] != null &&
                        facets['priceMax'] != null)
                      Text(
                        '商品價格 ${twd(facets['priceMin'])} ～ ${twd(facets['priceMax'])}',
                      ),
                    for (final (key, name, title) in _groups) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 8),
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      _options(key, facets[name]),
                    ],
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                TextButton(
                  onPressed: () {
                    _debounce?.cancel();
                    _form.currentState!.reset();
                    _min.clear();
                    _max.clear();
                    setState(_draft.clear);
                  },
                  child: const Text('清除篩選'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    _debounce?.cancel();
                    if (_prices()) {
                      Navigator.pop(context, Map<String, String>.of(_draft));
                    }
                  },
                  child: const Text('套用篩選'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _options(String key, dynamic data) {
    final selected = _draft[key]?.split(',') ?? [];
    final options = <String, Json>{};
    final labels = _labels.putIfAbsent(key, () => {});
    for (final option in data is List ? objects(data) : <Json>[]) {
      final value = '${option['value']}';
      labels[value] = _facetLabel(key, value, '${option['label']}');
      options[value] = option;
    }
    // Keep selected zero-result values removable after a narrower facets response.
    for (final value in selected) {
      options.putIfAbsent(value, () => {'count': 0});
    }
    if (options.isEmpty) return const Text('沒有符合的選項');
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final entry in options.entries)
          FilterChip(
            key: ValueKey('filter-$key-${entry.key}'),
            label: Text(
              '${labels[entry.key] ?? _facetLabel(key, entry.key, entry.key)}（${entry.value['count']}）',
            ),
            selected: selected.contains(entry.key),
            onSelected: (_) => _toggle(key, entry.key),
          ),
      ],
    );
  }
}
