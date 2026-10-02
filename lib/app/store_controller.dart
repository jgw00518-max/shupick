import 'dart:async';

import 'package:get/get.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';

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
    if (repository is! AccountBenefitsRepository) return;
    benefitsLoading = true;
    benefitsError = null;
    update();
    try {
      accountBenefits = await (repository as AccountBenefitsRepository)
          .getAccountBenefits();
    } catch (_) {
      benefitsError = '회원 혜택을 불러오지 못했습니다.';
    } finally {
      benefitsLoading = false;
      update();
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
  bool ordersLoading = false;
  String? ordersError;

  /// 로그인 고객의 주문을 다시 읽고 조회 실패를 상품 로딩과 분리합니다.
  Future<void> refreshOrders() async {
    ordersLoading = true;
    ordersError = null;
    update();
    try {
      orders = List.of(await orderRepository.getOrders());
      reviews
        ..clear()
        ..addAll(await reviewRepository.getReviews());
      await refreshSupport();
    } catch (_) {
      ordersError = '주문 내역을 불러오지 못했습니다. 다시 시도해주세요.';
    } finally {
      ordersLoading = false;
      update();
    }
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
    loading = true;
    loadError = null;
    update();
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
      await refreshOrders();
      reviews
        ..clear()
        ..addAll(await reviewRepository.getReviews());
      final shopping = await shoppingRepository.load(products);
      cart
        ..clear()
        ..addAll(shopping.cart);
      wishedIds
        ..clear()
        ..addAll(shopping.wishedIds);
      recentIds
        ..clear()
        ..addAll(shopping.recentIds);
      inquiries
        ..clear()
        ..addAll(await supportRepository.getInquiries());
      restockKeys
        ..clear()
        ..addAll(await supportRepository.getRestockKeys());
    } catch (_) {
      loadError = '상품을 불러오지 못했습니다.';
    } finally {
      loading = false;
      update();
    }
  }

  void view(Product product) {
    _recordInteraction('VIEW', product);
    recentIds.remove(product.id);
    recentIds.insert(0, product.id);
    update();
    unawaited(_saveShopping());
  }

  void toggleWish(Product product) {
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
    await shoppingRepository.save(
      ShoppingSnapshot(
        cart: List.of(cart),
        wishedIds: Set.of(wishedIds),
        recentIds: List.of(recentIds),
      ),
    );
  }

  Future<bool> signIn(String email, String password) async {
    final success = await accountRepository.signIn(email, password);
    if (success) {
      isLoggedIn = true;
      await refreshBenefits();
      _flushInteractions();
      await refreshOrders();
      update();
    }
    return success;
  }

  Future<bool> signInWithGoogle() async {
    final success = await accountRepository.signInWithGoogle();

    if (success) {
      isLoggedIn = true;
      userName = accountRepository.displayName;
      userEmail = accountRepository.email;
      await refreshBenefits();
      _flushInteractions();
      await refreshOrders();
      update();
    }

    return success;
  }

  Future<void> signUp(String email, String password) =>
      accountRepository.signUp(email, password);

  Future<void> signOut() async {
    await accountRepository.signOut();

    isLoggedIn = false;
    accountBenefits = null;
    benefitsError = null;
    orders.clear();
    reviews.clear();
    inquiries.clear();
    restockKeys.clear();
    ordersError = null;
    update();
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
    final loaded = await supportRepository.getInquiries();
    final keys = await supportRepository.getRestockKeys();
    inquiries
      ..clear()
      ..addAll(loaded);
    restockKeys
      ..clear()
      ..addAll(keys);
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
