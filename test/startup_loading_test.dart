import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/app/store_controller.dart';
import 'package:shupick/data/mock_repositories.dart';
import 'package:shupick/domain/models.dart';
import 'package:shupick/domain/repositories.dart';

class _Account extends MockAccountRepository
    implements SessionAccountRepository {
  bool connected = false;
  bool fail = false;
  int restores = 0;
  @override
  Future<bool> restoreSession() async {
    restores++;
    if (fail) throw StateError('Connection failed');
    connected = true;
    return true;
  }
}

class _Orders extends MockOrderRepository {
  _Orders(this.account);
  final _Account account;
  int calls = 0;
  @override
  Future<List<StoreOrder>> getOrders() async {
    calls++;
    expect(account.connected, isTrue);
    return super.getOrders();
  }
}

class _Reviews extends MockReviewRepository {
  bool fail = true;
  @override
  Future<List<ProductReview>> getReviews() async {
    if (fail) throw StateError('Review lookup failed');
    return super.getReviews();
  }
}

class _Support extends MockSupportRepository {
  @override
  Future<List<InquiryEntry>> getInquiries() async =>
      throw StateError('Support failed');
}

void main() {
  StoreController create(
    _Account account,
    _Orders orders, {
    ReviewRepository? reviews,
    SupportRepository? support,
  }) => StoreController(
    productsRepository: MockProductRepository(),
    accountRepository: account,
    orderRepository: orders,
    reviewRepository: reviews ?? MockReviewRepository(),
    shoppingRepository: MockShoppingRepository(),
    supportRepository: support ?? MockSupportRepository(),
  );

  test('기존 로그인 복원과 회원 연결이 주문 조회보다 먼저 진행된다', () async {
    final account = _Account();
    final orders = _Orders(account);
    final store = create(account, orders);
    await store.load();
    expect(account.restores, 1);
    expect(orders.calls, 1);
    expect(store.isLoggedIn, isTrue);
    expect(store.userEmail, 'user@sole.kr');
    expect(store.loadError, isNull);
    expect(store.accountConnectionError, isNull);
    store.dispose();
  });

  test('회원 연결 오류가 상품을 차단하지 않고 재시도로 회복한다', () async {
    final account = _Account()..fail = true;
    final orders = _Orders(account);
    final store = create(account, orders);
    await store.load();
    expect(store.products, hasLength(72));
    expect(store.loadError, isNull);
    expect(store.accountConnectionError, isNotNull);
    expect(orders.calls, 0);
    expect(store.isLoggedIn, isTrue); // 로그아웃 접근은 계속 가능
    account.fail = false;
    await store.load();
    expect(store.accountConnectionError, isNull);
    expect(orders.calls, 1);
    await store.signOut();
    expect(store.isLoggedIn, isFalse);
    expect(store.userEmail, isNull);
    store.dispose();
  });

  test('리뷰·문의 오류는 상품·주문 오류로 표시하지 않는다', () async {
    final account = _Account();
    final reviews = _Reviews();
    final store = create(
      account,
      _Orders(account),
      reviews: reviews,
      support: _Support(),
    );
    await store.load();
    expect(store.loadError, isNull);
    expect(store.products, hasLength(72));
    expect(store.orders, isNotEmpty);
    expect(store.ordersError, isNull);
    expect(store.reviewsError, isNotNull);
    expect(store.supportError, isNotNull);
    reviews.fail = false;
    await store.refreshReviews();
    expect(store.reviewsError, isNull);
    store.dispose();
  });
}
