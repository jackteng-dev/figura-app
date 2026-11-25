import 'dart:async';

import 'package:dio/dio.dart';
import 'package:figura/core/models.dart';
import 'package:figura/core/providers.dart';
import 'package:figura/core/storage.dart';
import 'package:figura/features/catalog.dart';
import 'package:figura/features/catalog_specs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'api_test.dart' show Adapter, apiFor, response;

Json product(int id, {Json? specs}) => {
  'id': 'p$id',
  'title': '商品 $id',
  'brand': '品牌甲',
  'category': '模型',
  'description': '',
  'skus': <Json>[],
  'minPriceTwd': 1280,
  'availability': 'IN_STOCK',
  'contentOrigin': 'REAL',
  'specs': ?specs,
};

Json page(int number, {int total = 21}) => {
  'items': [
    for (var i = (number - 1) * 20 + 1; i <= number * 20 && i <= total; i++)
      product(i),
  ],
  'total': total,
  'page': number,
  'pageSize': 20,
};

const brandA = '00000000-0000-0000-0000-000000000001';
const brandB = '00000000-0000-0000-0000-000000000002';
const workId = '00000000-0000-0000-0000-000000000003';
const categoryId = '00000000-0000-0000-0000-000000000004';
Json option(String value, String label) => {
  'value': value,
  'label': label,
  'count': 21,
};
Json facets() => {
  'brands': [option(brandA, '品牌甲'), option(brandB, '品牌乙')],
  'works': [option(workId, '作品甲')],
  'categories': [option(categoryId, '模型')],
  'availability': [
    option('IN_STOCK', 'IN_STOCK'),
    option('PREORDER', 'PREORDER'),
    option('SOLD_OUT', 'SOLD_OUT'),
  ],
  'scales': [option('NON_SCALE', 'NON_SCALE')],
  'materials': [option('PVC', 'PVC'), option('RESIN', 'RESIN')],
  'productTypes': [option('PREPAINTED', 'PREPAINTED')],
  'editions': [option('LIMITED', 'LIMITED')],
  'total': 21,
  'priceMin': 100,
  'priceMax': 5000,
};

List<RequestOptions> searches(Adapter adapter) => adapter.requests
    .where((r) => Uri.parse(r.path).path == 'catalog/products')
    .toList();
Map<String, String> query(RequestOptions request) =>
    Uri.parse(request.path).queryParameters;

Future<void> mount(WidgetTester tester, Adapter adapter, Widget screen) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = apiFor(adapter, MemoryStore());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiProvider.overrideWith((_) => api)],
      child: MaterialApp(home: Scaffold(body: screen)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> chip(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(ValueKey('filter-$key-$value'));
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.descendant(
      of: find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(ListView),
      ),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> reachSecondPage(WidgetTester tester, Adapter adapter) async {
  for (
    var i = 0;
    i < 30 && !searches(adapter).any((r) => query(r)['page'] == '2');
    i++
  ) {
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('detail omits missing specs and translates supplied values', (
    tester,
  ) async {
    final data = product(
      1,
      specs: {
        'characterName': '星之旅人',
        'scale': 'NON_SCALE',
        'heightMm': 250,
        'materials': [
          'PVC',
          'ABS',
          'RESIN',
          'POLYSTONE',
          'METAL',
          'FABRIC',
          'OTHER',
        ],
        'productType': 'ACTION_FIGURE',
        'edition': 'DELUXE',
        'limited': false,
        'accessories': ['底座', ' ', '替換手'],
        'releaseMonth': '2027-03',
        'manufacturer': ' ',
        'specNote': null,
      },
    );
    await mount(
      tester,
      Adapter((_) async => response(200, data)),
      const ProductScreen(id: 'p1'),
    );
    await tester.scrollUntilVisible(find.text('商品規格'), 300);
    await tester.pumpAndSettle();
    final table = find.byType(Table);
    expect(
      find.descendant(of: table, matching: find.text('星之旅人')),
      findsOneWidget,
    );
    for (final text in [
      '無比例',
      '250',
      'PVC、ABS、樹脂、聚石、金屬、布料、其他',
      '可動模型',
      '豪華版',
      '否',
      '底座',
      '替換手',
      '2027-03',
    ]) {
      expect(
        find.descendant(of: table, matching: find.text(text)),
        findsOneWidget,
      );
    }
    for (final text in ['作品', '製造商', '尺寸', '規格補充', '預計發售日', '未知', '配件 3']) {
      expect(
        find.descendant(of: table, matching: find.text(text)),
        findsNothing,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI concept materials never appear in the real material row', (
    tester,
  ) async {
    final data =
        product(
          1,
          specs: {
            'materials': [
              'PVC',
            ], // Even an inconsistent response must not imply real materials.
            'conceptMaterials': ['RESIN', 'METAL'],
            'releaseDate': '2027-04-12',
            'releaseMonth': '2027-04',
          },
        )..addAll({
          'contentOrigin': 'AI_CONCEPT',
          'availability': 'PREORDER',
          'preorder': {
            'deadlineAt': '2026-12-10T20:30:00+08:00',
            'arrivalFrom': '2027-04-01',
            'arrivalTo': '2027-04-30',
          },
        });
    await mount(
      tester,
      Adapter((_) async => response(200, data)),
      const ProductScreen(id: 'p1'),
    );
    expect(find.text('AI 虛構展示商品'), findsOneWidget);
    expect(find.text('預購'), findsOneWidget);
    expect(find.text('預購截止 2026/12/10 20:30'), findsOneWidget);
    expect(find.text('預計到貨 2027/04/01 ～ 2027/04/30'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('商品規格'), 300);
    await tester.pumpAndSettle();
    expect(find.text('設定材質（概念）'), findsOneWidget);
    expect(find.text('樹脂、金屬'), findsOneWidget);
    expect(find.text('材質'), findsNothing);
    expect(find.text('PVC'), findsNothing);
    expect(find.text('2027/04/12'), findsOneWidget);
    expect(find.text('預計發售月份'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy detail with absent specs adds no fabricated fields', (
    tester,
  ) async {
    final data = product(1)..remove('brand');
    await mount(
      tester,
      Adapter((_) async => response(200, data)),
      const ProductScreen(id: 'p1'),
    );
    expect(find.byType(Table), findsNothing);
    expect(find.text('商品規格'), findsNothing);
    expect(find.text('未知'), findsNothing);
  });

  testWidgets(
    'search submits only on action and relevance requires a keyword',
    (tester) async {
      final adapter = Adapter((_) async => response(200, page(1, total: 0)));
      await mount(tester, adapter, const CatalogScreen());
      await tester.tap(find.text('最新'));
      await tester.pumpAndSettle();
      expect(find.text('相關度'), findsNothing);
      await tester.tap(find.text('最新').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  星 & 月  ');
      await tester.pumpAndSettle();
      expect(searches(adapter), hasLength(1));
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(query(searches(adapter).last), {
        'q': '星 & 月',
        'sort': 'NEWEST',
        'page': '1',
        'pageSize': '20',
      });
      await tester.tap(find.text('最新'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('相關度').last);
      await tester.pumpAndSettle();
      expect(query(searches(adapter).last)['sort'], 'RELEVANCE');
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.byTooltip('送出搜尋'));
      await tester.pumpAndSettle();
      expect(query(searches(adapter).last), {
        'sort': 'NEWEST',
        'page': '1',
        'pageSize': '20',
      });
    },
  );

  testWidgets(
    'facets and product search send all selected multi-value filters',
    (tester) async {
      final adapter = Adapter(
        (r) async => response(
          200,
          Uri.parse(r.path).path == 'catalog/facets'
              ? facets()
              : page(int.parse(query(r)['page']!)),
        ),
      );
      await mount(tester, adapter, const CatalogScreen());
      await tester.enterText(find.byType(TextField), '星 月');
      await tester.tap(find.byTooltip('送出搜尋'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('最新'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('價格低到高').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('篩選'));
      await tester.pumpAndSettle();
      await chip(tester, 'availability', 'IN_STOCK');
      await chip(tester, 'availability', 'PREORDER');
      await chip(tester, 'brandId', brandA);
      await chip(tester, 'brandId', brandB);
      await chip(tester, 'workId', workId);
      await chip(tester, 'categoryId', categoryId);
      await chip(tester, 'scale', 'NON_SCALE');
      await chip(tester, 'material', 'PVC');
      await chip(tester, 'material', 'RESIN');
      await chip(tester, 'productType', 'PREPAINTED');
      await chip(tester, 'edition', 'LIMITED');
      await tester.tap(find.text('只看限定'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '最低價格（NT\$）'),
        '100',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '最高價格（NT\$）'),
        '5000',
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      final expected = {
        'q': '星 月',
        'brandId': '$brandA,$brandB',
        'workId': workId,
        'categoryId': categoryId,
        'scale': 'NON_SCALE',
        'material': 'PVC,RESIN',
        'productType': 'PREPAINTED',
        'edition': 'LIMITED',
        'limited': 'true',
        'priceMin': '100',
        'priceMax': '5000',
      };
      final facetCalls = adapter.requests.where(
        (r) => Uri.parse(r.path).path == 'catalog/facets',
      );
      expect(query(facetCalls.last), {
        ...expected,
        'availability': 'IN_STOCK,PREORDER',
      });
      await tester.tap(find.text('套用篩選'));
      await tester.pumpAndSettle();
      expect(query(searches(adapter).last), {
        ...expected,
        'availability': 'IN_STOCK,PREORDER',
        'sort': 'PRICE_ASC',
        'page': '1',
        'pageSize': '20',
      });
      expect(searches(adapter), hasLength(4));
      await reachSecondPage(tester, adapter);
      await tester.pumpAndSettle();
      expect(query(searches(adapter).last), {
        ...expected,
        'availability': 'IN_STOCK,PREORDER',
        'sort': 'PRICE_ASC',
        'page': '2',
        'pageSize': '20',
      });
      expect(
        adapter.requests.every(
          (r) => r.method == 'GET' && r.headers['Authorization'] == null,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scroll loads page two once and changing conditions resets to page one',
    (tester) async {
      final pending = Completer<ResponseBody>();
      final adapter = Adapter((r) async {
        final params = query(r);
        if (params['page'] == '2') return pending.future;
        return response(200, page(1));
      });
      await mount(tester, adapter, const CatalogScreen());
      expect(find.text('共 21 筆'), findsOneWidget);
      expect(find.text('NT\$ 1280 起'), findsWidgets);
      expect(find.text('現貨'), findsWidgets);
      final list = find.byType(ListView);
      await reachSecondPage(tester, adapter);
      await tester.drag(list, const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        searches(adapter).where((r) => query(r)['page'] == '2'),
        hasLength(1),
      );
      pending.complete(response(200, page(2)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('商品 21'),
        400,
        scrollable: find.descendant(
          of: list,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('商品 21'), findsOneWidget);
      expect(searches(adapter), hasLength(2));
      expect(query(searches(adapter).last), {
        'sort': 'NEWEST',
        'page': '2',
        'pageSize': '20',
      });
      await tester.tap(find.text('最新'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('價格高到低').last);
      await tester.pumpAndSettle();
      expect(query(searches(adapter).last)['page'], '1');
      expect(query(searches(adapter).last)['sort'], 'PRICE_DESC');
      expect(find.text('商品 1'), findsOneWidget);
      expect(find.text('商品 21'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late page response cannot enter a newer search', (tester) async {
    final pending = Completer<ResponseBody>();
    final adapter = Adapter((r) async {
      final params = query(r);
      return params['page'] == '2'
          ? pending.future
          : response(200, page(1, total: params['q'] == null ? 21 : 0));
    });
    await mount(tester, adapter, const CatalogScreen());
    await reachSecondPage(tester, adapter);
    expect(
      searches(adapter).where((r) => query(r)['page'] == '2'),
      hasLength(1),
    );
    await tester.enterText(find.byType(TextField), '新搜尋');
    await tester.tap(find.byTooltip('送出搜尋'));
    await tester.pumpAndSettle();
    pending.complete(response(200, page(2)));
    await tester.pumpAndSettle();
    expect(find.text('共 0 筆'), findsOneWidget);
    expect(find.text('商品 21'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'price validation blocks invalid ranges and cancel leaves search intact',
    (tester) async {
      final adapter = Adapter(
        (r) async => response(
          200,
          Uri.parse(r.path).path == 'catalog/facets'
              ? facets()
              : page(1, total: 0),
        ),
      );
      await mount(tester, adapter, const CatalogScreen());
      await tester.tap(find.text('篩選'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '最低價格（NT\$）'),
        '200',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '最高價格（NT\$）'),
        '100',
      );
      await tester.tap(find.text('套用篩選'));
      await tester.pumpAndSettle();
      expect(find.text('最低價不可高於最高價'), findsNWidgets(2));
      expect(searches(adapter), hasLength(1));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('篩選'), findsOneWidget);
      expect(searches(adapter), hasLength(1));
    },
  );

  testWidgets('availability badges use all three API states', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (final status in availabilityLabels.keys)
                ProductAvailability(product: {'availability': status}),
            ],
          ),
        ),
      ),
    );
    for (final label in availabilityLabels.values) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('clearing applied filters also clears both price controllers', (
    tester,
  ) async {
    final adapter = Adapter(
      (r) async => response(
        200,
        Uri.parse(r.path).path == 'catalog/facets'
            ? facets()
            : page(1, total: 0),
      ),
    );
    await mount(tester, adapter, const CatalogScreen());
    await tester.tap(find.text('篩選'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '最低價格（NT\$）'),
      '100',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '最高價格（NT\$）'),
      '5000',
    );
    await tester.tap(find.text('只看限定'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await tester.tap(find.text('套用篩選'));
    await tester.pumpAndSettle();
    expect(query(searches(adapter).last)['priceMin'], '100');
    await tester.tap(find.text('篩選（3）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除篩選'));
    await tester.pumpAndSettle();
    for (final label in ['最低價格（NT\$）', '最高價格（NT\$）']) {
      expect(
        tester
            .widget<TextFormField>(find.widgetWithText(TextFormField, label))
            .controller!
            .text,
        isEmpty,
      );
    }
    await tester.tap(find.text('套用篩選'));
    await tester.pumpAndSettle();
    expect(query(searches(adapter).last), {
      'sort': 'NEWEST',
      'page': '1',
      'pageSize': '20',
    });
    expect(find.text('篩選'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
