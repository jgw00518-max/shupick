import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/app/store_controller.dart';
import 'package:shupick/data/mock_repositories.dart';
import 'package:shupick/domain/models.dart';
import 'package:shupick/domain/repositories.dart';
import 'package:shupick/presentation/localization.dart';
import 'package:shupick/presentation/screens/account_screens.dart';
import 'package:shupick/presentation/shared/login_provider_badge.dart';

class _DelayedAccount extends MockAccountRepository
    implements IdentityAccountRepository, SocialAccountRepository {
  final Completer<bool> result = Completer<bool>();
  final Completer<void> signupResult = Completer<void>();
  final List<String> attempts = [];
  String? enteredEmail;
  String? enteredPassword;

  @override
  String? userId;

  @override
  String? get displayName => userId == null ? null : 'Synthetic member';

  @override
  String? get email => userId == null ? null : 'synthetic@example.com';

  Future<bool> _signIn(String provider) async {
    attempts.add(provider);
    final success = await result.future;
    if (success) userId = 'synthetic:$provider';
    return success;
  }

  @override
  Future<bool> signIn(String email, String password) {
    enteredEmail = email;
    enteredPassword = password;
    return _signIn('email');
  }

  @override
  Future<void> signUp(
    String email,
    String password, {
    String? name,
    String? phone,
    DateTime? birthDate,
  }) async {
    enteredEmail = email;
    enteredPassword = password;
    attempts.add('signup');
    await signupResult.future;
    userId = 'synthetic:signup';
  }

  @override
  Future<bool> signInWithGoogle() => _signIn('Google');

  @override
  Future<bool> signInWithKakao() => _signIn('카카오');

  @override
  Future<bool> signInWithNaver() => _signIn('네이버');
}

class _DelayedShopping extends MockShoppingRepository {
  final Completer<void> ready = Completer<void>();
  bool started = false;

  @override
  Future<ShoppingSnapshot> load(List<Product> products) async {
    started = true;
    await ready.future;
    return const ShoppingSnapshot(cart: [], wishedIds: {}, recentIds: []);
  }
}

class _DelayedOrders extends MockOrderRepository {
  final Completer<void> ready = Completer<void>();
  bool started = false;

  @override
  Future<List<StoreOrder>> getOrders() async {
    started = true;
    await ready.future;
    return [];
  }
}

class _Harness {
  _Harness({ShoppingRepository? shopping, OrderRepository? orders}) {
    store = StoreController(
      productsRepository: MockProductRepository(),
      accountRepository: account,
      orderRepository: orders ?? MockOrderRepository(),
      reviewRepository: MockReviewRepository(),
      shoppingRepository: shopping ?? MockShoppingRepository(),
      supportRepository: MockSupportRepository(),
    );
  }

  final account = _DelayedAccount();
  late final StoreController store;
  final List<String> messages = [];
  int done = 0;
  int back = 0;

  Future<void> show(
    WidgetTester tester, {
    String language = '한국어',
    Size size = const Size(800, 1100),
    double textScale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: brightness,
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        home: LocaleScope(
          language: language,
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: AuthScreen(
                store: store,
                onBack: () => back++,
                onDone: () => done++,
                onMessage: messages.add,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _expectLoading(
  WidgetTester tester, {
  String language = '한국어',
  String title = '로그인 중…',
  String description = '인증과 회원 정보를 확인하고 있어요.',
}) {
  expect(find.byType(CircularProgressIndicator), findsOneWidget);
  expect(find.text('SHUPICK'), findsOneWidget);
  expect(
    find.text(language == 'English' ? 'Signing in…' : title),
    findsOneWidget,
  );
  if (language != 'English') {
    expect(find.text(description), findsOneWidget);
  }
  expect(find.byType(Form), findsNothing);
  expect(find.byType(TextFormField), findsNothing);
  expect(find.byType(FilledButton), findsNothing);
  expect(find.byTooltip('카카오 로그인'), findsNothing);
  expect(find.byTooltip('네이버 로그인'), findsNothing);
  expect(find.byTooltip('Google 로그인'), findsNothing);
  expect(find.byIcon(Icons.arrow_back), findsNothing);
  final scopes = tester.widgetList<PopScope>(find.byType(PopScope));
  expect(scopes.any((scope) => !scope.canPop), isTrue);
  expect(tester.takeException(), isNull);
}

Future<void> _startSocial(WidgetTester tester, String provider) async {
  final button = find.byTooltip('$provider 로그인');
  if (button.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      button,
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
}

Future<void> _startEmail(WidgetTester tester) async {
  await tester.enterText(
    find.byType(TextFormField).at(0),
    'synthetic@example.com',
  );
  await tester.enterText(find.byType(TextFormField).at(1), 'Synthetic123');
  await tester.ensureVisible(find.byType(FilledButton));
  await tester.tap(find.byType(FilledButton));
  await tester.pump();
}

Future<void> _startSignup(
  WidgetTester tester, {
  bool pumpAfterSubmit = true,
}) async {
  await tester.tap(find.widgetWithText(TextButton, '회원가입'));
  await tester.pump();
  await tester.tap(find.widgetWithText(OutlinedButton, '이메일로 가입'));
  await tester.pump();
  await tester.enterText(
    find.widgetWithText(TextFormField, '이름'),
    'Synthetic member',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, '전화번호'),
    '01012345678',
  );
  final dropdowns = tester
      .widgetList<DropdownButtonFormField<int>>(
        find.byType(DropdownButtonFormField<int>),
      )
      .toList();
  dropdowns[0].onChanged!(2000);
  dropdowns[1].onChanged!(1);
  dropdowns[2].onChanged!(2);
  await tester.pump();
  await tester.enterText(
    find.widgetWithText(TextFormField, '이메일'),
    'synthetic@example.com',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, '비밀번호'),
    'Synthetic123',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, '비밀번호 확인'),
    'Synthetic123',
  );
  await tester.ensureVisible(find.byType(FilledButton));
  await tester.tap(find.byType(FilledButton));
  if (pumpAfterSubmit) await tester.pump();
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('login inputs use icons, hints and underlines in $brightness', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.show(tester, brightness: brightness);
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields.length, 2);
      expect(fields[0].decoration?.hintText, '이메일을 입력해주세요.');
      expect(fields[1].decoration?.hintText, '비밀번호를 입력해주세요.');
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(fields[0].keyboardType, TextInputType.emailAddress);
      expect(fields[0].obscureText, isFalse);
      expect(fields[1].obscureText, isTrue);
      for (final field in fields) {
        final decoration = field.decoration!;
        expect(decoration.labelText, isNull);
        expect(decoration.filled, isFalse);
        for (final border in [
          decoration.border,
          decoration.enabledBorder,
          decoration.disabledBorder,
          decoration.focusedBorder,
          decoration.errorBorder,
          decoration.focusedErrorBorder,
        ]) {
          expect(border, isA<UnderlineInputBorder>());
        }
      }
      await tester.tap(find.byType(TextFormField).first);
      await tester.pump();
      await tester.enterText(
        find.byType(TextFormField).first,
        'synthetic@example.com',
      );
      await tester.pump();
      final hint = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.text('이메일을 입력해주세요.'),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(hint.opacity, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('English login input hints are translated', (tester) async {
    final harness = _Harness();
    await harness.show(tester, language: 'English');
    expect(find.text('Please enter your email.'), findsOneWidget);
    expect(find.text('Please enter your password.'), findsOneWidget);
  });

  testWidgets('sign-up and reset keep their existing input layout', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.show(tester);
    await tester.tap(find.widgetWithText(TextButton, '회원가입'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, '이메일로 가입'));
    await tester.pump();
    final signupFields = tester.widgetList<TextField>(find.byType(TextField));
    expect(signupFields.length, 5);
    for (final field in signupFields) {
      expect(field.decoration?.border, isA<OutlineInputBorder>());
    }
    await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_back));
    await tester.pump();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_back));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '비밀번호를 잊으셨나요?'));
    await tester.pump();
    final reset = tester.widget<TextField>(find.byType(TextField));
    expect(reset.decoration?.labelText, '이메일');
    expect(reset.decoration?.border, isA<OutlineInputBorder>());
  });

  testWidgets(
    'social sign-in buttons show brand marks instead of bare letters',
    (tester) async {
      final harness = _Harness();
      await harness.show(tester);
      final marks = tester.widgetList<LoginProviderBadge>(
        find.byType(LoginProviderBadge),
      );
      expect(marks.map((mark) => mark.provider), [
        AccountLoginProvider.kakao,
        AccountLoginProvider.naver,
        AccountLoginProvider.google,
      ]);
      expect(marks.map((mark) => mark.size), everyElement(32));
      expect(find.text('K'), findsNothing);
      expect(find.text('k'), findsNothing);
      expect(find.text('G'), findsNothing);
      for (final label in ['카카오 로그인', '네이버 로그인', 'Google 로그인']) {
        expect(find.byTooltip(label), findsOneWidget);
        final button = tester.widget<IconButton>(
          find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == label,
          ),
        );
        expect(button.onPressed, isNotNull);
        expect(
          tester.getSize(find.byWidget(button)).width,
          greaterThanOrEqualTo(48),
        );
      }
      expect(harness.account.attempts, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final provider in ['카카오', '네이버', 'Google']) {
    testWidgets('$provider success stays on loading until navigation', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.show(tester);
      await _startSocial(tester, provider);
      _expectLoading(tester);
      expect(harness.account.attempts, [provider]);
      expect(harness.done, 0);

      // External authentication can return after several app-resume frames.
      await tester.pump(const Duration(seconds: 2));
      _expectLoading(tester);
      harness.account.result.complete(true);
      await tester.pump();
      expect(harness.done, 1);
      expect(harness.messages, isEmpty);
      _expectLoading(tester);
      await tester.pump(const Duration(milliseconds: 250));
      _expectLoading(tester);
      expect(harness.account.attempts, [provider]);
      expect(harness.back, 0);
    });

    testWidgets('$provider cancellation restores the form and reports it', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.show(tester);
      await _startSocial(tester, provider);
      _expectLoading(tester);
      harness.account.result.complete(false);
      await tester.pump();
      expect(find.byType(Form), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(harness.done, 0);
      expect(harness.messages, ['$provider 로그인을 취소했거나 완료하지 못했습니다.']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$provider authentication failure restores the form', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.show(tester);
      await _startSocial(tester, provider);
      harness.account.result.completeError(
        StateError('Synthetic authentication failure'),
      );
      await tester.pump();
      expect(find.byType(Form), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(harness.done, 0);
      expect(harness.messages, ['Synthetic authentication failure']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$provider disposed screen ignores a late success', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.show(tester);
      await _startSocial(tester, provider);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      harness.account.result.complete(true);
      await tester.pump();
      expect(harness.done, 0);
      expect(harness.messages, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('loading covers account, local shopping, and server orders', (
    tester,
  ) async {
    final shopping = _DelayedShopping();
    final orders = _DelayedOrders();
    final harness = _Harness(shopping: shopping, orders: orders);
    await harness.show(tester);
    await _startSocial(tester, '네이버');
    _expectLoading(tester);

    harness.account.result.complete(true);
    await tester.pump();
    expect(shopping.started, isTrue);
    expect(orders.started, isFalse);
    expect(harness.done, 0);
    _expectLoading(tester);

    shopping.ready.complete();
    await tester.pump();
    expect(orders.started, isTrue);
    expect(harness.done, 0);
    _expectLoading(tester);

    orders.ready.complete();
    await tester.pump();
    expect(harness.done, 1);
    _expectLoading(tester);
  });

  testWidgets('unexpected social error returns to the form safely', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.show(tester);
    await _startSocial(tester, 'Google');
    harness.account.result.completeError(
      Exception('Synthetic transport error'),
    );
    await tester.pump();
    expect(find.byType(Form), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(harness.done, 0);
    expect(harness.messages, ['Google 로그인을 완료하지 못했습니다. 다시 시도해주세요.']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('email success uses the same dedicated loading screen', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.show(tester);
    await _startEmail(tester);
    expect(harness.account.enteredEmail, 'synthetic@example.com');
    expect(harness.account.enteredPassword, 'Synthetic123');
    _expectLoading(tester);
    harness.account.result.complete(true);
    await tester.pump();
    expect(harness.done, 1);
    expect(harness.messages, isEmpty);
    _expectLoading(tester);
  });

  testWidgets('invalid email login restores entered credentials for retry', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.show(tester);
    await _startEmail(tester);
    _expectLoading(tester);
    harness.account.result.complete(false);
    await tester.pump();
    expect(find.byType(Form), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(harness.done, 0);
    expect(harness.messages, ['이메일 또는 비밀번호가 올바르지 않습니다.']);
    final inputs = tester.widgetList<TextFormField>(find.byType(TextFormField));
    expect(inputs.first.controller!.text, 'synthetic@example.com');
    expect(inputs.last.controller!.text, 'Synthetic123');
    expect(tester.takeException(), isNull);
  });

  testWidgets('email authentication failure restores the form', (tester) async {
    final harness = _Harness();
    await harness.show(tester);
    await _startEmail(tester);
    harness.account.result.completeError(StateError('Synthetic email failure'));
    await tester.pump();
    expect(find.byType(Form), findsOneWidget);
    expect(harness.done, 0);
    expect(harness.messages, ['Synthetic email failure']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unexpected email error returns to the form safely', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.show(tester);
    await _startEmail(tester);
    harness.account.result.completeError(
      Exception('Synthetic transport error'),
    );
    await tester.pump();
    expect(find.byType(Form), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(harness.done, 0);
    expect(harness.messages, ['로그인을 완료하지 못했습니다. 다시 시도해주세요.']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('email disposed screen ignores late completion', (tester) async {
    final harness = _Harness();
    await harness.show(tester);
    await _startEmail(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    harness.account.result.complete(true);
    await tester.pump();
    expect(harness.done, 0);
    expect(harness.messages, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final provider in ['email', '네이버']) {
    testWidgets('$provider disposed screen ignores a late error', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.show(tester);
      if (provider == 'email') {
        await _startEmail(tester);
      } else {
        await _startSocial(tester, provider);
      }
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      harness.account.result.completeError(
        StateError('Synthetic late authentication failure'),
      );
      await tester.pump();
      expect(harness.done, 0);
      expect(harness.messages, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('email signup completion restores an empty login password', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.show(tester);
    await _startSignup(tester);
    _expectLoading(tester, title: '회원가입 중…', description: '잠시만 기다려주세요.');
    expect(harness.account.attempts, ['signup']);
    expect(harness.account.enteredEmail, 'synthetic@example.com');
    expect(harness.account.enteredPassword, 'Synthetic123');

    harness.account.signupResult.complete();
    await tester.pump();
    expect(find.byType(Form), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final inputs = tester.widgetList<TextFormField>(find.byType(TextFormField));
    expect(inputs.length, 2);
    expect(inputs.first.controller!.text, 'synthetic@example.com');
    expect(inputs.last.controller!.text, isEmpty);
    expect(find.widgetWithText(FilledButton, '로그인'), findsOneWidget);
    expect(harness.done, 0);
    expect(harness.messages, ['회원가입이 완료되었습니다. 입력한 계정으로 로그인해주세요.']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('email signup failure restores its original form', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.show(tester);
    await _startSignup(tester);
    harness.account.signupResult.completeError(
      StateError('Synthetic signup failure'),
    );
    await tester.pump();
    expect(find.byType(Form), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(5));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.widgetWithText(FilledButton, '가입하기'), findsOneWidget);
    expect(harness.done, 0);
    expect(harness.messages, ['Synthetic signup failure']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('instant signup completion does not reset the retained email', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.show(tester);
    harness.account.signupResult.complete();
    await _startSignup(tester, pumpAfterSubmit: false);
    await tester.pump();
    expect(find.byType(TextFormField), findsNWidgets(2));
    final inputs = tester.widgetList<TextFormField>(find.byType(TextFormField));
    expect(inputs.first.controller!.text, 'synthetic@example.com');
    expect(inputs.last.controller!.text, isEmpty);
    expect(find.widgetWithText(FilledButton, '로그인'), findsOneWidget);
    expect(harness.messages, ['회원가입이 완료되었습니다. 입력한 계정으로 로그인해주세요.']);
    expect(tester.takeException(), isNull);

    // Reopening sign-up also confirms the hidden confirmation was cleared.
    await tester.tap(find.widgetWithText(TextButton, '회원가입'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, '이메일로 가입'));
    await tester.pump();
    final signupInputs = tester.widgetList<TextFormField>(
      find.byType(TextFormField),
    );
    expect(signupInputs.elementAt(3).controller!.text, isEmpty);
    expect(signupInputs.elementAt(4).controller!.text, isEmpty);
  });

  testWidgets('queued duplicate login and back taps are ignored while busy', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.show(tester);
    final backButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_back),
    );
    final naverButton = tester.widget<IconButton>(
      find.ancestor(of: find.text('N'), matching: find.byType(IconButton)),
    );
    naverButton.onPressed!();
    naverButton.onPressed!();
    backButton.onPressed!();
    await tester.pump();
    expect(harness.account.attempts, ['네이버']);
    expect(harness.back, 0);
    _expectLoading(tester);
    harness.account.result.complete(false);
    await tester.pump();
    expect(find.byType(Form), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final fails in [false, true]) {
    testWidgets('disposed signup ignores late ${fails ? 'error' : 'success'}', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.show(tester);
      await _startSignup(tester);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      if (fails) {
        harness.account.signupResult.completeError(
          StateError('Synthetic late signup failure'),
        );
      } else {
        harness.account.signupResult.complete();
      }
      await tester.pump();
      expect(harness.done, 0);
      expect(harness.messages, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('invalid fields never enter loading or begin authentication', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.show(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(find.byType(Form), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(harness.account.attempts, isEmpty);
    expect(harness.messages, isEmpty);
  });

  testWidgets('English users see translated loading copy', (tester) async {
    final harness = _Harness();
    await harness.show(tester, language: 'English');
    await _startSocial(tester, 'Google');
    _expectLoading(tester, language: 'English');
    expect(find.text('로그인 중…'), findsNothing);
    expect(find.text('인증과 회원 정보를 확인하고 있어요.'), findsNothing);
    harness.account.result.complete(false);
    await tester.pump();
    expect(find.byType(Form), findsOneWidget);
  });

  testWidgets('loading fits a small screen with large accessibility text', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.show(tester, size: const Size(320, 640), textScale: 2);
    await _startSocial(tester, '네이버');
    _expectLoading(tester);
    harness.account.result.complete(false);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
