import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/app/store_controller.dart';
import 'package:shupick/data/mock_repositories.dart';
import 'package:shupick/domain/models.dart';
import 'package:shupick/domain/repositories.dart';

const _first = Product(
  id: 101,
  name: 'First shoe',
  category: '운동화',
  price: 10000,
  imageUrl: '',
  color: '블랙',
  gender: '공용',
);
const _second = Product(
  id: 202,
  name: 'Second shoe',
  category: '운동화',
  price: 20000,
  imageUrl: '',
  color: '화이트',
  gender: '공용',
);
const _third = Product(
  id: 303,
  name: 'Third shoe',
  category: '운동화',
  price: 30000,
  imageUrl: '',
  color: '블루',
  gender: '공용',
);
const _empty = ShoppingSnapshot(cart: [], wishedIds: {}, recentIds: []);

ShoppingSnapshot _copy(ShoppingSnapshot snapshot) => ShoppingSnapshot(
  cart: List.of(snapshot.cart),
  wishedIds: Set.of(snapshot.wishedIds),
  recentIds: List.of(snapshot.recentIds),
);

ShoppingSnapshot _snapshot(Product product) => ShoppingSnapshot(
  cart: [CartItem(product: product, size: '260', color: product.color)],
  wishedIds: {product.id},
  recentIds: [product.id],
);

enum _LoginResult { success, canceled, rejected, syncFailed }

class _Account
    implements
        AccountRepository,
        SessionAccountRepository,
        IdentityAccountRepository,
        SocialAccountRepository {
  _Account({this.userId, this.email});

  @override
  String? userId;
  @override
  String? email;
  @override
  String? get displayName => userId == null ? null : 'User $userId';

  String? nextUserId;
  String? nextEmail;
  _LoginResult result = _LoginResult.success;
  Completer<void>? loginGate;
  Completer<void>? loginStarted;
  int restores = 0;
  bool failAfterSignOut = false;

  void next(String uid, {String? email}) {
    nextUserId = uid;
    nextEmail = email;
    result = _LoginResult.success;
  }

  Future<bool> _login() async {
    loginStarted?.complete();
    final gate = loginGate;
    loginGate = null;
    if (gate != null) await gate.future;
    if (result == _LoginResult.canceled) return false;
    if (result == _LoginResult.rejected) {
      throw StateError('Authentication failed before changing identity');
    }
    userId = nextUserId;
    email = nextEmail;
    if (result == _LoginResult.syncFailed) {
      throw StateError('Firebase succeeded but MySQL customer sync failed');
    }
    return true;
  }

  @override
  Future<bool> restoreSession() async {
    restores++;
    return userId != null;
  }

  @override
  Future<bool> signIn(String email, String password) => _login();
  @override
  Future<bool> signInWithGoogle() => _login();
  @override
  Future<bool> signInWithKakao() => _login();
  @override
  Future<bool> signInWithNaver() => _login();
  @override
  Future<void> signUp(String email, String password) async {
    await _login();
  }

  @override
  Future<void> signOut() async {
    userId = null;
    email = null;
    if (failAfterSignOut) throw StateError('Social sign-out cleanup failed');
  }
}

class _HeldLoad {
  final started = Completer<void>();
  final result = Completer<ShoppingSnapshot>();
}

class _HeldRead<T> {
  final started = Completer<void>();
  final result = Completer<T>();
  Future<T> read() {
    started.complete();
    return result.future;
  }
}

class _Save {
  _Save(this.owner, this.snapshot);
  final String? owner;
  final ShoppingSnapshot snapshot;
}

/// Each asynchronous operation captures its owner at invocation, like SQLite.
class _Shopping implements ShoppingRepository, AccountScopedShoppingRepository {
  String? selected;
  final selections = <String?>[];
  final snapshots = <String?, ShoppingSnapshot>{};
  final saves = <_Save>[];
  final heldLoads = <String?, List<_HeldLoad>>{};
  final failedOwners = <String?>{};

  _HeldLoad holdNextLoad(String? owner) {
    final held = _HeldLoad();
    heldLoads.putIfAbsent(owner, () => []).add(held);
    return held;
  }

  @override
  void selectAccount(String? userId) {
    selected = userId;
    selections.add(userId);
  }

  @override
  Future<ShoppingSnapshot> load(List<Product> products) async {
    final owner = selected;
    final queue = heldLoads[owner];
    if (queue != null && queue.isNotEmpty) {
      final held = queue.removeAt(0);
      held.started.complete();
      return _copy(await held.result.future);
    }
    if (failedOwners.contains(owner)) throw StateError('Local load failed');
    return _copy(snapshots[owner] ?? _empty);
  }

  @override
  Future<void> save(ShoppingSnapshot snapshot) async {
    final owner = selected;
    final captured = _copy(snapshot);
    saves.add(_Save(owner, captured));
    snapshots[owner] = captured;
  }
}

class _Products implements ProductRepository {
  @override
  Future<List<Product>> getProducts() async => [_first, _second, _third];
  @override
  Future<List<ProductOption>> getProductOptions(int productId) async => [];
}

class _Orders extends MockOrderRepository implements AccountBenefitsRepository {
  Completer<StoreOrder>? createGate;
  int creates = 0;
  List<StoreOrder> records = [];
  Map<String, dynamic> benefits = {};
  _HeldRead<List<StoreOrder>>? nextRead;
  _HeldRead<Map<String, dynamic>>? nextBenefitsRead;
  @override
  Future<List<StoreOrder>> getOrders() async {
    final held = nextRead;
    nextRead = null;
    return held == null ? List.of(records) : held.read();
  }

  @override
  Future<Map<String, dynamic>> getAccountBenefits() async {
    final held = nextBenefitsRead;
    nextBenefitsRead = null;
    return held == null ? Map.of(benefits) : held.read();
  }

  @override
  Future<void> confirmOrder(int orderId) async {}

  @override
  Future<StoreOrder> createOrder(
    List<CartItem> items,
    String district, {
    required int paidTotal,
    required int couponDiscount,
    required int pointsUsed,
    required String paymentMethod,
    int? customerCouponId,
  }) async {
    creates++;
    final gate = createGate;
    if (gate != null) return gate.future;
    return StoreOrder(
      number: 'test-order-$creates',
      items: List.of(items),
      date: DateTime(2026, 10, 6),
      district: district,
    );
  }
}

class _Reviews extends MockReviewRepository {
  List<ProductReview> records = [];
  _HeldRead<List<ProductReview>>? nextRead;
  int reads = 0;
  @override
  Future<List<ProductReview>> getReviews() async {
    reads++;
    final held = nextRead;
    nextRead = null;
    return held == null ? List.of(records) : held.read();
  }
}

class _Support extends MockSupportRepository {
  List<InquiryEntry> records = [];
  Set<String> keys = {};
  _HeldRead<List<InquiryEntry>>? nextRead;
  int reads = 0;
  int keyReads = 0;
  @override
  Future<List<InquiryEntry>> getInquiries() async {
    reads++;
    final held = nextRead;
    nextRead = null;
    return held == null ? List.of(records) : held.read();
  }

  @override
  Future<Set<String>> getRestockKeys() async {
    keyReads++;
    return Set.of(keys);
  }
}

StoreOrder _order(String owner) => StoreOrder(
  number: '$owner-order',
  items: _snapshot(owner == 'a' ? _first : _second).cart,
  date: DateTime(2026, 10, 6),
  district: '성동구',
);

ProductReview _review(String owner) => ProductReview(
  orderNumber: '$owner-order',
  itemKey: '$owner-item',
  rating: 5,
  content: '$owner-review',
);

InquiryEntry _inquiry(String owner) => InquiryEntry(
  id: owner == 'a' ? 1 : 2,
  kind: '상품 문의',
  title: '$owner-inquiry',
  body: '$owner-body',
  date: '2026.10.06',
);

StoreController _store(
  _Account account,
  _Shopping shopping, {
  _Orders? orders,
  ReviewRepository? reviews,
  SupportRepository? support,
}) {
  final store = StoreController(
    productsRepository: _Products(),
    accountRepository: account,
    orderRepository: orders ?? _Orders(),
    reviewRepository: reviews ?? MockReviewRepository(),
    shoppingRepository: shopping,
    supportRepository: support ?? MockSupportRepository(),
  );
  addTearDown(store.dispose);
  return store;
}

void _expectShopping(StoreController store, Product product) {
  expect(store.cart.map((item) => item.product.id), [product.id]);
  expect(store.wishedIds, {product.id});
  expect(store.recentIds, [product.id]);
}

void _expectEmpty(StoreController store) {
  expect(store.cart, isEmpty);
  expect(store.wishedIds, isEmpty);
  expect(store.recentIds, isEmpty);
}

Future<void> _settleSaves() async {
  await Future<void>.delayed(Duration.zero);
}

Future<bool> _login(StoreController store, String provider) =>
    switch (provider) {
      'google' => store.signInWithGoogle(),
      'kakao' => store.signInWithKakao(),
      'naver' => store.signInWithNaver(),
      _ => store.signIn('entered@example.com', 'unused-test-password'),
    };

void main() {
  test('A의 쇼핑 기록은 B에게 보이지 않고 A 재로그인 시 복원된다', () async {
    final account = _Account();
    final shopping = _Shopping();
    final store = _store(account, shopping);
    await store.load();
    account.next('uid-a', email: 'a@example.com');
    expect(await _login(store, 'email'), isTrue);
    store.addToCart(_first, '260', _first.color);
    store.toggleWish(_first);
    store.view(_first);
    await _settleSaves();
    _expectShopping(store, _first);
    expect(shopping.snapshots['uid-a']!.cart.single.product.id, _first.id);

    await store.signOut();
    _expectEmpty(store);
    account.next('uid-b', email: 'b@example.com');
    expect(await _login(store, 'email'), isTrue);
    expect(shopping.selected, 'uid-b');
    _expectEmpty(store);
    store.addToCart(_second, '260', _second.color);
    store.toggleWish(_second);
    store.view(_second);
    await _settleSaves();

    await store.signOut();
    account.next('uid-a', email: 'a@example.com');
    expect(await _login(store, 'email'), isTrue);
    _expectShopping(store, _first);
    expect(shopping.snapshots['uid-b']!.wishedIds, {_second.id});
  });

  test('시작 시 복원한 Firebase UID의 쇼핑 scope를 이메일보다 우선한다', () async {
    final account = _Account(userId: 'uid-a', email: 'a@example.com');
    final shopping = _Shopping()
      ..snapshots['uid-a'] = _snapshot(_first)
      ..snapshots['a@example.com'] = _snapshot(_second);
    final store = _store(account, shopping);
    await store.load();
    expect(account.restores, 1);
    expect(store.accountIdentityKey, 'uid-a');
    expect(shopping.selected, 'uid-a');
    _expectShopping(store, _first);
  });

  test('게스트 쇼핑 기록은 회원에게 자동 합쳐지지 않고 로그아웃 시 복원된다', () async {
    final account = _Account();
    final shopping = _Shopping();
    final store = _store(account, shopping);
    await store.load();
    store.addToCart(_first, '260', _first.color);
    store.toggleWish(_first);
    store.view(_first);
    await _settleSaves();

    account.next('uid-member', email: 'member@example.com');
    expect(await _login(store, 'email'), isTrue);
    _expectEmpty(store);
    expect(shopping.snapshots[null]!.recentIds, [_first.id]);
    await store.signOut();
    expect(shopping.selected, isNull);
    _expectShopping(store, _first);
  });

  for (final provider in ['google', 'kakao', 'naver']) {
    test('$provider 이메일 없는 소셜 로그인도 UID 전용 기록을 사용한다', () async {
      final account = _Account(userId: 'uid-old', email: 'old@example.com');
      final shopping = _Shopping()
        ..snapshots['uid-old'] = _snapshot(_first)
        ..snapshots['uid-$provider'] = _snapshot(_second);
      final store = _store(account, shopping);
      await store.load();
      account.next('uid-$provider');
      expect(await _login(store, provider), isTrue);
      expect(store.isLoggedIn, isTrue);
      expect(store.userEmail, isNull);
      expect(store.accountIdentityKey, 'uid-$provider');
      expect(shopping.selected, 'uid-$provider');
      _expectShopping(store, _second);
    });
  }

  test('동일한 이메일이라도 Firebase UID가 다르면 쇼핑 기록이 분리된다', () async {
    final account = _Account(userId: 'uid-a', email: 'shared@example.com');
    final shopping = _Shopping()
      ..snapshots['uid-a'] = _snapshot(_first)
      ..snapshots['uid-b'] = _snapshot(_second);
    final store = _store(account, shopping);
    await store.load();
    account.next('uid-b', email: 'shared@example.com');
    expect(await _login(store, 'email'), isTrue);
    expect(shopping.selected, 'uid-b');
    _expectShopping(store, _second);
  });

  test('소셜 로그인 취소는 기존 UID scope와 기록을 보존한다', () async {
    final account = _Account(userId: 'uid-a', email: 'a@example.com');
    final shopping = _Shopping()..snapshots['uid-a'] = _snapshot(_first);
    final store = _store(account, shopping);
    await store.load();
    account.result = _LoginResult.canceled;
    expect(await _login(store, 'google'), isFalse);
    expect(shopping.selected, 'uid-a');
    expect(store.accountIdentityKey, 'uid-a');
    _expectShopping(store, _first);
    store.addToCart(_second, '260', _second.color);
    await _settleSaves();
    expect(shopping.saves.last.owner, 'uid-a');
  });

  test('인증 실패로 UID가 바뀌지 않으면 기존 scope를 유지한다', () async {
    final account = _Account(userId: 'uid-a', email: 'a@example.com');
    final shopping = _Shopping()..snapshots['uid-a'] = _snapshot(_first);
    final store = _store(account, shopping);
    await store.load();
    account.result = _LoginResult.rejected;
    await expectLater(_login(store, 'email'), throwsStateError);
    expect(shopping.selected, 'uid-a');
    _expectShopping(store, _first);
    store.view(_second);
    await _settleSaves();
    expect(shopping.saves.last.owner, 'uid-a');
  });

  test('Firebase 새 UID 인증 후 MySQL 연결 실패 시 이전 회원 기록을 노출·저장하지 않는다', () async {
    final account = _Account(userId: 'uid-a', email: 'a@example.com');
    final shopping = _Shopping()
      ..snapshots['uid-a'] = _snapshot(_first)
      ..snapshots['uid-b'] = _snapshot(_second);
    final store = _store(account, shopping);
    await store.load();
    account.next('uid-b', email: 'b@example.com');
    account.result = _LoginResult.syncFailed;
    await expectLater(_login(store, 'email'), throwsStateError);
    expect(store.accountConnectionError, isNotNull);
    expect(store.accountIdentityKey, 'uid-b');
    expect(shopping.selected, 'uid-b');
    expect(store.cart.any((item) => item.product.id == _first.id), isFalse);
    expect(store.wishedIds, isNot(contains(_first.id)));
    expect(store.recentIds, isNot(contains(_first.id)));
    store.addToCart(_third, '260', _third.color);
    store.toggleWish(_third);
    store.view(_third);
    await _settleSaves();
    for (final save in shopping.saves.where((save) => save.owner == 'uid-b')) {
      expect(
        save.snapshot.cart.any((item) => item.product.id == _first.id),
        isFalse,
      );
      expect(save.snapshot.wishedIds, isNot(contains(_first.id)));
      expect(save.snapshot.recentIds, isNot(contains(_first.id)));
    }
    expect(shopping.snapshots['uid-a']!.wishedIds, {_first.id});
  });

  test('이전 UID의 지연된 load는 새 UID로 로그인한 화면을 덮어쓰지 않는다', () async {
    final account = _Account(userId: 'uid-a', email: 'a@example.com');
    final shopping = _Shopping()..snapshots['uid-b'] = _snapshot(_second);
    final held = shopping.holdNextLoad('uid-a');
    final store = _store(account, shopping);
    final oldLoad = store.load();
    await held.started.future;
    account.next('uid-b', email: 'b@example.com');
    expect(await _login(store, 'email'), isTrue);
    _expectShopping(store, _second);
    held.result.complete(_snapshot(_first));
    await oldLoad;
    expect(shopping.selected, 'uid-b');
    _expectShopping(store, _second);
  });

  test('초기 쇼핑 load 완료 전에는 쇼핑 mutation과 저장을 막는다', () async {
    final account = _Account(userId: 'uid-a', email: 'a@example.com');
    final shopping = _Shopping();
    final held = shopping.holdNextLoad('uid-a');
    final store = _store(account, shopping);
    final loading = store.load();
    await held.started.future;
    store.view(_third);
    store.toggleWish(_third);
    store.addToCart(_third, '260', _third.color);
    await _settleSaves();
    _expectEmpty(store);
    expect(shopping.saves, isEmpty);
    held.result.complete(_snapshot(_first));
    await loading;
    _expectShopping(store, _first);
  });

  test('계정 전환 동안 기존 장바구니 수정과 주문을 막고 새 회원 기록을 로드한다', () async {
    final account = _Account(userId: 'uid-a', email: 'a@example.com');
    final shopping = _Shopping()
      ..snapshots['uid-a'] = _snapshot(_first)
      ..snapshots['uid-b'] = _snapshot(_second);
    final orders = _Orders();
    final store = _store(account, shopping, orders: orders);
    await store.load();
    final original = store.cart.single;
    account.next('uid-b', email: 'b@example.com');
    final gate = Completer<void>();
    final started = Completer<void>();
    account.loginGate = gate;
    account.loginStarted = started;
    final signingIn = _login(store, 'email');
    await started.future;
    store.view(_third);
    store.toggleWish(_third);
    store.addToCart(_third, '260', _third.color);
    store.changeQuantity(original, 9);
    store.updateCartOption(original, size: '270');
    store.removeCartKeys({original.key});
    await expectLater(store.placeOrder('성동구'), throwsStateError);
    await _settleSaves();
    expect(shopping.saves, isEmpty);
    expect(orders.creates, 0);
    gate.complete();
    expect(await signingIn, isTrue);
    _expectShopping(store, _second);
    expect(shopping.snapshots['uid-a']!.cart.single.quantity, 1);
  });

  test('쇼핑 load 실패 후에는 빈 상태를 저장하지 않고 재시도로 기존 기록을 복원한다', () async {
    final account = _Account(userId: 'uid-a', email: 'a@example.com');
    final shopping = _Shopping()
      ..snapshots['uid-a'] = _snapshot(_first)
      ..failedOwners.add('uid-a');
    final store = _store(account, shopping);
    await store.load();
    expect(store.shoppingError, isNotNull);
    store.addToCart(_third, '260', _third.color);
    store.toggleWish(_third);
    store.view(_third);
    await _settleSaves();
    _expectEmpty(store);
    expect(shopping.saves, isEmpty);
    shopping.failedOwners.clear();
    await store.load();
    expect(store.shoppingError, isNull);
    _expectShopping(store, _first);
  });

  test('이전 회원의 진행 중 주문 완료가 새 회원 cart/orders를 변경하지 않는다', () async {
    final account = _Account(userId: 'uid-a', email: 'a@example.com');
    final shopping = _Shopping()
      ..snapshots['uid-a'] = _snapshot(_first)
      ..snapshots['uid-b'] = _snapshot(_second);
    final gate = Completer<StoreOrder>();
    final orders = _Orders()..createGate = gate;
    final store = _store(account, shopping, orders: orders);
    await store.load();
    final placing = store.placeOrder('성동구');
    expect(orders.creates, 1);
    account.next('uid-b', email: 'b@example.com');
    expect(await _login(store, 'email'), isTrue);
    final oldOrder = StoreOrder(
      number: 'old-member-order',
      items: _snapshot(_first).cart,
      date: DateTime(2026, 10, 6),
      district: '성동구',
    );
    gate.complete(oldOrder);
    await placing;
    await _settleSaves();
    _expectShopping(store, _second);
    expect(
      store.orders.any((order) => order.number == oldOrder.number),
      isFalse,
    );
    expect(shopping.saves.where((save) => save.owner == 'uid-b'), isEmpty);
  });

  for (final source in ['orders', 'reviews', 'benefits', 'support']) {
    for (final transition in ['login', 'logout']) {
      for (final fails in [false, true]) {
        test(
          '$source A의 늦은 ${fails ? '오류' : '응답'}를 $transition 후 폐기한다',
          () async {
            final account = _Account(userId: 'uid-a', email: 'a@example.com');
            final shopping = _Shopping()
              ..snapshots['uid-a'] = _snapshot(_first)
              ..snapshots['uid-b'] = _snapshot(_second);
            final orders = _Orders()
              ..records = [_order('a')]
              ..benefits = {'owner': 'a'};
            final reviews = _Reviews()..records = [_review('a')];
            final support = _Support()
              ..records = [_inquiry('a')]
              ..keys = {'a-restock'};
            final store = _store(
              account,
              shopping,
              orders: orders,
              reviews: reviews,
              support: support,
            );
            await store.load();

            late final Future<void> pending;
            late final Future<void> started;
            late final void Function() complete;
            final failure = StateError('Earlier account private read failed');
            switch (source) {
              case 'orders':
                final held = _HeldRead<List<StoreOrder>>();
                orders.nextRead = held;
                started = held.started.future;
                complete = () => fails
                    ? held.result.completeError(failure)
                    : held.result.complete([_order('a')]);
                pending = store.refreshOrders();
              case 'reviews':
                final held = _HeldRead<List<ProductReview>>();
                reviews.nextRead = held;
                started = held.started.future;
                complete = () => fails
                    ? held.result.completeError(failure)
                    : held.result.complete([_review('a')]);
                pending = store.refreshReviews();
              case 'benefits':
                final held = _HeldRead<Map<String, dynamic>>();
                orders.nextBenefitsRead = held;
                started = held.started.future;
                complete = () => fails
                    ? held.result.completeError(failure)
                    : held.result.complete({'owner': 'a'});
                pending = store.refreshBenefits();
              case 'support':
                final held = _HeldRead<List<InquiryEntry>>();
                support.nextRead = held;
                started = held.started.future;
                complete = () => fails
                    ? held.result.completeError(failure)
                    : held.result.complete([_inquiry('a')]);
                pending = store.refreshSupport();
              default:
                throw StateError('Unknown private source');
            }
            await started;
            orders
              ..records = [_order('b')]
              ..benefits = {'owner': 'b'};
            reviews.records = [_review('b')];
            support
              ..records = [_inquiry('b')]
              ..keys = {'b-restock'};
            if (transition == 'login') {
              account.next('uid-b', email: 'b@example.com');
              expect(await _login(store, 'email'), isTrue);
            } else {
              await store.signOut();
            }
            final reviewReads = reviews.reads;
            final supportReads = support.reads;
            final keyReads = support.keyReads;
            complete();
            await pending;

            if (transition == 'login') {
              expect(store.orders.map((order) => order.number), ['b-order']);
              expect(store.reviews.map((review) => review.content), [
                'b-review',
              ]);
              expect(store.accountBenefits, {'owner': 'b'});
              expect(store.inquiries.map((inquiry) => inquiry.title), [
                'b-inquiry',
              ]);
              expect(store.restockKeys, {'b-restock'});
              _expectShopping(store, _second);
            } else {
              expect(store.isLoggedIn, isFalse);
              expect(store.orders, isEmpty);
              expect(store.reviews, isEmpty);
              expect(store.accountBenefits, isNull);
              expect(store.inquiries, isEmpty);
              expect(store.restockKeys, isEmpty);
            }
            expect(store.ordersError, isNull);
            expect(store.reviewsError, isNull);
            expect(store.benefitsError, isNull);
            expect(store.supportError, isNull);
            expect(store.ordersLoading, isFalse);
            expect(store.benefitsLoading, isFalse);
            if (source == 'orders') {
              expect(reviews.reads, reviewReads);
              expect(support.reads, supportReads);
              expect(support.keyReads, keyReads);
            }
          },
        );
      }
    }
  }

  test('회원가입이 Firebase UID를 바꾸면 새 회원 쇼핑 기록만 로드한다', () async {
    final account = _Account(userId: 'uid-a', email: 'a@example.com');
    final shopping = _Shopping()..snapshots['uid-a'] = _snapshot(_first);
    final store = _store(account, shopping);
    await store.load();
    account.next('uid-new', email: 'new@example.com');
    await store.signUp('new@example.com', 'unused-test-password');
    expect(store.isLoggedIn, isTrue);
    expect(store.accountIdentityKey, 'uid-new');
    expect(shopping.selected, 'uid-new');
    _expectEmpty(store);
    store.addToCart(_third, '260', _third.color);
    await _settleSaves();
    expect(shopping.saves.last.owner, 'uid-new');
    expect(shopping.snapshots['uid-a']!.cart.single.product.id, _first.id);
  });

  test('회원가입 인증 후 고객 연결 실패라도 이전 UID 기록은 남기지 않는다', () async {
    final account = _Account(userId: 'uid-a', email: 'a@example.com');
    final shopping = _Shopping()..snapshots['uid-a'] = _snapshot(_first);
    final store = _store(account, shopping);
    await store.load();
    account.next('uid-new', email: 'new@example.com');
    account.result = _LoginResult.syncFailed;
    await expectLater(
      store.signUp('new@example.com', 'unused-test-password'),
      throwsStateError,
    );
    expect(store.accountIdentityKey, 'uid-new');
    expect(shopping.selected, 'uid-new');
    expect(store.accountConnectionError, isNotNull);
    _expectEmpty(store);
    expect(shopping.snapshots['uid-a']!.wishedIds, {_first.id});
  });

  test('Firebase 로그아웃 후 소셜 정리 오류가 나도 게스트 scope와 상태로 전환한다', () async {
    final account = _Account(userId: 'uid-a', email: 'a@example.com');
    final shopping = _Shopping()
      ..snapshots['uid-a'] = _snapshot(_first)
      ..snapshots[null] = _snapshot(_second);
    final orders = _Orders()
      ..records = [_order('a')]
      ..benefits = {'owner': 'a'};
    final reviews = _Reviews()..records = [_review('a')];
    final support = _Support()
      ..records = [_inquiry('a')]
      ..keys = {'a-restock'};
    final store = _store(
      account,
      shopping,
      orders: orders,
      reviews: reviews,
      support: support,
    );
    await store.load();
    account.failAfterSignOut = true;
    await expectLater(store.signOut(), throwsStateError);
    expect(store.isLoggedIn, isFalse);
    expect(store.accountIdentityKey, isNull);
    expect(shopping.selected, isNull);
    _expectShopping(store, _second);
    expect(store.orders, isEmpty);
    expect(store.reviews, isEmpty);
    expect(store.accountBenefits, isNull);
    expect(store.inquiries, isEmpty);
    expect(store.restockKeys, isEmpty);
    store.addToCart(_third, '260', _third.color);
    await _settleSaves();
    expect(shopping.saves.last.owner, isNull);
    expect(shopping.snapshots['uid-a']!.recentIds, [_first.id]);
  });
}
