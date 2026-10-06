import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/app/store_controller.dart';
import 'package:shupick/data/mock_repositories.dart';
import 'package:shupick/presentation/screens/account_screens.dart';
import 'package:shupick/presentation/shared/app_theme.dart';

class RecordingAccount extends MockAccountRepository {
  String? savedName, savedPhone, savedEmail;
  DateTime? savedBirthDate;
  @override
  Future<void> signUp(
    String email,
    String password, {
    String? name,
    String? phone,
    DateTime? birthDate,
  }) async {
    savedEmail = email;
    savedName = name;
    savedPhone = phone;
    savedBirthDate = birthDate;
  }
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'NotoSansKR',
    )..addFont(rootBundle.load('assets/fonts/NotoSansKR-Variable.ttf'))).load();
  });
  Future<void> openSignup(WidgetTester tester, RecordingAccount account) async {
    tester.view.physicalSize = const Size(320, 852);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = StoreController(
      productsRepository: MockProductRepository(),
      accountRepository: account,
      orderRepository: MockOrderRepository(),
      reviewRepository: MockReviewRepository(),
      shoppingRepository: MockShoppingRepository(),
      supportRepository: MockSupportRepository(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ShoepickTheme.light(),
        home: Scaffold(
          body: AuthScreen(
            store: store,
            onBack: () {},
            onDone: () {},
            onMessage: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('회원가입'));
    await tester.tap(find.text('회원가입'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이메일로 가입'));
    await tester.pumpAndSettle();
  }

  Future<void> field(WidgetTester tester, String label, String text) async {
    final finder = find.widgetWithText(TextFormField, label);
    await tester.ensureVisible(finder);
    await tester.enterText(finder, text);
    await tester.pump();
  }

  Future<void> select(WidgetTester tester, int index, int value) async {
    tester
        .widgetList<DropdownButtonFormField<int>>(
          find.byType(DropdownButtonFormField<int>),
        )
        .elementAt(index)
        .onChanged!(value);
    await tester.pumpAndSettle();
  }

  testWidgets('회원가입 입력 정보를 저장소에 전달한다', (tester) async {
    final account = RecordingAccount();
    await openSignup(tester, account);
    await field(tester, '이름', '홍길동');
    await field(tester, '전화번호', '010-1234-5678');
    await select(tester, 0, 2000);
    await select(tester, 1, 2);
    await select(tester, 2, 29);
    await field(tester, '이메일', 'new@example.com');
    await field(tester, '비밀번호', 'secure1234');
    await field(tester, '비밀번호 확인', 'secure1234');
    tester.testTextInput.hide();
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('가입하기'));
    await tester.pumpAndSettle();
    expect(account.savedEmail, 'new@example.com');
    expect(account.savedName, '홍길동');
    expect(account.savedPhone, '01012345678');
    expect(account.savedBirthDate, DateTime(2000, 2, 29));
    expect(tester.takeException(), isNull);
  });
  testWidgets('윤년 변경 시 유효하지 않은 날짜를 해제하고 필수 입력을 검증한다', (tester) async {
    final account = RecordingAccount();
    await openSignup(tester, account);
    await select(tester, 0, 2000);
    await select(tester, 1, 2);
    await select(tester, 2, 29);
    await select(tester, 0, 2001);
    final day = tester
        .widgetList<DropdownButtonFormField<int>>(
          find.byType(DropdownButtonFormField<int>),
        )
        .last;
    expect(day.initialValue, isNull);
    final dropdown = tester
        .widgetList<DropdownButton<int>>(find.byType(DropdownButton<int>))
        .last;
    expect(dropdown.items!.length, 28);
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('가입하기'));
    await tester.pumpAndSettle();
    expect(account.savedEmail, isNull);
    expect(find.text('이름을 입력해주세요.'), findsOneWidget);
    expect(find.text('올바른 전화번호를 입력해주세요.'), findsOneWidget);
    expect(find.text('일을 선택해주세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
