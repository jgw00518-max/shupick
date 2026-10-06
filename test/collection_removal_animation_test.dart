import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/app/store_controller.dart';
import 'package:shupick/data/mock_repositories.dart';
import 'package:shupick/domain/models.dart';
import 'package:shupick/presentation/screens/catalog_screens.dart';
import 'package:shupick/presentation/shared/app_theme.dart';
import 'package:shupick/presentation/shared/collection_product_card.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'NotoSansKR',
    )..addFont(rootBundle.load('assets/fonts/NotoSansKR-Variable.ttf'))).load();
  });
  const first = Product(
    id: 1,
    name: '라이트 러너',
    category: '운동화',
    price: 89000,
    imageUrl: 'https://example.invalid/1',
    color: '화이트',
    gender: '공용',
  );
  const second = Product(
    id: 2,
    name: '데일리 스니커즈',
    category: '운동화',
    price: 99000,
    imageUrl: 'https://example.invalid/2',
    color: '블랙',
    gender: '공용',
  );

  for (final count in [1, 2]) {
    testWidgets('찜 $count개에서 해제 카드는 축소 후 사라지고 남은 목록을 유지한다', (tester) async {
      tester.view.physicalSize = const Size(393, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = StoreController(
        productsRepository: MockProductRepository(),
        accountRepository: MockAccountRepository(),
        orderRepository: MockOrderRepository(),
        reviewRepository: MockReviewRepository(),
        shoppingRepository: MockShoppingRepository(),
        supportRepository: MockSupportRepository(),
      );
      await store.load();
      store.products = [];
      store.wishedIds.clear();
      store.products.addAll([first, if (count == 2) second]);
      store.wishedIds.addAll([1, if (count == 2) 2]);
      Future<void> render() => tester.pumpWidget(
        MaterialApp(
          theme: ShoepickTheme.light(),
          home: Scaffold(
            body: ProductCollectionScreen(
              title: '찜한 상품',
              products: store.wished,
              store: store,
              canRemove: true,
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await render();
      await tester.pumpAndSettle();
      final originalHeight = tester
          .getSize(find.widgetWithText(CollectionProductCard, first.name))
          .height;
      final originalSecondY = count == 2
          ? tester
                .getTopLeft(
                  find.widgetWithText(CollectionProductCard, second.name),
                )
                .dy
          : null;
      await tester.tap(find.byTooltip('찜 해제').first);
      expect(store.wishedIds.contains(1), isFalse);
      await render();
      expect(find.text(first.name), findsOneWidget);
      expect(find.text('저장한 상품이 없어요'), findsNothing);
      await tester.pump(const Duration(milliseconds: 150));
      final firstCard = find.widgetWithText(CollectionProductCard, first.name);
      final fade = tester.widget<FadeTransition>(
        find
            .ancestor(of: firstCard, matching: find.byType(FadeTransition))
            .first,
      );
      expect(fade.opacity.value, inExclusiveRange(0, 1));
      if (count == 2) {
        final newY = tester
            .getTopLeft(find.widgetWithText(CollectionProductCard, second.name))
            .dy;
        expect(newY, lessThan(originalSecondY!));
        expect(newY, greaterThan(originalSecondY - originalHeight - 16));
      }
      await tester.pumpAndSettle();
      expect(find.text(first.name), findsNothing);
      expect(
        find.text(count == 1 ? '저장한 상품이 없어요' : second.name),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
