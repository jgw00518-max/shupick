import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/app/store_controller.dart';
import 'package:shupick/data/mock_repositories.dart';
import 'package:shupick/presentation/screens/account_screens.dart';
import 'package:shupick/presentation/shared/app_theme.dart';

class NamedAccount extends MockAccountRepository {
  @override
  String? get displayName => '홍길동';
}

StoreController namedStore() => StoreController(
  productsRepository: MockProductRepository(),
  accountRepository: NamedAccount(),
  orderRepository: MockOrderRepository(),
  reviewRepository: MockReviewRepository(),
  shoppingRepository: MockShoppingRepository(),
  supportRepository: MockSupportRepository(),
);
void main() {
  for (final google in [false, true]) {
    testWidgets('${google ? "Google" : "이메일"} 로그인 시 마이페이지에 고객 이름이 표시된다', (
      tester,
    ) async {
      final store = namedStore();
      final loggedIn = google
          ? await store.signInWithGoogle()
          : await store.signIn('user@sole.kr', 'sole1234');
      expect(loggedIn, isTrue);
      expect(store.userName, '홍길동');
      expect(store.userEmail, 'user@sole.kr');
      await tester.pumpWidget(
        MaterialApp(
          theme: ShoepickTheme.light(),
          home: Scaffold(
            body: ProfileScreen(store: store, onGo: (_) {}, onLogout: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('홍길동 님'), findsOneWidget);
      await store.signOut();
      expect(store.userName, isNull);
      expect(store.userEmail, isNull);
      expect(store.isLoggedIn, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
