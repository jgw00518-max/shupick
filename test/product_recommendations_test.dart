import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/app/store_controller.dart';
import 'package:shupick/data/mock_repositories.dart';
import 'package:shupick/domain/models.dart';
import 'package:shupick/domain/product_recommendations.dart';
import 'package:shupick/domain/repositories.dart';
import 'package:shupick/presentation/shared/app_theme.dart';
import 'package:shupick/presentation/shared/product_recommendation_section.dart';

Product shoe(
  int id, {
  String gender = '공용',
  String category = '스포츠',
  String subcategory = '러닝화',
  int price = 89000,
}) => Product(
  id: id,
  name: 'SHOEPICK 상품 $id 가벼운 데일리 스니커즈',
  category: category,
  middleCategory: category,
  subcategory: subcategory,
  gender: gender,
  price: price,
  imageUrl: 'https://example.invalid/shoe.png',
  color: '블랙',
);

class RecommendationRepository extends MockProductRepository
    implements ProductRecommendationRepository {
  RecommendationRepository(this.loadRecommendations);
  final Future<ProductRecommendations> Function(int) loadRecommendations;
  @override
  Future<ProductRecommendations> getRecommendations(int productId) =>
      loadRecommendations(productId);
}

StoreController storeWith(
  ProductRepository repository,
  List<Product> products,
) => StoreController(
  productsRepository: repository,
  accountRepository: MockAccountRepository(),
  orderRepository: MockOrderRepository(),
  reviewRepository: MockReviewRepository(),
  shoppingRepository: MockShoppingRepository(),
  supportRepository: MockSupportRepository(),
)..products = products;

void main() {
  setUpAll(() async {
    await (FontLoader(
      'NotoSansKR',
    )..addFont(rootBundle.load('assets/fonts/NotoSansKR-Variable.ttf'))).load();
  });

  test('상품 번호에 관계없이 같은 종류를 우선하고 가격 차이로 정렬한다', () {
    final source = shoe(1001);
    final products = [
      source,
      shoe(9002, subcategory: '워킹화'),
      shoe(7001, price: 109000),
      shoe(6001, price: 99000),
      shoe(5001, gender: '키즈'),
      shoe(6001, price: 99000),
    ];
    expect(similarProducts(source, products).map((p) => p.id), [
      6001,
      7001,
      9002,
    ]);
  });

  test('키즈는 키즈를 추천하고 남성은 여성 전용 상품을 제외한다', () {
    final products = [
      shoe(1, gender: '키즈'),
      shoe(2, gender: '키즈'),
      shoe(3, gender: '남성'),
      shoe(4, gender: '여성'),
      shoe(5),
    ];
    expect(similarProducts(products.first, products).map((p) => p.id), [2]);
    expect(similarProducts(products[2], products).map((p) => p.id), [5]);
  });

  test('추천 API 실패 시 현재 상품 목록으로 유사 상품을 제공한다', () async {
    final source = shoe(100);
    final store = storeWith(
      RecommendationRepository((_) async => throw StateError('offline')),
      [source, shoe(200)],
    );
    final result = await store.getRecommendations(source);
    expect(result.products.single.id, 200);
    expect(result.hasCustomerViews, isFalse);
    store.dispose();
  });

  test('서버 추천 순서는 유지하되 본인·중복 상품과 잘못된 공동 조회 ID를 제외한다', () async {
    final source = shoe(100);
    final store = storeWith(
      RecommendationRepository(
        (_) async => ProductRecommendations(
          products: [shoe(300), source, shoe(200), shoe(300)],
          coViewedProductIds: {300, 100, 999},
        ),
      ),
      [source, shoe(200), shoe(300)],
    );
    final result = await store.getRecommendations(source);
    expect(result.products.map((p) => p.id), [300, 200]);
    expect(result.coViewedProductIds, {300});
    store.dispose();
  });

  Future<void> pumpSection(
    WidgetTester tester,
    StoreController store,
    Product product, {
    ValueChanged<Product>? onOpen,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ShoepickTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProductRecommendationSection(
              product: product,
              store: store,
              onOpenProduct: onOpen ?? (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('실제 공동 조회 제목과 가격을 표시하고 카드 터치로 상품을 연다', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final source = shoe(100);
    final next = shoe(200);
    final store = storeWith(
      RecommendationRepository(
        (_) async =>
            ProductRecommendations(products: [next], coViewedProductIds: {200}),
      ),
      [source, next],
    );
    Product? opened;
    await pumpSection(
      tester,
      store,
      source,
      onOpen: (product) => opened = product,
    );
    await tester.pumpAndSettle();
    expect(find.text('이 상품을 본 고객이 많이 찾아본 상품'), findsOneWidget);
    expect(find.text('89,000원'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('recommended-product-200')));
    expect(opened?.id, 200);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('상품 변경 후 늦게 도착한 이전 상품 추천은 무시한다', (tester) async {
    final first = Completer<ProductRecommendations>();
    final second = Completer<ProductRecommendations>();
    final source = shoe(100);
    final nextSource = shoe(200);
    final store = storeWith(
      RecommendationRepository(
        (id) => id == 100 ? first.future : second.future,
      ),
      [source, nextSource, shoe(300), shoe(400)],
    );
    await pumpSection(tester, store, source);
    await pumpSection(tester, store, nextSource);
    second.complete(ProductRecommendations(products: [shoe(400)]));
    await tester.pumpAndSettle();
    first.complete(
      ProductRecommendations(products: [shoe(300)], coViewedProductIds: {300}),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('recommended-product-400')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('recommended-product-300')), findsNothing);
    expect(find.text('함께 둘러보기 좋은 상품'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
