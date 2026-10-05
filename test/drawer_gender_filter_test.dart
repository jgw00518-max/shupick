import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shupick/app/shupick_app.dart';
import 'package:shupick/app/store_binding.dart';
import 'package:shupick/data/mock_repositories.dart';
import 'package:shupick/domain/models.dart';
import 'package:shupick/presentation/screens/catalog_screens.dart';
import 'widget_test.dart' show MemorySettingsRepository;

class DrawerProducts extends MockProductRepository {
  @override
  Future<CatalogMetadata> getCatalog() async => const CatalogMetadata(
    categories: {
      '스니커즈': ['캔버스/단화'],
      '키즈': ['키즈운동화'],
    },
    brands: {},
  );
  @override
  Future<List<Product>> getProducts() async => [
    for (final (id, gender, middle, sub) in [
      (1, '남성', '스니커즈', '캔버스/단화'),
      (2, '여성', '스니커즈', '캔버스/단화'),
      (3, '공용', '스니커즈', '캔버스/단화'),
      (4, '키즈', '키즈', '키즈운동화'),
      (5, '공용', '키즈', '키즈운동화'),
    ])
      Product(
        id: id,
        name: '테스트 상품 $id',
        category: '운동화',
        price: 59000,
        imageUrl: 'https://example.invalid/$id',
        color: '화이트',
        gender: gender,
        middleCategory: middle,
        subcategory: sub,
      ),
  ];
}

void main() {
  tearDown(Get.reset);
  Future<void> openDrawer(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ShupickApp(
        binding: StoreBinding(
          productsRepository: DrawerProducts(),
          accountRepository: MockAccountRepository(),
          reviewRepository: MockReviewRepository(),
          supportRepository: MockSupportRepository(),
          shoppingRepository: MockShoppingRepository(),
          settingsRepository: MemorySettingsRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('카테고리'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, '공용'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '키즈'), findsNothing);
  }

  for (final selected in ['남성', '여성', '공용']) {
    testWidgets('상단 $selected 선택과 관계없이 키즈 카테고리는 키즈 성별만 표시한다', (tester) async {
      await openDrawer(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, selected));
      await tester.pumpAndSettle();
      await tester.tap(find.text('키즈'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('키즈운동화'));
      await tester.pumpAndSettle();
      final products = tester
          .widget<ProductGrid>(find.byType(ProductGrid))
          .products;
      expect(products.map((p) => p.id), [4]);
      expect(find.text('키즈 · 키즈운동화'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('공용 버튼은 일반 카테고리에서 공용 성별을 조회한다', (tester) async {
    await openDrawer(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, '공용'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('스니커즈'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('캔버스/단화'));
    await tester.pumpAndSettle();
    final products = tester
        .widget<ProductGrid>(find.byType(ProductGrid))
        .products;
    expect(products.map((p) => p.id), [3]);
    expect(find.text('공용 · 캔버스/단화'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
