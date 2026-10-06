import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/app/store_controller.dart';
import 'package:shupick/data/mock_repositories.dart';
import 'package:shupick/presentation/screens/commerce_screens.dart';

void main() {
  StoreController createStore() => StoreController(
    productsRepository: MockProductRepository(),
    accountRepository: MockAccountRepository(),
    orderRepository: MockOrderRepository(),
    reviewRepository: MockReviewRepository(),
    shoppingRepository: MockShoppingRepository(),
    supportRepository: MockSupportRepository(),
  );

  Future<void> showOrders(WidgetTester tester, StoreController store) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrdersScreen(
            store: store,
            onMessage: (_) {},
            onShipping: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('로그인 고객의 빈 주문 내역에는 로그인 요청을 표시하지 않는다', (tester) async {
    final store = createStore()..isLoggedIn = true;
    await showOrders(tester, store);
    expect(find.text('아직 주문한 내역이 없습니다.'), findsOneWidget);
    expect(find.textContaining('로그인 후'), findsNothing);
    store.dispose();
  });

  testWidgets('비회원의 주문 화면에는 로그인 안내를 표시한다', (tester) async {
    final store = createStore();
    await showOrders(tester, store);
    expect(find.text('로그인 후 주문 내역을 확인해주세요.'), findsOneWidget);
    expect(find.text('아직 주문한 내역이 없습니다.'), findsNothing);
    store.dispose();
  });

  testWidgets('주문 조회 오류는 빈 주문 내역으로 표시하지 않는다', (tester) async {
    final store = createStore()
      ..isLoggedIn = true
      ..ordersError = '주문 조회 오류';
    await showOrders(tester, store);
    expect(find.text('주문 조회 오류'), findsOneWidget);
    expect(find.text('아직 주문한 내역이 없습니다.'), findsNothing);
    store.dispose();
  });
}
