import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shupick/app/store_controller.dart';
import 'package:shupick/data/api_product_repository.dart';
import 'package:shupick/data/mock_repositories.dart';
import 'package:shupick/domain/models.dart';
import 'package:shupick/presentation/screens/commerce_screens.dart';
import 'package:shupick/presentation/screens/product_detail_screen.dart';
import 'package:shupick/presentation/shared/app_theme.dart';
import 'package:shupick/presentation/shared/cart_item_options.dart';

const shoe = Product(
  id: 91,
  name: '실제 옵션 신발',
  category: '운동화',
  price: 89000,
  imageUrl: 'https://example.invalid/shoe',
  color: '화이트',
  gender: '공용',
);
Map<String, dynamic> option(
  int id,
  String color,
  String size, {
  int stock = 5,
}) => {
  'productVariantId': id,
  'productCode': 'SKU$id',
  'color': color,
  'size': size,
  'availableQuantity': stock,
  'inventoryStatus': stock > 0 ? 'AVAILABLE' : 'OUT_OF_STOCK',
};
StoreController storeWith(http.Client client) => StoreController(
  productsRepository: ApiProductRepository(
    baseUrl: 'http://test',
    client: client,
  ),
  accountRepository: MockAccountRepository(),
  orderRepository: MockOrderRepository(),
  reviewRepository: MockReviewRepository(),
  shoppingRepository: MockShoppingRepository(),
  supportRepository: MockSupportRepository(),
);

void main() {
  setUpAll(() async {
    await (FontLoader(
      'NotoSansKR',
    )..addFont(rootBundle.load('assets/fonts/NotoSansKR-Variable.ttf'))).load();
  });
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(393, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ShoepickTheme.light(),
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  http.Client client() => MockClient((request) async {
    if (request.url.path.endsWith('/recommendations')) {
      return http.Response('{"products":[],"coViewedProductIds":[]}', 200);
    }
    expect(request.url.path, '/products/91/options');
    return http.Response(
      jsonEncode([
        option(1, '화이트', '245'),
        option(2, '화이트', '250', stock: 0),
        option(3, '화이트', '245'),
        option(4, '블랙', '190'),
        option(5, '블랙', '195'),
      ]),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  testWidgets('장바구니 245 사이즈와 중복 서버 옵션이 있어도 예외가 발생하지 않는다', (tester) async {
    final store = storeWith(client());
    await store.load();
    store.cart.add(const CartItem(product: shoe, size: '245', color: '화이트'));
    await pump(
      tester,
      CartScreen(
        store: store,
        onOpen: (_) {},
        onCheckout: (_) {},
        onMessage: (_) {},
      ),
    );
    final dropdowns = tester
        .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .toList();
    final sizes = dropdowns.singleWhere((dropdown) => dropdown.value == '245');
    expect(sizes.items!.map((item) => item.value), ['245', '250']);
    expect(sizes.items!.last.enabled, isFalse);
    final colors = dropdowns.singleWhere((dropdown) => dropdown.value == '화이트');
    colors.onChanged!('블랙');
    await tester.pumpAndSettle();
    expect(store.cart.single.color, '블랙');
    expect(store.cart.single.size, '190');
    expect(tester.takeException(), isNull);
  });
  testWidgets('서버에서 삭제된 저장 사이즈는 안내하고 유효한 옵션으로 변경한다', (tester) async {
    final store = storeWith(client());
    ProductOption? changed;
    await pump(
      tester,
      SingleChildScrollView(
        child: CartItemOptions(
          store: store,
          item: const CartItem(product: shoe, size: '225', color: '화이트'),
          onChanged: (option) => changed = option,
        ),
      ),
    );
    final sizeDropdown = tester
        .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .singleWhere((dropdown) => dropdown.value == null);
    expect(find.text('225 (옵션 없음)'), findsOneWidget);
    sizeDropdown.onChanged!('245');
    expect(changed?.size, '245');
  });
  testWidgets('상세 화면은 색상별 서버 사이즈와 품절 상태를 표시한다', (tester) async {
    final store = storeWith(client());
    await pump(
      tester,
      ProductDetailScreen(
        product: shoe,
        store: store,
        onCart: () {},
        onBuy: (_) {},
        onOpenProduct: (_) {},
        onInquiry: () {},
        onMessage: (_) {},
      ),
    );
    await tester.ensureVisible(find.text('245'));
    expect(find.text('250'), findsOneWidget);
    expect(find.text('품절'), findsOneWidget);
    expect(find.text('240'), findsNothing);
    await tester.ensureVisible(find.text('블랙').first);
    await tester.tap(find.text('블랙').first);
    await tester.pumpAndSettle();
    expect(find.text('245'), findsNothing);
    expect(find.text('190'), findsOneWidget);
    expect(find.text('195'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('옵션 조회 실패 후 재시도하면 서버 사이즈를 표시한다', (tester) async {
    var requests = 0;
    final store = storeWith(
      MockClient((request) async {
        requests++;
        return requests == 1
            ? http.Response('unavailable', 503)
            : http.Response(
                jsonEncode([option(1, '화이트', '245')]),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
      }),
    );
    await pump(
      tester,
      SingleChildScrollView(
        child: CartItemOptions(
          store: store,
          item: const CartItem(product: shoe, size: '245', color: '화이트'),
          onChanged: (_) {},
        ),
      ),
    );
    expect(find.text('상품 옵션을 불러오지 못했어요.'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('상품 옵션을 불러오지 못했어요.'), findsNothing);
    expect(requests, 2);
    expect(tester.takeException(), isNull);
  });
}
