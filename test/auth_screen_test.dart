import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shupick/app/store_controller.dart';
import 'package:shupick/data/mock_repositories.dart';
import 'package:shupick/presentation/screens/account_screens.dart';

void main() {
  testWidgets('auth layout supports small screens and existing login flow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 640);
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
    addTearDown(store.dispose);
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: AuthScreen(
              store: store,
              onBack: () {},
              onDone: () => completed = true,
              onMessage: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final login = find.widgetWithText(FilledButton, '로그인');
    await tester.ensureVisible(login);
    await tester.pumpAndSettle();
    await tester.tap(login);
    await tester.pumpAndSettle();
    expect(find.text('올바른 이메일 주소를 입력해주세요.'), findsOneWidget);
    final signup = find.widgetWithText(TextButton, '회원가입');
    await tester.ensureVisible(signup);
    await tester.pumpAndSettle();
    await tester.tap(signup);
    await tester.pumpAndSettle();
    final emailSignup = find.widgetWithText(OutlinedButton, '이메일로 가입');
    await tester.ensureVisible(emailSignup);
    await tester.pumpAndSettle();
    await tester.tap(emailSignup);
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(tester.takeException(), isNull);
    final back = find.widgetWithText(TextButton, '로그인으로 돌아가기');
    await tester.ensureVisible(back);
    await tester.pumpAndSettle();
    await tester.tap(back);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'user@sole.kr');
    await tester.enterText(find.byType(TextFormField).at(1), 'sole1234');
    await tester.ensureVisible(login);
    await tester.pumpAndSettle();
    await tester.tap(login);
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(store.isLoggedIn, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'guest lookup validates fields without signing in and email is saved',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'shupick_saved_login_email': 'saved@example.com',
      });
      final store = StoreController(
        productsRepository: MockProductRepository(),
        accountRepository: MockAccountRepository(),
        orderRepository: MockOrderRepository(),
        reviewRepository: MockReviewRepository(),
        shoppingRepository: MockShoppingRepository(),
        supportRepository: MockSupportRepository(),
      );
      addTearDown(store.dispose);
      final messages = <String>[];
      var done = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuthScreen(
              store: store,
              onBack: () {},
              onDone: () => done = true,
              onMessage: messages.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('member-email')))
            .controller!
            .text,
        'saved@example.com',
      );
      final guestTab = find.text('비회원 주문조회');
      await tester.ensureVisible(guestTab);
      await tester.pumpAndSettle();
      await tester.tap(guestTab);
      await tester.pumpAndSettle();
      final lookup = find.widgetWithText(FilledButton, '주문 조회');
      await tester.ensureVisible(lookup);
      await tester.pumpAndSettle();
      await tester.tap(lookup);
      await tester.pumpAndSettle();
      expect(find.text('주문번호를 입력해주세요.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('guest-order-number')),
        'SS0928-1842',
      );
      await tester.enterText(
        find.byKey(const ValueKey('guest-order-district')),
        '잘못된 지역',
      );
      await tester.ensureVisible(lookup);
      await tester.pumpAndSettle();
      await tester.tap(lookup);
      await tester.pumpAndSettle();
      expect(messages.last, '주문번호와 배송 지역을 확인해주세요.');
      await tester.enterText(
        find.byKey(const ValueKey('guest-order-district')),
        '성동구',
      );
      await tester.ensureVisible(lookup);
      await tester.pumpAndSettle();
      await tester.tap(lookup);
      await tester.pumpAndSettle();
      expect(find.text('주문번호: SS0928-1842'), findsOneWidget);
      expect(store.isLoggedIn, isFalse);
      expect(done, isFalse);
      await tester.ensureVisible(find.text('회원 로그인'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('회원 로그인'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('member-email')),
        'user@sole.kr',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'sole1234');
      final login = find.widgetWithText(FilledButton, '로그인');
      await tester.ensureVisible(login);
      await tester.pumpAndSettle();
      await tester.tap(login);
      await tester.pumpAndSettle();
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString('shupick_saved_login_email'),
        'user@sole.kr',
      );
      expect(done, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
