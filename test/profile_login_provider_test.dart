import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/app/store_controller.dart';
import 'package:shupick/data/mock_repositories.dart';
import 'package:shupick/domain/repositories.dart';
import 'package:shupick/presentation/localization.dart';
import 'package:shupick/presentation/screens/account_screens.dart';
import 'package:shupick/presentation/shared/login_provider_badge.dart';

class _Account extends MockAccountRepository
    implements
        SessionAccountRepository,
        IdentityAccountRepository,
        LoginProviderAccountRepository,
        SocialAccountRepository {
  _Account({
    this.userId,
    this.loginProvider,
    this.accountEmail = 'same-contact@example.com',
    this.accountName = '같은 표시 이름',
  });

  final String? accountEmail;
  final String? accountName;

  @override
  String? userId;
  @override
  AccountLoginProvider? loginProvider;
  bool cancel = false;
  bool connectionFails = false;

  @override
  String? get displayName => userId == null ? null : accountName;
  @override
  String? get email => userId == null ? null : accountEmail;

  @override
  Future<bool> restoreSession() async {
    if (connectionFails) throw StateError('Synthetic profile connection error');
    return userId != null;
  }

  Future<bool> _login(AccountLoginProvider value) async {
    if (cancel) return false;
    userId = '${value.name}:synthetic-user';
    loginProvider = value;
    if (connectionFails) throw StateError('Synthetic profile connection error');
    return true;
  }

  @override
  Future<bool> signIn(String email, String password) =>
      _login(AccountLoginProvider.email);
  @override
  Future<bool> signInWithGoogle() => _login(AccountLoginProvider.google);
  @override
  Future<bool> signInWithKakao() => _login(AccountLoginProvider.kakao);
  @override
  Future<bool> signInWithNaver() => _login(AccountLoginProvider.naver);

  @override
  Future<void> signOut() async {
    userId = null;
    loginProvider = null;
  }
}

StoreController _store(AccountRepository account) => StoreController(
  productsRepository: MockProductRepository(),
  accountRepository: account,
  orderRepository: MockOrderRepository(),
  reviewRepository: MockReviewRepository(),
  shoppingRepository: MockShoppingRepository(),
  supportRepository: MockSupportRepository(),
);

Future<void> _showProfile(
  WidgetTester tester,
  StoreController store, {
  double textScale = 1,
  String language = '한국어',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: LocaleScope(
          language: language,
          child: Scaffold(
            body: ProfileScreen(store: store, onGo: (_) {}, onLogout: () {}),
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final provider in AccountLoginProvider.values) {
    test(
      'controller restores the current $provider authentication source',
      () async {
        final store = _store(
          _Account(
            userId: '${provider.name}:same-user',
            loginProvider: provider,
          ),
        );
        addTearDown(store.dispose);
        await store.load();
        expect(store.loginProvider, provider);
        expect(store.userName, '같은 표시 이름');
        expect(store.userEmail, 'same-contact@example.com');
      },
    );
  }

  test(
    'account switch and logout replace the provider without editing names',
    () async {
      final store = _store(_Account());
      addTearDown(store.dispose);
      expect(await store.signInWithKakao(), isTrue);
      expect(store.loginProvider, AccountLoginProvider.kakao);
      expect(await store.signInWithNaver(), isTrue);
      expect(store.loginProvider, AccountLoginProvider.naver);
      expect(await store.signInWithGoogle(), isTrue);
      expect(store.loginProvider, AccountLoginProvider.google);
      expect(
        await store.signIn('same-contact@example.com', 'synthetic'),
        isTrue,
      );
      expect(store.loginProvider, AccountLoginProvider.email);
      expect(store.userName, '같은 표시 이름');
      await store.signOut();
      expect(store.loginProvider, isNull);
      expect(store.isLoggedIn, isFalse);
    },
  );

  test('cancelled provider login keeps the actual account badge', () async {
    final account = _Account(
      userId: 'kakao:existing',
      loginProvider: AccountLoginProvider.kakao,
    )..cancel = true;
    final store = _store(account);
    addTearDown(store.dispose);
    await store.load();
    expect(await store.signInWithNaver(), isFalse);
    expect(store.loginProvider, AccountLoginProvider.kakao);
    expect(store.userId, 'kakao:existing');
  });

  test(
    'profile connection failure still reflects the new authenticated UID',
    () async {
      final account = _Account(
        userId: 'google:existing',
        loginProvider: AccountLoginProvider.google,
      );
      final store = _store(account);
      addTearDown(store.dispose);
      await store.load();
      account.connectionFails = true;
      await expectLater(store.signInWithNaver(), throwsStateError);
      expect(store.loginProvider, AccountLoginProvider.naver);
      expect(store.userId, 'naver:synthetic-user');
      expect(store.accountConnectionError, isNotNull);
    },
  );

  test(
    'repositories without authentication metadata do not invent a badge',
    () async {
      final store = _store(MockAccountRepository());
      addTearDown(store.dispose);
      expect(await store.signInWithGoogle(), isTrue);
      expect(store.loginProvider, isNull);
    },
  );

  for (final provider in AccountLoginProvider.values) {
    testWidgets('profile shows only the current $provider badge', (
      tester,
    ) async {
      final store = _store(
        _Account(userId: '${provider.name}:user', loginProvider: provider),
      );
      addTearDown(store.dispose);
      await store.load();
      await _showProfile(tester, store);
      final title = provider == AccountLoginProvider.email
          ? 'same-contact 님'
          : '같은 표시 이름 님';
      expect(find.text(title), findsOneWidget);
      if (provider == AccountLoginProvider.email) {
        expect(find.byType(LoginProviderBadge), findsNothing);
      } else {
        expect(find.byType(LoginProviderBadge), findsOneWidget);
        expect(
          tester
              .widget<LoginProviderBadge>(find.byType(LoginProviderBadge))
              .provider,
          provider,
        );
        final nameRect = tester.getRect(find.text('같은 표시 이름 님'));
        final badgeRect = tester.getRect(find.byType(LoginProviderBadge));
        expect(badgeRect.left, greaterThanOrEqualTo(nameRect.right));
        expect(badgeRect.center.dy, closeTo(nameRect.center.dy, 1));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'email session displays the local part without changing identity',
    (tester) async {
      final store = _store(
        _Account(
          userId: 'synthetic-existing-email-user',
          loginProvider: AccountLoginProvider.email,
          accountEmail: 'shupicktest01@example.com',
          accountName: null,
        ),
      );
      addTearDown(store.dispose);
      await store.load();
      await _showProfile(tester, store);
      expect(find.text('shupicktest01 님'), findsOneWidget);
      expect(find.text('사용자 님'), findsNothing);
      expect(find.byType(LoginProviderBadge), findsNothing);
      expect(store.userName, isNull);
      expect(store.userEmail, 'shupicktest01@example.com');
      expect(store.userId, 'synthetic-existing-email-user');
      expect(store.accountIdentityKey, 'synthetic-existing-email-user');
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'email login and switching providers recompute only the profile label',
    () async {
      final store = _store(_Account());
      addTearDown(store.dispose);
      expect(
        await store.signIn('same-contact@example.com', 'synthetic'),
        isTrue,
      );
      expect(store.profileDisplayName, 'same-contact');
      expect(store.userName, '같은 표시 이름');
      expect(await store.signInWithNaver(), isTrue);
      expect(store.profileDisplayName, '같은 표시 이름');
      expect(
        await store.signIn('same-contact@example.com', 'synthetic'),
        isTrue,
      );
      expect(store.profileDisplayName, 'same-contact');
      await store.signOut();
      expect(store.profileDisplayName, isNull);
    },
  );

  for (final address in <String?>[
    null,
    '',
    '   ',
    'without-separator',
    '@example.com',
    'local-only@',
  ]) {
    test('email label with unusable address $address preserves the name', () {
      final store = _store(_Account())
        ..isLoggedIn = true
        ..loginProvider = AccountLoginProvider.email
        ..userEmail = address
        ..userName = 'Existing name';
      addTearDown(store.dispose);
      expect(store.profileDisplayName, 'Existing name');
    });
  }

  test(
    'email label trims outer whitespace and preserves the full local part',
    () {
      final store = _store(_Account())
        ..isLoggedIn = true
        ..loginProvider = AccountLoginProvider.email
        ..userEmail = '  Alice.test+shop@example.com  ';
      addTearDown(store.dispose);
      expect(store.profileDisplayName, 'Alice.test+shop');
      expect(store.userEmail, '  Alice.test+shop@example.com  ');
    },
  );

  test(
    'unknown authentication method never infers email login from an address',
    () {
      final store = _store(_Account())
        ..isLoggedIn = true
        ..userEmail = 'contact@example.com'
        ..userName = 'Original profile name';
      addTearDown(store.dispose);
      expect(store.profileDisplayName, 'Original profile name');
    },
  );

  test('guest never uses a lingering email provider or email as its label', () {
    final store = _store(_Account())
      ..loginProvider = AccountLoginProvider.email
      ..userEmail = 'previous@example.com';
    addTearDown(store.dispose);
    expect(store.profileDisplayName, isNull);
  });

  testWidgets('guest profile does not show a lingering provider badge', (
    tester,
  ) async {
    final store = _store(_Account());
    addTearDown(store.dispose);
    store.loginProvider = AccountLoginProvider.naver;
    await _showProfile(tester, store);
    expect(find.byType(LoginProviderBadge), findsNothing);
    expect(find.text('비회원으로 상품을 둘러보고 있어요.'), findsOneWidget);
  });

  testWidgets('benefits card has a title instead of name initials', (
    tester,
  ) async {
    final store = _store(_Account())
      ..isLoggedIn = true
      ..userName = '네이버 회원'
      ..loginProvider = AccountLoginProvider.naver;
    addTearDown(store.dispose);
    await _showProfile(tester, store);
    expect(find.text('네이버 회원 님'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('membership-benefits')),
        matching: find.text('회원 혜택'),
      ),
      findsOneWidget,
    );
    expect(find.text('네회'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('membership benefits card title has an English translation', (
    tester,
  ) async {
    final store = _store(_Account())
      ..isLoggedIn = true
      ..userName = 'Consented nickname'
      ..loginProvider = AccountLoginProvider.naver;
    addTearDown(store.dispose);
    await _showProfile(tester, store, language: 'English');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('membership-benefits')),
        matching: find.text('Membership benefits'),
      ),
      findsOneWidget,
    );
    expect(find.text('CN'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long name and large text keep the badge visible without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = _store(_Account())
        ..isLoggedIn = true
        ..userName = List.filled(100, '긴').join()
        ..loginProvider = AccountLoginProvider.naver;
      addTearDown(store.dispose);
      await _showProfile(tester, store, textScale: 1.5);
      expect(tester.takeException(), isNull);
      expect(find.byType(LoginProviderBadge), findsOneWidget);
      expect(
        tester.getSize(find.byType(LoginProviderBadge)),
        const Size(24, 24),
      );
      expect(
        tester.getRect(find.byType(LoginProviderBadge)).right,
        lessThanOrEqualTo(360 - 20),
      );
    },
  );
}
