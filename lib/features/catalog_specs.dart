import 'package:flutter/material.dart';

import '../core/models.dart';
import 'common.dart';

const availabilityLabels = {
  'IN_STOCK': '現貨',
  'PREORDER': '預購',
  'SOLD_OUT': '售完',
};
const materialLabels = {
  'PVC': 'PVC',
  'ABS': 'ABS',
  'RESIN': '樹脂',
  'POLYSTONE': '聚石',
  'METAL': '金屬',
  'FABRIC': '布料',
  'OTHER': '其他',
};
const productTypeLabels = {
  'PREPAINTED': '完成品',
  'ACTION_FIGURE': '可動模型',
  'MODEL_KIT': '組裝模型',
  'GARAGE_KIT': 'GK',
  'PRIZE': '景品',
  'BLIND_BOX': '盒玩',
  'STATUE': '雕像',
  'PLUSH': '布偶',
  'OTHER': '其他',
};
const editionLabels = {
  'STANDARD': '一般版',
  'LIMITED': '限定版',
  'BONUS': '特典版',
  'DELUXE': '豪華版',
};
String scaleLabel(String value) => value == 'NON_SCALE' ? '無比例' : value;
String? _value(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

List<String> _values(dynamic value) =>
    value is List ? value.map(_value).whereType<String>().toList() : [];

bool isConcept(Json product) =>
    (product['contentOrigin'] ??
        (product['specs'] as Map?)?['contentOrigin']) ==
    'AI_CONCEPT';

class ProductAvailability extends StatelessWidget {
  final Json product;
  const ProductAvailability({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final label = availabilityLabels[product['availability']];
    final preorder = product['preorder'] as Map?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            if (label != null) Chip(label: Text(label)),
            if (isConcept(product)) const Chip(label: Text('AI 虛構展示商品')),
          ],
        ),
        if (product['availability'] == 'PREORDER' && preorder != null) ...[
          if (_value(preorder['deadlineAt']) != null)
            Text('預購截止 ${dateLabel(preorder['deadlineAt'])}'),
          if (_value(preorder['arrivalFrom']) != null ||
              _value(preorder['arrivalTo']) != null)
            Text(
              '預計到貨 ${dateLabel(preorder['arrivalFrom'])} ～ ${dateLabel(preorder['arrivalTo'])}',
            ),
        ],
      ],
    );
  }
}

class ProductSpecs extends StatelessWidget {
  final Json product;
  const ProductSpecs({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final specs = product['specs'] is Map
        ? object(product['specs'])
        : <String, dynamic>{};
    final rows = <TableRow>[];
    void add(String label, dynamic value) {
      final text = _value(value);
      if (text == null) return;
      rows.add(
        TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
              child: Text(text),
            ),
          ],
        ),
      );
    }

    add('角色', specs['characterName']);
    add('作品', product['work']);
    add('品牌', product['brand']);
    add('製造商', specs['manufacturer']);
    if (_value(specs['scale']) case final String value) {
      add('比例', scaleLabel(value));
    }
    add('全高（mm）', specs['heightMm']);
    add('尺寸', specs['dimensions']);
    final materials = _values(
      specs[isConcept(product) ? 'conceptMaterials' : 'materials'],
    );
    add(
      isConcept(product) ? '設定材質（概念）' : '材質',
      materials.map((v) => materialLabels[v] ?? '未知').join('、'),
    );
    if (_value(specs['productType']) case final String value) {
      add('商品類型', productTypeLabels[value] ?? '未知');
    }
    if (_value(specs['edition']) case final String value) {
      add('版本', editionLabels[value] ?? '未知');
    }
    if (specs['limited'] is bool) {
      add('限定', specs['limited'] == true ? '是' : '否');
    }
    final accessories = _values(specs['accessories']);
    for (var i = 0; i < accessories.length; i++) {
      add('配件 ${i + 1}', accessories[i]);
    }
    if (_value(specs['releaseDate']) case final String value) {
      add('預計發售日', dateLabel(value));
    } else {
      add('預計發售月份', specs['releaseMonth']);
    }
    add('規格補充', specs['specNote']);
    if (rows.isEmpty) return const SizedBox.shrink();
    return infoCard('商品規格', [
      Table(
        columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(3)},
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        border: TableBorder(
          horizontalInside: BorderSide(color: Theme.of(context).dividerColor),
        ),
        children: rows,
      ),
    ]);
  }
}
