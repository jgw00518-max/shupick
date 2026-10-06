import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/app/store_controller.dart';
import 'package:shupick/data/mock_repositories.dart';
import 'package:shupick/domain/models.dart';
import 'package:shupick/domain/repositories.dart';
import 'package:shupick/presentation/screens/product_detail_screen.dart';
import 'package:shupick/presentation/shared/store_widgets.dart';

const _product = Product(
  id: 101,
  name: 'Synthetic loading-test shoe',
  category: '운동화',
  price: 10000,
  imageUrl: 'https://synthetic.invalid/shoe.png',
  images: {'블랙': 'https://synthetic.invalid/shoe.png'},
  color: '블랙',
  gender: '공용',
);

class _Products implements ProductRepository {
  @override
  Future<List<Product>> getProducts() async => [_product];

  @override
  Future<List<ProductOption>> getProductOptions(int productId) async => const [
    ProductOption(
      productVariantId: 1011,
      productCode: 'SYNTHETIC-101-260',
      color: '블랙',
      size: '260',
      availableQuantity: 5,
      inventoryStatus: 'AVAILABLE',
    ),
  ];
}

class _Shopping implements ShoppingRepository {
  _Shopping({this.failLoad = false});

  bool failLoad;
  int saves = 0;

  @override
  Future<ShoppingSnapshot> load(List<Product> products) async {
    if (failLoad) throw StateError('Synthetic local shopping load failure');
    return const ShoppingSnapshot(cart: [], wishedIds: {}, recentIds: []);
  }

  @override
  Future<void> save(ShoppingSnapshot snapshot) async {
    saves++;
  }
}

StoreController _createStore(_Shopping shopping) {
  final store = StoreController(
    productsRepository: _Products(),
    accountRepository: MockAccountRepository(),
    orderRepository: MockOrderRepository(),
    reviewRepository: MockReviewRepository(),
    shoppingRepository: shopping,
    supportRepository: MockSupportRepository(),
  );
  addTearDown(store.dispose);
  return store;
}

void _sizeScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openSelectedOptions(
  WidgetTester tester,
  StoreController store, {
  required void Function(List<CartItem>) onCart,
  required void Function(List<CartItem>) onBuy,
  required void Function(String) onMessage,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => ProductOptionsSheet(
                product: _product,
                store: store,
                initialColor: _product.color,
                onCart: onCart,
                onBuy: onBuy,
                onMessage: onMessage,
              ),
            ),
            child: const Text('옵션 열기'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('옵션 열기'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(OutlinedButton, '블랙'));
  await tester.pump();
  await tester.tap(find.widgetWithText(OutlinedButton, '260\n재고 5'));
  await tester.pump();
  expect(find.text('블랙 · 260'), findsOneWidget);
}

void main() {
  for (final failure in [false, true]) {
    for (final buy in [false, true]) {
      testWidgets('${failure ? '쇼핑 load 실패' : '초기 쇼핑 미로드'} 상태에서 '
          '${buy ? '바로 구매' : '장바구니'}는 오류를 표시하고 옵션 창을 유지한다', (tester) async {
        _sizeScreen(tester);
        final shopping = _Shopping(failLoad: failure);
        final store = _createStore(shopping);
        if (failure) await store.load();
        expect(store.shoppingReady, isFalse);
        final cartCalls = <List<CartItem>>[];
        final buyCalls = <List<CartItem>>[];
        final messages = <String>[];
        await _openSelectedOptions(
          tester,
          store,
          onCart: cartCalls.add,
          onBuy: buyCalls.add,
          onMessage: messages.add,
        );

        await tester.tap(find.text(buy ? '바로 구매' : '장바구니'));
        await tester.pumpAndSettle();

        expect(cartCalls, isEmpty);
        expect(buyCalls, isEmpty);
        expect(messages, isEmpty);
        expect(shopping.saves, 0);
        expect(find.byType(ProductOptionsSheet), findsOneWidget);
        expect(find.text('블랙 · 260'), findsOneWidget);
        expect(
          find.text(store.shoppingError ?? '계정과 장바구니 정보를 불러온 뒤 다시 시도해주세요.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final buy in [false, true]) {
    testWidgets('쇼핑 준비 완료 시 ${buy ? '바로 구매' : '장바구니'}는 선택한 옵션을 한 번 전달한다', (
      tester,
    ) async {
      _sizeScreen(tester);
      final shopping = _Shopping();
      final store = _createStore(shopping);
      await store.load();
      expect(store.shoppingReady, isTrue);
      final cartCalls = <List<CartItem>>[];
      final buyCalls = <List<CartItem>>[];
      await _openSelectedOptions(
        tester,
        store,
        onCart: cartCalls.add,
        onBuy: buyCalls.add,
        onMessage: (_) {},
      );

      await tester.tap(find.text(buy ? '바로 구매' : '장바구니'));
      await tester.pumpAndSettle();

      final calls = buy ? buyCalls : cartCalls;
      expect(buy ? cartCalls : buyCalls, isEmpty);
      expect(calls, hasLength(1));
      expect(calls.single, hasLength(1));
      expect(calls.single.single.product.id, _product.id);
      expect(calls.single.single.size, '260');
      expect(calls.single.single.color, '블랙');
      expect(calls.single.single.quantity, 1);
      expect(find.byType(ProductOptionsSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('상품 카드의 찜은 쇼핑 준비 전 비활성화되고 준비 후 동작한다', (tester) async {
    _sizeScreen(tester);
    final shopping = _Shopping();
    final store = _createStore(shopping);
    Widget card() => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 280,
          child: ProductCard(product: _product, store: store, onOpen: () {}),
        ),
      ),
    );
    await tester.pumpWidget(card());
    final wish = find.widgetWithIcon(IconButton, Icons.favorite_border);
    expect(tester.widget<IconButton>(wish).onPressed, isNull);
    expect(store.wishedIds, isEmpty);
    expect(shopping.saves, 0);

    await store.load();
    await tester.pumpWidget(card());
    expect(tester.widget<IconButton>(wish).onPressed, isNotNull);
    await tester.tap(wish);
    await tester.pump();
    expect(store.wishedIds, {_product.id});
    expect(shopping.saves, 1);
    expect(tester.takeException(), isNull);
  });
}
