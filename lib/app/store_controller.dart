import 'dart:async';

import 'package:get/get.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';
import '../domain/customer_enrollment.dart';

/// 화면 상태를 관리하며 저장과 조회는 Repository에 위임합니다.
class StoreController extends GetxController {
  StoreController({
    required this.productsRepository,
    required this.accountRepository,
    required this.orderRepository,
    required this.reviewRepository,
    required this.shoppingRepository,
    required this.supportRepository,
    this.interactionRepository,
  });

  final ProductRepository productsRepository;
  final AccountRepository accountRepository;
  final OrderRepository orderRepository;
  final ReviewRepository reviewRepository;
  final ShoppingRepository shoppingRepository;
  final SupportRepository supportRepository;
  final InteractionRepository? interactionRepository;
  Timer? _interactionRetry;

  /// 분석 전송 실패는 쇼핑 동작을 막지 않고 로컬 큐에서 재시도합니다.
  void _recordInteraction(
    String type,
    Product product, {
    String? color,
    String? size,
    int? quantity,
  }) {
    final repository = interactionRepository;
    if (repository != null) {
      unawaited(
        repository
            .record(
              type,
              product.id,
              color: color,
              size: size,
              quantity: quantity,
            )
            .catchError((Object _) {}),
      );
    }
  }

  void _flushInteractions() {
    final repository = interactionRepository;
    if (repository != null) {
      unawaited(repository.flush().catchError((Object _) {}));
    }
  }

  List<Product> products = [];
  Map<String, List<String>> categoryTree = {};
  Map<String, List<int>> brands = {};
  Map<String, dynamic>? accountBenefits;
  String? benefitsError;
  bool benefitsLoading = false;

  /// 마이페이지의 회원등급·쿠폰·포인트 원장을 갱신합니다.
  Future<void> refreshBenefits() async {
    final repository = orderRepository;
    if (repository is! AccountBenefitsRepository || _authTransition) return;
    final generation = _accountGeneration;
    benefitsLoading = true;
    benefitsError = null;
    update();
    try {
      final loaded = await (repository as AccountBenefitsRepository)
          .getAccountBenefits();
      if (generation != _accountGeneration) return;
      accountBenefits = loaded;
    } catch (_) {
      if (generation != _accountGeneration) return;
      benefitsError = '회원 혜택을 불러오지 못했습니다.';
    } finally {
      if (generation == _accountGeneration) {
        benefitsLoading = false;
        update();
      }
    }
  }

  Future<void> confirmPurchase(StoreOrder order) async {
    final repository = orderRepository;
    if (repository is! AccountBenefitsRepository || order.id == null) {
      throw StateError('서버 주문이 필요합니다.');
    }
    await (repository as AccountBenefitsRepository).confirmOrder(order.id!);
    await refreshOrders();
    await refreshBenefits();
  }

  List<StoreOrder> orders = [];
  final List<ProductReview> reviews = [];
  final List<CartItem> cart = [];
  final Set<int> wishedIds = {};
  final List<int> recentIds = [];
  final List<InquiryEntry> inquiries = [];
  final Set<String> restockKeys = {};
  bool loading = true;
  String? loadError;
  bool isLoggedIn = false;
  String? userName;
  String? userEmail;
  String? userId;
  AccountLoginProvider? loginProvider;
  String? get accountIdentityKey => userId ?? userEmail;

  /// Email-login labels are presentation only; never change account identity.
  String? get profileDisplayName {
    if (isLoggedIn && loginProvider == AccountLoginProvider.email) {
      final address = userEmail?.trim();
      if (address != null) {
        final separator = address.indexOf('@');
        if (separator > 0 && separator < address.length - 1) {
          return address.substring(0, separator).trim();
        }
      }
    }
    return userName;
  }

  bool ordersLoading = false;
  String? ordersError;
  String? reviewsError;
  String? supportError;
  String? shoppingError;
  String? accountConnectionError;
  bool shoppingLoading = true;
  bool _shoppingReady = false;
  bool _authTransition = false;
  int _shoppingGeneration = 0;
  int _accountGeneration = 0;
  String? _shoppingIdentity;

  String? get _currentShoppingIdentity =>
      isLoggedIn ? accountIdentityKey : null;

  bool get _canChangeShopping =>
      !_authTransition &&
      !shoppingLoading &&
      _shoppingReady &&
      _shoppingIdentity == _currentShoppingIdentity;

  bool get shoppingReady => _canChangeShopping;

  void _clearShopping() {
    cart.clear();
    wishedIds.clear();
    recentIds.clear();
  }

  /// Never apply an earlier account's late SQLite result to the current UI.
  Future<void> _reloadShoppingForAccount() async {
    final generation = ++_shoppingGeneration;
    final identity = _currentShoppingIdentity;
    _shoppingIdentity = identity;
    final repository = shoppingRepository;
    if (repository is AccountScopedShoppingRepository) {
      (repository as AccountScopedShoppingRepository).selectAccount(identity);
    }
    shoppingLoading = true;
    _shoppingReady = false;
    shoppingError = null;
    _clearShopping();
    update();
    try {
      final shopping = await repository.load(products);
      if (generation != _shoppingGeneration ||
          identity != _currentShoppingIdentity) {
        return;
      }
      cart.addAll(shopping.cart);
      wishedIds.addAll(shopping.wishedIds);
      recentIds.addAll(shopping.recentIds);
      _shoppingReady = true;
    } catch (_) {
      if (generation == _shoppingGeneration) {
        shoppingError = '저장된 장바구니·찜 정보를 불러오지 못했습니다.';
      }
    } finally {
      if (generation == _shoppingGeneration) {
        shoppingLoading = false;
        update();
      }
    }
  }

  void _readAccountIdentity() {
    final previousIdentity = _currentShoppingIdentity;
    userName = accountRepository.displayName;
    userEmail = accountRepository.email;
    final repository = accountRepository;
    userId = repository is IdentityAccountRepository
        ? (repository as IdentityAccountRepository).userId
        : null;
    isLoggedIn = repository is IdentityAccountRepository
        ? userId != null
        : userEmail != null;
    loginProvider = isLoggedIn && repository is LoginProviderAccountRepository
        ? (repository as LoginProviderAccountRepository).loginProvider
        : null;
    if (previousIdentity != _currentShoppingIdentity) {
      _accountGeneration++;
      _shoppingGeneration++;
      _shoppingReady = false;
      _clearShopping();
      // Account switch failures must not leave the previous member's cache.
      orders.clear();
      reviews.clear();
      inquiries.clear();
      restockKeys.clear();
      accountBenefits = null;
      ordersLoading = false;
      benefitsLoading = false;
      ordersError = null;
      reviewsError = null;
      supportError = null;
      benefitsError = null;
    }
  }

  Future<void> _restoreAccount() async {
    final repository = accountRepository;
    accountConnectionError = null;
    if (repository is! SessionAccountRepository) return;
    try {
      isLoggedIn = await (repository as SessionAccountRepository)
          .restoreSession();
      _readAccountIdentity();
    } catch (_) {
      _readAccountIdentity();
      accountConnectionError = '회원 정보 연결에 실패했습니다. 연결을 다시 시도해주세요.';
      orders.clear();
      reviews.clear();
      inquiries.clear();
      restockKeys.clear();
      accountBenefits = null;
    }
  }

  /// 로그인 고객의 주문을 다시 읽고 조회 실패를 상품 로딩과 분리합니다.
  Future<void> refreshOrders() async {
    if (accountConnectionError != null || _authTransition) return;
    final generation = _accountGeneration;
    ordersLoading = true;
    ordersError = null;
    update();
    try {
      final loaded = await orderRepository.getOrders();
      if (generation != _accountGeneration) return;
      orders = List.of(loaded);
    } catch (_) {
      if (generation != _accountGeneration) return;
      orders.clear();
      ordersError = '주문 내역을 불러오지 못했습니다. 다시 시도해주세요.';
    } finally {
      if (generation == _accountGeneration) {
        ordersLoading = false;
        update();
      }
    }
    if (generation != _accountGeneration) return;
    await refreshReviews();
    if (generation != _accountGeneration) return;
    await refreshSupport();
  }

  Future<void> refreshReviews() async {
    if (accountConnectionError != null || _authTransition) return;
    final generation = _accountGeneration;
    reviewsError = null;
    try {
      final loaded = await reviewRepository.getReviews();
      if (generation != _accountGeneration) return;
      reviews
        ..clear()
        ..addAll(loaded);
    } catch (_) {
      if (generation != _accountGeneration) return;
      reviews.clear();
      reviewsError = '리뷰를 불러오지 못했습니다. 다시 시도해주세요.';
    }
    update();
  }

  @override
  void onInit() {
    super.onInit();
    load();
    if (interactionRepository != null) {
      _flushInteractions();
      _interactionRetry = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _flushInteractions(),
      );
    }
  }

  @override
  void onClose() {
    _interactionRetry?.cancel();
    super.onClose();
  }

  int get cartCount => cart.fold(0, (sum, item) => sum + item.quantity);
  int get cartTotal => cart.fold(0, (sum, item) => sum + item.total);
  List<Product> get wished =>
      products.where((p) => wishedIds.contains(p.id)).toList();
  List<Product> get recent => recentIds
      .map((id) => products.where((p) => p.id == id).firstOrNull)
      .whereType<Product>()
      .toList();

  /// 상세 화면이 선택한 상품의 최신 색상·사이즈 재고를 요청합니다.
  Future<List<ProductOption>> getProductOptions(int productId) =>
      productsRepository.getProductOptions(productId);

  Future<List<PickupBranch>> getPickupBranches() =>
      orderRepository.getPickupBranches();

  Future<List<CheckoutCoupon>> getCoupons() async =>
      orderRepository is CheckoutBenefitsRepository
      ? (orderRepository as CheckoutBenefitsRepository).getCoupons()
      : const [];
  Future<int> getPointBalance() async =>
      orderRepository is CheckoutBenefitsRepository
      ? (orderRepository as CheckoutBenefitsRepository).getPointBalance()
      : 0;

  /// 목업 데이터도 비동기로 읽어 API 교체 시 UI 흐름을 유지합니다.
  Future<void> load() async {
    if (_loadInProgress || _authTransition) return;
    _loadInProgress = true;
    loading = true;
    shoppingLoading = true;
    _shoppingReady = false;
    loadError = null;
    update();
    await _restoreAccount();
    final accountGeneration = _accountGeneration;
    try {
      products = await productsRepository.getProducts();
      if (productsRepository is CatalogRepository) {
        try {
          final metadata = await (productsRepository as CatalogRepository)
              .getCatalog();
          categoryTree = metadata.categories;
          brands = metadata.brands;
        } catch (_) {
          categoryTree = {
            for (final product in products)
              product.middleCategory: products
                  .where(
                    (item) => item.middleCategory == product.middleCategory,
                  )
                  .map((item) => item.subcategory)
                  .toSet()
                  .toList(),
          };
        }
      } else {
        categoryTree = {
          for (final product in products)
            product.middleCategory: products
                .where((item) => item.middleCategory == product.middleCategory)
                .map((item) => item.subcategory)
                .toSet()
                .toList(),
        };
      }
    } catch (_) {
      loadError = '상품을 불러오지 못했습니다.';
    }
    // 로컬 쇼핑 정보 및 회원 전용 조회는 상품 오류 상태와 분리합니다.
    try {
      if (accountGeneration == _accountGeneration && !_authTransition) {
        await _reloadShoppingForAccount();
      }
      if (accountGeneration == _accountGeneration &&
          !_authTransition &&
          accountConnectionError == null) {
        await refreshOrders();
        if (isLoggedIn) await refreshBenefits();
      }
    } finally {
      _loadInProgress = false;
      loading = false;
      update();
    }
  }

  bool _loadInProgress = false;

  void view(Product product) {
    if (!_canChangeShopping) return;
    _recordInteraction('VIEW', product);
    recentIds.remove(product.id);
    recentIds.insert(0, product.id);
    update();
    unawaited(_saveShopping());
  }

  void toggleWish(Product product) {
    if (!_canChangeShopping) return;
    if (!wishedIds.remove(product.id)) wishedIds.add(product.id);
    _recordInteraction(
      wishedIds.contains(product.id) ? 'WISH_ADD' : 'WISH_REMOVE',
      product,
    );
    update();
    unawaited(_saveShopping());
  }

  void addToCart(Product product, String size, String color) {
    addCartItems([CartItem(product: product, size: size, color: color)]);
  }

  void addCartItems(List<CartItem> items) {
    if (!_canChangeShopping) return;
    for (final item in items) {
      _recordInteraction(
        'CART_ADD',
        item.product,
        color: item.color,
        size: item.size,
        quantity: item.quantity,
      );
      final index = cart.indexWhere((entry) => entry.key == item.key);
      if (index < 0) {
        cart.add(item);
      } else {
        cart[index] = cart[index].copyWith(
          quantity: (cart[index].quantity + item.quantity).clamp(1, 99),
        );
      }
    }
    update();
    unawaited(_saveShopping());
  }

  void changeQuantity(CartItem item, int quantity) {
    if (!_canChangeShopping) return;
    final index = cart.indexWhere((entry) => entry.key == item.key);
    if (index < 0) return;
    cart[index] = cart[index].copyWith(quantity: quantity.clamp(1, 99));
    _recordInteraction(
      'CART_QUANTITY',
      item.product,
      color: item.color,
      size: item.size,
      quantity: cart[index].quantity,
    );
    update();
    unawaited(_saveShopping());
  }

  void updateCartOption(CartItem item, {String? size, String? color}) {
    if (!_canChangeShopping) return;
    final index = cart.indexWhere((entry) => entry.key == item.key);
    if (index < 0) return;
    final updated = cart[index].copyWith(size: size, color: color);
    _recordInteraction(
      'CART_OPTION',
      updated.product,
      color: updated.color,
      size: updated.size,
      quantity: updated.quantity,
    );
    final duplicate = cart.indexWhere(
      (entry) => entry.key == updated.key && entry.key != item.key,
    );
    cart.removeAt(index);
    if (duplicate >= 0) {
      final target = cart.indexWhere((entry) => entry.key == updated.key);
      cart[target] = cart[target].copyWith(
        quantity: (cart[target].quantity + updated.quantity).clamp(1, 99),
      );
    } else {
      cart.add(updated);
    }
    update();
    unawaited(_saveShopping());
  }

  void removeCartKeys(Set<String> keys) {
    if (!_canChangeShopping) return;
    for (final item in cart.where((item) => keys.contains(item.key))) {
      _recordInteraction(
        'CART_REMOVE',
        item.product,
        color: item.color,
        size: item.size,
        quantity: item.quantity,
      );
    }
    cart.removeWhere((item) => keys.contains(item.key));
    update();
    unawaited(_saveShopping());
  }

  Future<void> _saveShopping() async {
    if (!_canChangeShopping) return;
    final generation = _shoppingGeneration;
    try {
      await shoppingRepository.save(
        ShoppingSnapshot(
          cart: List.of(cart),
          wishedIds: Set.of(wishedIds),
          recentIds: List.of(recentIds),
        ),
      );
    } catch (_) {
      if (generation == _shoppingGeneration) {
        shoppingError = '장바구니·찜 정보를 저장하지 못했습니다. 다시 시도해주세요.';
        update();
      }
    }
  }

  Future<bool> signIn(String email, String password) async {
    final success = await _signInAndConnect(
      () => accountRepository.signIn(email, password),
    );
    if (success) {
      isLoggedIn = true;
      userName = accountRepository.displayName;
      userEmail = accountRepository.email;
      _readAccountIdentity();
      await refreshBenefits();
      _flushInteractions();
      await refreshOrders();
      update();
    }
    return success;
  }

  Future<bool> signInWithGoogle() async {
    final success = await _signInAndConnect(accountRepository.signInWithGoogle);

    if (success) {
      isLoggedIn = true;
      userName = accountRepository.displayName;
      userEmail = accountRepository.email;
      _readAccountIdentity();
      await refreshBenefits();
      _flushInteractions();
      await refreshOrders();
      update();
    }

    return success;
  }

  Future<bool> signInWithKakao() => _socialSignIn('kakao');

  Future<bool> signInWithNaver() => _socialSignIn('naver');

  Future<bool> _socialSignIn(String provider) async {
    final repository = accountRepository;
    if (repository is! SocialAccountRepository) {
      throw StateError('이 실행 환경에는 소셜 로그인이 설정되지 않았습니다.');
    }
    final social = repository as SocialAccountRepository;
    final success = await _signInAndConnect(
      provider == 'kakao' ? social.signInWithKakao : social.signInWithNaver,
    );
    if (success) {
      _readAccountIdentity();
      await refreshBenefits();
      _flushInteractions();
      await refreshOrders();
      update();
    }
    return success;
  }

  Future<bool> _signInAndConnect(Future<bool> Function() signIn) async {
    if (_authTransition) throw StateError('계정 변경이 진행 중입니다.');
    _authTransition = true;
    _accountGeneration++;
    _shoppingGeneration++;
    _shoppingReady = false;
    shoppingLoading = true;
    _clearShopping();
    ordersLoading = false;
    benefitsLoading = false;
    update();
    try {
      final success = await signIn();
      _readAccountIdentity();
      if (success) accountConnectionError = null;
      return success;
    } catch (_) {
      _readAccountIdentity();
      if (isLoggedIn) {
        accountConnectionError = '회원 정보 연결에 실패했습니다. 연결을 다시 시도해주세요.';
      }
      update();
      rethrow;
    } finally {
      // A Firebase sign-in can succeed even if MySQL profile sync fails.
      // Restore the actual UID's local data on success, failure, or cancel.
      await _reloadShoppingForAccount();
      _authTransition = false;
      update();
    }
  }

  Future<void> signUp(
    String email,
    String password, {
    String? name,
    String? phone,
    DateTime? birthDate,
  }) async {
    await _signInAndConnect(() async {
      await accountRepository.signUp(
        email,
        password,
        name: name,
        phone: phone,
        birthDate: birthDate,
      );
      return true;
    });
  }

  Future<void> signUpWithEnrollment(
    String email,
    String password,
    VerifiedPhone phone,
    DateTime? birthDate, {
    String? name,
  }) async {
    final repository = accountRepository;
    if (repository is! EnrollmentAccountRepository) {
      throw StateError('휴대폰 인증 회원가입이 설정되지 않았습니다.');
    }
    await _signInAndConnect(() async {
      await (repository as EnrollmentAccountRepository).signUpWithEnrollment(
        email,
        password,
        phone,
        birthDate,
        name: name,
      );
      return true;
    });
  }

  Future<void> signOut() async {
    if (_authTransition) throw StateError('계정 변경이 진행 중입니다.');
    _authTransition = true;
    _accountGeneration++;
    _shoppingGeneration++;
    _shoppingReady = false;
    shoppingLoading = true;
    _clearShopping();
    ordersLoading = false;
    benefitsLoading = false;
    update();
    try {
      await accountRepository.signOut();
      isLoggedIn = false;
      userName = null;
      userEmail = null;
      userId = null;
      loginProvider = null;
      accountConnectionError = null;
      reviewsError = null;
      supportError = null;
      accountBenefits = null;
      benefitsError = null;
      orders.clear();
      reviews.clear();
      inquiries.clear();
      restockKeys.clear();
      ordersError = null;
      ordersLoading = false;
      benefitsLoading = false;
    } catch (_) {
      _readAccountIdentity();
      rethrow;
    } finally {
      await _reloadShoppingForAccount();
      _authTransition = false;
      update();
    }
  }

  Future<StoreOrder> placeOrder(
    String district, {
    List<CartItem>? lines,
    int? paidTotal,
    int couponDiscount = 0,
    int pointsUsed = 0,
    String paymentMethod = '카드',
    int? customerCouponId,
    bool fromCart = true,
  }) async {
    if (!_canChangeShopping) {
      throw StateError('계정과 장바구니 정보를 불러온 뒤 다시 주문해주세요.');
    }
    final accountGeneration = _accountGeneration;
    final selected = List<CartItem>.of(lines ?? cart);
    final subtotal = selected.fold(0, (sum, item) => sum + item.total);
    final order = await orderRepository.createOrder(
      selected,
      district,
      paidTotal: paidTotal ?? subtotal,
      couponDiscount: couponDiscount,
      pointsUsed: pointsUsed,
      paymentMethod: paymentMethod,
      customerCouponId: customerCouponId,
    );
    if (accountGeneration != _accountGeneration) return order;
    orders.insert(0, order);
    if (fromCart) {
      final selectedKeys = selected.map((item) => item.key).toSet();
      cart.removeWhere((item) => selectedKeys.contains(item.key));
    }
    update();
    unawaited(_saveShopping());
    await refreshBenefits();
    return order;
  }

  Future<void> cancelOrder(StoreOrder order) async {
    final canceled = await orderRepository.cancelOrder(order);
    final index = orders.indexWhere((item) => item.number == order.number);
    if (index >= 0) orders[index] = canceled;
    update();
  }

  /// 구매 항목별 리뷰를 저장하고 최초 작성 적립 결과를 회원 혜택에 반영합니다.
  Future<void> addReview(ProductReview review) async {
    if (reviews.any(
      (item) =>
          item.orderNumber == review.orderNumber &&
          item.itemKey == review.itemKey,
    )) {
      return;
    }
    await reviewRepository.addReview(review);
    reviews.add(review);
    await refreshBenefits();
    update();
  }

  Future<void> updateReview(ProductReview review) async {
    await reviewRepository.updateReview(review);
    final index = reviews.indexWhere(
      (item) =>
          item.orderNumber == review.orderNumber &&
          item.itemKey == review.itemKey,
    );
    if (index >= 0) reviews[index] = review;
    update();
  }

  Future<void> deleteReview(ProductReview review) async {
    await reviewRepository.deleteReview(review);
    reviews.removeWhere(
      (item) =>
          item.orderNumber == review.orderNumber &&
          item.itemKey == review.itemKey,
    );
    update();
  }

  Future<void> refreshSupport() async {
    if (accountConnectionError != null || _authTransition) return;
    final generation = _accountGeneration;
    supportError = null;
    try {
      final loaded = await supportRepository.getInquiries();
      if (generation != _accountGeneration) return;
      final keys = await supportRepository.getRestockKeys();
      if (generation != _accountGeneration) return;
      inquiries
        ..clear()
        ..addAll(loaded);
      restockKeys
        ..clear()
        ..addAll(keys);
    } catch (_) {
      if (generation != _accountGeneration) return;
      inquiries.clear();
      restockKeys.clear();
      supportError = '문의·재입고 정보를 불러오지 못했습니다. 다시 시도해주세요.';
    }
    update();
  }

  Future<void> addInquiry(
    String kind,
    String title,
    String body, {
    int? productId,
  }) async {
    final entry = await supportRepository.createInquiry(
      kind,
      title,
      body,
      productId: productId,
    );
    inquiries.insert(0, entry);
    update();
  }

  Future<void> toggleRestock(String key) async {
    final next = Set<String>.of(restockKeys);
    if (!next.remove(key)) next.add(key);
    await supportRepository.saveRestockKeys(next);
    restockKeys
      ..clear()
      ..addAll(next);
    update();
  }

  bool hasReview(StoreOrder order, CartItem item) => reviews.any(
    (review) =>
        review.orderNumber == order.number && review.itemKey == item.key,
  );
}
