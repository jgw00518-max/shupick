import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/app/store_controller.dart';
import 'package:shupick/data/mock_repositories.dart';
import 'package:shupick/domain/customer_enrollment.dart';
import 'package:shupick/presentation/screens/member_enrollment_screen.dart';
import 'package:shupick/presentation/screens/account_screens.dart';
import 'package:shupick/presentation/screens/settings_screen.dart';
import 'package:shupick/presentation/shared/phone_enrollment_fields.dart';

class _Verifier implements PhoneVerifier {
  int sends = 0;
  int checks = 0;
  bool closed = false;
  bool reject = false;
  void Function(VerifiedPhone)? automatic;
  Completer<void>? pending;

  @override
  Future<void> sendCode(
    String phone, {
    required void Function(VerifiedPhone) onAutomaticVerification,
  }) async {
    sends++;
    automatic = onAutomaticVerification;
    if (pending != null) await pending!.future;
  }

  @override
  Future<VerifiedPhone> verifyCode(String code) async {
    checks++;
    if (reject) throw StateError('인증번호가 올바르지 않습니다.');
    return VerifiedPhone(number: '+821012345678', idToken: 'synthetic-proof');
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

class _Enrollment extends MockAccountRepository
    implements EnrollmentAccountRepository {
  @override
  String? enrollmentUserId = 'primary-A';
  EnrollmentProfile profile = const EnrollmentProfile(
    phoneVerified: true,
    maskedPhone: '010-****-5678',
  );
  int saves = 0;
  VerifiedPhone? savedProof;
  DateTime? savedBirthday;
  int enrollSignups = 0;
  String? savedName;

  @override
  Future<EnrollmentProfile> getEnrollmentProfile() async => profile;
  @override
  Future<void> saveEnrollment(VerifiedPhone? phone, DateTime? birthDate) async {
    saves++;
    savedProof = phone;
    savedBirthday = birthDate;
  }

  @override
  Future<void> signUpWithEnrollment(
    String email,
    String password,
    VerifiedPhone phone,
    DateTime? birthDate, {
    String? name,
  }) async {
    enrollSignups++;
    savedName = name;
  }
}

void main() {
  testWidgets(
    'email signup requires SMS while optional birthday can stay empty',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final account = _Enrollment();
      final verifier = _Verifier();
      final store = StoreController(
        productsRepository: MockProductRepository(),
        accountRepository: account,
        orderRepository: MockOrderRepository(),
        reviewRepository: MockReviewRepository(),
        shoppingRepository: MockShoppingRepository(),
        supportRepository: MockSupportRepository(),
      );
      addTearDown(store.dispose);
      final messages = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuthScreen(
              store: store,
              phoneVerifier: verifier,
              onBack: () {},
              onDone: () {},
              onMessage: messages.add,
            ),
          ),
        ),
      );
      await tester.tap(find.text('회원가입'));
      await tester.pump();
      await tester.tap(find.text('이메일로 가입'));
      await tester.pump();
      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(5));
      expect(find.text('생년월일 (선택)'), findsOneWidget);
      await tester.enterText(fields.at(0), 'Synthetic User');
      await tester.enterText(fields.at(1), 'synthetic@example.com');
      await tester.enterText(
        find.widgetWithText(TextFormField, '비밀번호'),
        'synthetic-password123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '비밀번호 확인'),
        'synthetic-password123',
      );

      await tester.enterText(fields.at(4), '01012345678');
      await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
      await tester.tap(find.text('가입하기'));
      await tester.pump();
      expect(account.enrollSignups, 0);
      expect(find.text('휴대폰 문자 인증을 완료해주세요.'), findsOneWidget);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('문자 인증번호 받기'));
      await tester.pump();
      verifier.automatic!(
        VerifiedPhone(number: '+821012345678', idToken: 'synthetic-proof'),
      );
      await tester.pump();
      await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
      await tester.tap(find.text('가입하기'));
      await tester.pumpAndSettle();
      expect(account.enrollSignups, 1);
      expect(account.savedName, 'Synthetic User');
      expect(messages, contains('회원가입이 완료되었습니다. 입력한 계정으로 로그인해주세요.'));
      expect(find.byType(PhoneEnrollmentFields), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'normalizes Korean mobile formats without accepting letters or other regions',
    () {
      for (final input in [
        '01012345678',
        '010-1234-5678',
        ' 010 1234 5678 ',
        '+821012345678',
      ]) {
        expect(normalizeKoreanMobile(input), '+821012345678');
      }
      for (final input in [
        '',
        '0101234',
        '01112345678',
        '+15555555555',
        '010abc12345678',
      ]) {
        expect(() => normalizeKoreanMobile(input), throwsStateError);
      }
      expect(
        VerifiedPhone(
          number: '+821012345678',
          idToken: 'synthetic-secret',
        ).toString(),
        'VerifiedPhone(redacted)',
      );
    },
  );

  Future<void> showFields(
    WidgetTester tester,
    _Verifier verifier,
    ValueChanged<VerifiedPhone?> changed, {
    bool keep = false,
    GlobalKey<FormState>? form,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Form(
              key: form,
              child: PhoneEnrollmentFields(
                verifier: verifier,
                keepExistingPhone: keep,
                onChanged: changed,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> send(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField), '01012345678');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('문자 인증번호 받기'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('idle form does not send SMS; explicit consent enables send', (
    tester,
  ) async {
    final verifier = _Verifier();
    final form = GlobalKey<FormState>();
    await showFields(tester, verifier, (_) {}, form: form);
    expect(verifier.sends, 0);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    expect(form.currentState!.validate(), isFalse);
    await send(tester);
    expect(verifier.sends, 1);
    expect(find.text('문자로 받은 인증번호 6자리'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    expect(verifier.closed, isTrue);
  });

  testWidgets(
    'incorrect code cannot mark verified; retry succeeds then number change clears proof',
    (tester) async {
      final verifier = _Verifier()..reject = true;
      VerifiedPhone? proof;
      final form = GlobalKey<FormState>();
      await showFields(tester, verifier, (value) => proof = value, form: form);
      await send(tester);
      await tester.enterText(find.byType(TextField).last, '123456');
      await tester.tap(find.text('인증번호 확인'));
      await tester.pump();
      expect(find.text('인증번호가 올바르지 않습니다.'), findsOneWidget);
      expect(proof, isNull);
      verifier.reject = false;
      await tester.tap(find.text('인증번호 확인'));
      await tester.pump();
      expect(proof?.idToken, 'synthetic-proof');
      expect(form.currentState!.validate(), isTrue);
      await tester.enterText(find.byType(TextFormField), '01087654321');
      await tester.pump();
      expect(proof, isNull);
      expect(form.currentState!.validate(), isFalse);
      // Old automatic callback must not verify the newly edited number.
      verifier.automatic!(
        VerifiedPhone(number: '+821012345678', idToken: 'late-secret'),
      );
      await tester.pump();
      expect(proof, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'consent withdrawal clears verification and five-minute timer expires',
    (tester) async {
      final verifier = _Verifier();
      VerifiedPhone? proof;
      await showFields(tester, verifier, (value) => proof = value);
      await send(tester);
      verifier.automatic!(
        VerifiedPhone(number: '+821012345678', idToken: 'synthetic-proof'),
      );
      await tester.pump();
      expect(proof, isNotNull);
      await tester.pump(const Duration(minutes: 5));
      expect(proof, isNull);
      expect(find.text('휴대폰 인증 후 5분이 지났습니다. 다시 인증해주세요.'), findsOneWidget);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('closing while code is pending ignores late automatic proof', (
    tester,
  ) async {
    final verifier = _Verifier()..pending = Completer<void>();
    VerifiedPhone? proof;
    await showFields(tester, verifier, (value) => proof = value);
    await send(tester);
    await tester.pumpWidget(const SizedBox());
    verifier.automatic!(
      VerifiedPhone(number: '+821012345678', idToken: 'late-secret'),
    );
    verifier.pending!.complete();
    await tester.pump();
    expect(proof, isNull);
    expect(verifier.closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing verified number may be kept without another SMS', (
    tester,
  ) async {
    final verifier = _Verifier();
    final form = GlobalKey<FormState>();
    await showFields(tester, verifier, (_) {}, keep: true, form: form);
    expect(form.currentState!.validate(), isTrue);
    expect(verifier.sends, 0);
    await tester.enterText(find.byType(TextFormField), '01087654321');
    expect(form.currentState!.validate(), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('birthday can be omitted or removed explicitly', (tester) async {
    DateTime? value = DateTime(2000, 1, 2);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BirthdayEnrollmentField(
            value: value,
            onChanged: (date) => value = date,
          ),
        ),
      ),
    );
    expect(find.text('생년월일 (선택)'), findsOneWidget);
    await tester.tap(find.text('생일 정보 삭제'));
    expect(value, isNull);
  });

  testWidgets('member form refuses to save into a switched account', (
    tester,
  ) async {
    final repository = _Enrollment();
    await tester.pumpWidget(
      MaterialApp(
        home: MemberEnrollmentScreen(
          repository: repository,
          verifier: _Verifier(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('등록된 인증 번호: 010-****-5678'), findsOneWidget);
    repository.enrollmentUserId = 'primary-B';
    await tester.ensureVisible(find.text('정보 저장'));
    await tester.tap(find.text('정보 저장'));
    await tester.pump();
    expect(repository.saves, 0);
    expect(find.text('계정이 변경되었습니다. 화면을 다시 열어주세요.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('guest settings does not expose enrollment', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            dark: false,
            language: '한국어',
            push: false,
            onDarkChanged: (_) {},
            onLanguageChanged: (_) {},
            onPushChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('휴대폰 인증·생일 등록'), findsNothing);
  });
}
