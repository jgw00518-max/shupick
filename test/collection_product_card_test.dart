import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/domain/models.dart';
import 'package:shupick/presentation/shared/app_theme.dart';
import 'package:shupick/presentation/shared/collection_product_card.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'NotoSansKR',
    )..addFont(rootBundle.load('assets/fonts/NotoSansKR-Variable.ttf'))).load();
  });
  const product = Product(
    id: 1,
    name: '매일 편하게 신는 프리미엄 라이트 러닝 스니커즈',
    category: '운동화',
    price: 129000,
    imageUrl: 'https://example.invalid/shoe.png',
    color: '오프화이트',
    gender: '공용',
  );
  Future<void> pump(
    WidgetTester tester, {
    required VoidCallback onOpen,
    VoidCallback? onRemove,
    bool dark = false,
  }) async {
    tester.view.physicalSize = const Size(320, 852);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? ShoepickTheme.dark() : ShoepickTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: CollectionProductCard(
              product: product,
              onOpen: onOpen,
              onRemove: onRemove,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('큰 글씨와 긴 상품명에서 카드와 찜 해제 동작을 구분한다', (tester) async {
    var opened = 0;
    var removed = 0;
    await pump(tester, onOpen: () => opened++, onRemove: () => removed++);
    expect(find.text(product.name), findsOneWidget);
    expect(find.text('129,000원'), findsOneWidget);
    await tester.tap(find.byTooltip('찜 해제'));
    expect(removed, 1);
    expect(opened, 0);
    await tester.tap(find.text(product.name));
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('최근 본 상품은 다크 모드에서도 전체 카드로 상세를 연다', (tester) async {
    var opened = false;
    await pump(tester, dark: true, onOpen: () => opened = true);
    expect(find.byTooltip('찜 해제'), findsNothing);
    await tester.tap(find.text('129,000원'));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });
}
