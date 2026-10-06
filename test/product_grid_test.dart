import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shupick/app/store_controller.dart';
import 'package:shupick/data/mock_repositories.dart';
import 'package:shupick/presentation/screens/catalog_screens.dart';

void main() {
  testWidgets('search history persists, deduplicates and restores a query', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = StoreController(
      productsRepository: MockProductRepository(),
      accountRepository: MockAccountRepository(),
      orderRepository: MockOrderRepository(),
      reviewRepository: MockReviewRepository(),
      shoppingRepository: MockShoppingRepository(),
      supportRepository: MockSupportRepository(),
    );
    store.products = await store.productsRepository.getProducts();
    addTearDown(store.dispose);
    Widget screen() => MaterialApp(
      home: Scaffold(
        body: SearchScreen(store: store, onOpen: (_) {}),
      ),
    );
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('인기 검색어'), findsOneWidget);
    expect(find.text('추천 검색어'), findsOneWidget);
    expect(find.text('나이키'), findsOneWidget);
    expect(find.text('스케쳐스'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '운동화');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('최근 검색어'), findsOneWidget);
    expect(find.widgetWithText(InputChip, '운동화'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '구두');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(InputChip, '운동화'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '운동화',
    );
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getStringList('shupick_recent_searches'), ['운동화', '구두']);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, '운동화'), findsOneWidget);
    expect(find.widgetWithText(InputChip, '구두'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(InputChip, '운동화'),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, '운동화'), findsNothing);
    expect(find.widgetWithText(InputChip, '구두'), findsOneWidget);
    expect(preferences.getStringList('shupick_recent_searches'), ['구두']);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, '운동화'), findsNothing);
    expect(find.widgetWithText(InputChip, '구두'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(InputChip, '구두'),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('최근 검색어'), findsNothing);
    expect(preferences.getStringList('shupick_recent_searches'), isEmpty);
    await tester.ensureVisible(find.widgetWithText(ActionChip, '러닝화'));
    await tester.tap(find.widgetWithText(ActionChip, '러닝화'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '러닝화',
    );
    expect(find.text('검색 결과가 없습니다.'), findsNothing);
    expect(preferences.getStringList('shupick_recent_searches'), ['러닝화']);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('나이키'));
    await tester.tap(find.text('나이키'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '나이키',
    );
    expect(preferences.getStringList('shupick_recent_searches'), [
      '나이키',
      '러닝화',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home campaign scrolls to all products horizontally', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = MockProductRepository();
    final store = StoreController(
      productsRepository: repository,
      accountRepository: MockAccountRepository(),
      orderRepository: MockOrderRepository(),
      reviewRepository: MockReviewRepository(),
      shoppingRepository: MockShoppingRepository(),
      supportRepository: MockSupportRepository(),
    );
    store.products = await repository.getProducts();
    addTearDown(store.dispose);
    int? openedId;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            store: store,
            onOpen: (product) => openedId = product.id,
            onCampaign: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final campaign = find.byKey(
      const ValueKey('campaign-products-매일 신기 좋은 신발'),
    );
    expect(tester.widget<ListView>(campaign).scrollDirection, Axis.horizontal);
    await tester.drag(campaign, const Offset(-600, 0));
    await tester.pumpAndSettle();
    final lastProduct = store.products.firstWhere((p) => p.id == 16);
    await tester.tap(
      find.descendant(of: campaign, matching: find.text(lastProduct.name)),
    );
    expect(openedId, 16);
    await tester.ensureVisible(find.text('새로운 상품 발매 소식'));
    await tester.pumpAndSettle();
    final news = find.byKey(const ValueKey('release-news-pages'));
    await tester.ensureVisible(news);
    await tester.pumpAndSettle();
    await tester.drag(news, const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<PageView>(news).controller!.page, closeTo(1, .01));
    await tester.ensureVisible(find.text('부츠 신상'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('부츠 신상'));
    await tester.pumpAndSettle();
    final autumn = find.byKey(const ValueKey('autumn-products-부츠'));
    await tester.ensureVisible(autumn);
    await tester.pumpAndSettle();
    final boot = store.products.firstWhere((p) => p.category == '부츠');
    await tester.tap(
      find.descendant(of: autumn, matching: find.text(boot.name)),
    );
    expect(openedId, boot.id);
    await tester.ensureVisible(find.text('브랜드별 베스트 상품'));
    await tester.pumpAndSettle();
    final best = find.byKey(const ValueKey('brand-best-products'));
    await tester.ensureVisible(best);
    await tester.pumpAndSettle();
    expect(tester.widget<ListView>(best).scrollDirection, Axis.horizontal);
    final ranked = List.of(store.products)
      ..sort((a, b) => b.salesCount.compareTo(a.salesCount));
    await tester.tap(
      find.descendant(of: best, matching: find.text(ranked.first.name)),
    );
    expect(openedId, ranked.first.id);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 360.0, 390.0, 720.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final details in [false, true]) {
        testWidgets('grid width=$width scale=$scale details=$details', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final repository = MockProductRepository();
          final products = await repository.getProducts();
          final store = StoreController(
            productsRepository: repository,
            accountRepository: MockAccountRepository(),
            orderRepository: MockOrderRepository(),
            reviewRepository: MockReviewRepository(),
            shoppingRepository: MockShoppingRepository(),
            supportRepository: MockSupportRepository(),
          );
          addTearDown(store.dispose);
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: ProductGrid(
                    products: products,
                    store: store,
                    onOpen: (_) {},
                    showDetails: details,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (details) {
            await tester.tap(find.text('SIZE ▼').first);
            await tester.pumpAndSettle();
            expect(find.text('230  240  250  260  270  280'), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
        });
      }
    }
  }
}
