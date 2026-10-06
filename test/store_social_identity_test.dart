import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/app/store_controller.dart';
import 'package:shupick/data/mock_repositories.dart';
import 'package:shupick/domain/models.dart';
import 'package:shupick/domain/repositories.dart';

class _Account extends MockAccountRepository
    implements
        SessionAccountRepository,
        IdentityAccountRepository,
        SocialAccountRepository {
  _Account({this.userId, this.email});

  @override
  String? userId;
  @override
  String? email;
  String? nextUid = 'kakao:next-subject';
  bool cancel = false;
  bool connectionFails = false;
  int restores = 0;
  int logouts = 0;

  @override
  String? get displayName => userId == null ? null : '소셜 회원';

  @override
  Future<bool> restoreSession() async {
    restores++;
    if (connectionFails) throw StateError('Synthetic MySQL profile failure');
    return userId != null;
  }

  @override
  Future<bool> signInWithKakao() async {
    if (cancel) return false;
    userId = nextUid;
    return true;
  }

  @override
  Future<bool> signInWithNaver() => signInWithKakao();

  @override
  Future<void> signOut() async {
    logouts++;
    userId = null;
    email = null;
  }
}

class _Orders extends MockOrderRepository implements AccountBenefitsRepository {
  _Orders(this.account);
  final _Account account;
  final List<String?> identities = [];
  int benefitsCalls = 0;

  @override
  Future<List<StoreOrder>> getOrders() async {
    identities.add(account.userId);
    if (account.userId == null) return [];
    return [
      StoreOrder(
        number: 'order-${account.userId}',
        items: const [],
        date: DateTime(2026),
        district: '성동구',
      ),
    ];
  }

  @override
  Future<Map<String, dynamic>> getAccountBenefits() async {
    benefitsCalls++;
    return {'identity': account.userId};
  }

  @override
  Future<void> confirmOrder(int orderId) async {}
}

class _Reviews extends MockReviewRepository {
  _Reviews(this.account);
  final _Account account;

  @override
  Future<List<ProductReview>> getReviews() async => account.userId == null
      ? []
      : [
          ProductReview(
            orderNumber: 'order-${account.userId}',
            itemKey: 'item-1',
            rating: 5,
            content: 'review-${account.userId}',
          ),
        ];
}

class _Support extends MockSupportRepository {
  _Support(this.account);
  final _Account account;

  @override
  Future<List<InquiryEntry>> getInquiries() async => account.userId == null
      ? []
      : [
          InquiryEntry(
            id: 1,
            kind: '상품 문의',
            title: 'inquiry-${account.userId}',
            body: 'synthetic-private-inquiry',
            date: '2026.10.06',
          ),
        ];

  @override
  Future<Set<String>> getRestockKeys() async =>
      account.userId == null ? {} : {'restock-${account.userId}'};
}

void main() {
  StoreController create(_Account account, _Orders orders) => StoreController(
    productsRepository: MockProductRepository(),
    accountRepository: account,
    orderRepository: orders,
    reviewRepository: _Reviews(account),
    shoppingRepository: MockShoppingRepository(),
    supportRepository: _Support(account),
  );

  test(
    'email-less UID session restores login and loads UID-owned private data',
    () async {
      final account = _Account(userId: 'kakao:synthetic-subject');
      final orders = _Orders(account);
      final store = create(account, orders);
      addTearDown(store.dispose);

      await store.load();
      expect(account.restores, 1);
      expect(store.isLoggedIn, isTrue);
      expect(store.userId, account.userId);
      expect(store.userEmail, isNull);
      expect(store.accountIdentityKey, account.userId);
      expect(store.accountConnectionError, isNull);
      expect(store.orders.single.number, 'order-${account.userId}');
      expect(store.reviews.single.content, 'review-${account.userId}');
      expect(store.inquiries.single.title, 'inquiry-${account.userId}');
      expect(store.restockKeys, {'restock-${account.userId}'});
      expect(store.accountBenefits, {'identity': account.userId});
    },
  );

  for (final provider in ['kakao', 'naver']) {
    test('$provider login uses UID even without an email', () async {
      final account = _Account()..nextUid = '$provider:synthetic-subject';
      final orders = _Orders(account);
      final store = create(account, orders);
      addTearDown(store.dispose);

      final success = provider == 'kakao'
          ? await store.signInWithKakao()
          : await store.signInWithNaver();
      expect(success, isTrue);
      expect(store.isLoggedIn, isTrue);
      expect(store.userEmail, isNull);
      expect(store.userId, account.nextUid);
      expect(store.accountIdentityKey, account.nextUid);
      expect(orders.identities, [account.nextUid]);
      expect(orders.benefitsCalls, 1);
    });
  }

  test(
    'two accounts sharing a contact email have distinct UID cache identities',
    () async {
      final account = _Account(
        userId: 'kakao:first',
        email: 'shared@example.com',
      )..nextUid = 'naver:second';
      final orders = _Orders(account);
      final store = create(account, orders);
      addTearDown(store.dispose);
      await store.load();
      final firstIdentity = store.accountIdentityKey;

      expect(await store.signInWithNaver(), isTrue);
      expect(store.userEmail, 'shared@example.com');
      expect(firstIdentity, 'kakao:first');
      expect(store.accountIdentityKey, 'naver:second');
      expect(store.accountIdentityKey, isNot(firstIdentity));
      expect(store.orders.single.number, 'order-naver:second');
      expect(store.reviews.single.content, 'review-naver:second');
      expect(store.inquiries.single.title, 'inquiry-naver:second');
      expect(store.restockKeys, {'restock-naver:second'});
      expect(store.accountBenefits, {'identity': 'naver:second'});
    },
  );

  test(
    'cancellation leaves the current UID and private cache unchanged',
    () async {
      final account = _Account(userId: 'kakao:existing')..cancel = true;
      final orders = _Orders(account);
      final store = create(account, orders);
      addTearDown(store.dispose);
      await store.load();
      final cachedOrder = store.orders.single;
      final cachedReview = store.reviews.single;
      final cachedInquiry = store.inquiries.single;
      final calls = orders.identities.length;

      expect(await store.signInWithNaver(), isFalse);
      expect(store.isLoggedIn, isTrue);
      expect(store.accountIdentityKey, 'kakao:existing');
      expect(store.orders.single, same(cachedOrder));
      expect(store.reviews.single, same(cachedReview));
      expect(store.inquiries.single, same(cachedInquiry));
      expect(orders.identities, hasLength(calls));
    },
  );

  test('logout clears UID, session, and member-only private cache', () async {
    final account = _Account(userId: 'naver:synthetic-subject');
    final store = create(account, _Orders(account));
    addTearDown(store.dispose);
    await store.load();
    expect(store.orders, isNotEmpty);
    expect(store.reviews, isNotEmpty);
    expect(store.inquiries, isNotEmpty);
    expect(store.accountBenefits, isNotNull);

    await store.signOut();
    expect(account.logouts, 1);
    expect(store.isLoggedIn, isFalse);
    expect(store.userId, isNull);
    expect(store.userName, isNull);
    expect(store.userEmail, isNull);
    expect(store.accountIdentityKey, isNull);
    expect(store.orders, isEmpty);
    expect(store.reviews, isEmpty);
    expect(store.inquiries, isEmpty);
    expect(store.restockKeys, isEmpty);
    expect(store.accountBenefits, isNull);
    expect(store.products, isNotEmpty);
    expect(store.accountConnectionError, isNull);
  });

  test(
    'failed email-less session connection preserves logout identity but blocks private queries',
    () async {
      final account = _Account(userId: 'naver:synthetic-subject')
        ..connectionFails = true;
      final orders = _Orders(account);
      final store = create(account, orders);
      addTearDown(store.dispose);

      await store.load();
      expect(store.isLoggedIn, isTrue);
      expect(store.userId, account.userId);
      expect(store.accountIdentityKey, account.userId);
      expect(store.accountConnectionError, isNotNull);
      expect(store.products, hasLength(72));
      expect(store.loadError, isNull);
      expect(orders.identities, isEmpty);
      expect(store.orders, isEmpty);
      expect(store.reviews, isEmpty);
      expect(store.inquiries, isEmpty);
      expect(store.accountBenefits, isNull);

      account.connectionFails = false;
      await store.load();
      expect(store.accountConnectionError, isNull);
      expect(orders.identities, [account.userId]);
      expect(store.orders, isNotEmpty);
    },
  );

  test(
    'email alone cannot mark an identity-aware repository as logged in',
    () async {
      final account = _Account(email: 'contact-only@example.com');
      final store = create(account, _Orders(account));
      addTearDown(store.dispose);

      await store.load();
      expect(store.userId, isNull);
      expect(store.isLoggedIn, isFalse);
      expect(store.orders, isEmpty);
      expect(store.accountBenefits, isNull);
    },
  );
}
