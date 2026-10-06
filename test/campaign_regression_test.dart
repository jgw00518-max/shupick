import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shupick/app/shupick_app.dart';
import 'package:shupick/app/store_binding.dart';
import 'package:shupick/app/store_controller.dart';
import 'package:shupick/data/mock_repositories.dart';
import 'package:shupick/domain/models.dart';
import 'package:shupick/presentation/screens/catalog_screens.dart';
import 'package:shupick/presentation/shared/app_theme.dart';
import 'widget_test.dart' show MemorySettingsRepository;

Product product(int id) => Product(
  id: id,
  name: '서버 상품 $id',
  category: '운동화',
  price: 59000,
  imageUrl: 'https://example.invalid/$id',
  color: '화이트',
  gender: '공용',
);

class ServerIdsRepository extends MockProductRepository {
  @override
  Future<List<Product>> getProducts() async => [product(901)];
}

StoreController storeWith(List<Product> products) {
  final store = StoreController(
    productsRepository: MockProductRepository(),
    accountRepository: MockAccountRepository(),
    orderRepository: MockOrderRepository(),
    reviewRepository: MockReviewRepository(),
    shoppingRepository: MockShoppingRepository(),
    supportRepository: MockSupportRepository(),
  );
  store.products = products;
  return store;
}

void main() {
  tearDown(Get.reset);
  for (final title in ['이번 주 특가', '계절의 신발']) {
    testWidgets('홈에서 $title 진입 시 목업 ID가 없어도 실제 상품을 표시한다', (tester) async {
      tester.view.physicalSize = const Size(393, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ShupickApp(
          binding: StoreBinding(
            productsRepository: ServerIdsRepository(),
            accountRepository: MockAccountRepository(),
            reviewRepository: MockReviewRepository(),
            supportRepository: MockSupportRepository(),
            shoppingRepository: MockShoppingRepository(),
            settingsRepository: MemorySettingsRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(title).first);
      await tester.tap(find.text(title).first);
      await tester.pumpAndSettle();
      expect(find.byType(CampaignScreen), findsOneWidget);
      final grid = tester.widget<ProductGrid>(find.byType(ProductGrid));
      expect(grid.products.map((p) => p.id), [901]);
      expect(tester.takeException(), isNull);
    });
    testWidgets('$title 상품이 전혀 없으면 예외 없이 안내한다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ShoepickTheme.light(),
          home: Scaffold(
            body: CampaignScreen(
              title: title,
              store: storeWith([]),
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('기획전 상품이 없습니다.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('기획전 상품 일부가 있으면 지정 순서대로 해당 상품만 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ShoepickTheme.light(),
        home: Scaffold(
          body: CampaignScreen(
            title: '이번 주 특가',
            store: storeWith([product(19), product(901), product(5)]),
            onOpen: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final grid = tester.widget<ProductGrid>(find.byType(ProductGrid));
    expect(grid.products.map((p) => p.id), [5, 19]);
    expect(tester.takeException(), isNull);
  });
}
