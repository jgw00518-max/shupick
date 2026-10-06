import 'models.dart';

/// Device-wide UI preferences, independent of account sign-in.
abstract interface class SettingsRepository {
  Future<String> language();
  Future<bool> dark();
  Future<bool> push();
  Future<void> saveLanguage(String value);
  Future<void> saveDark(bool value);
  Future<void> savePush(bool value);
}

/// 실제 연동 시 API 기반 구현으로 교체하는 상품 조회 경계입니다.
abstract interface class ProductRepository {
  Future<List<Product>> getProducts();
  Future<List<ProductOption>> getProductOptions(int productId);
}

abstract interface class CatalogRepository {
  Future<CatalogMetadata> getCatalog();
}

/// 회원 혜택 조회와 구매확정 요청을 제공합니다.
abstract interface class AccountBenefitsRepository {
  Future<Map<String, dynamic>> getAccountBenefits();
  Future<void> confirmOrder(int orderId);
}

/// 실제 연동 시 서버가 인증과 계정 정보를 관리하도록 교체합니다.
abstract interface class AccountRepository {
  Future<bool> signIn(String email, String password);
  Future<void> signUp(String email, String password);

  Future<bool> signInWithGoogle();
  Future<void> signOut();

  String? get displayName;
  String? get email;
}

/// 주문 생성과 취소는 추후 MySQL 백엔드 API에서 검증해야 합니다.
/// 로그인 상태를 복원하고 서버의 고객 연결을 확인할 수 있는 인증 저장소.
abstract interface class SessionAccountRepository {
  Future<bool> restoreSession();
}

/// 이메일이 없는 소셜 사용자도 UID로 로그인과 개인 데이터를 구분합니다.
abstract interface class IdentityAccountRepository {
  String? get userId;
}

/// Presentation-only authentication source, independent of names/contact email.
enum AccountLoginProvider { email, google, kakao, naver }

abstract interface class LoginProviderAccountRepository {
  AccountLoginProvider? get loginProvider;
}

/// 기존 테스트/목업 인증 구현과 분리된 실제 소셜 로그인 경계입니다.
abstract interface class SocialAccountRepository {
  Future<bool> signInWithKakao();
  Future<bool> signInWithNaver();
}

abstract interface class OrderRepository {
  Future<List<PickupBranch>> getPickupBranches();
  Future<List<StoreOrder>> getOrders();
  Future<StoreOrder> createOrder(
    List<CartItem> items,
    String district, {
    required int paidTotal,
    required int couponDiscount,
    required int pointsUsed,
    required String paymentMethod,
    int? customerCouponId,
  });
  Future<StoreOrder> cancelOrder(StoreOrder order);
}

/// 실제 연동 시 구매 항목을 검증하는 리뷰 API로 교체합니다.
abstract interface class ReviewRepository {
  Future<List<ProductReview>> getReviews();
  Future<void> addReview(ProductReview review);
  Future<void> updateReview(ProductReview review);
  Future<void> deleteReview(ProductReview review);
}

/// 서버 쿠폰과 만료 처리된 포인트 잔액을 조회합니다.
abstract interface class CheckoutBenefitsRepository {
  Future<List<CheckoutCoupon>> getCoupons();
  Future<int> getPointBalance();
}

/// 추후 장바구니·찜·최근 본 기록의 API/SQLite 구현으로 교체합니다.
abstract interface class ShoppingRepository {
  Future<ShoppingSnapshot> load(List<Product> products);
  Future<void> save(ShoppingSnapshot snapshot);
}

/// Selects device-local shopping data by Firebase UID, never by contact email.
/// Selection is synchronous; each load/save must capture its selected owner.
abstract interface class AccountScopedShoppingRepository {
  void selectAccount(String? userId);
}

/// 로컬 쇼핑 상태와 별도로 고객 행동을 분석용 서버 원장에 전송합니다.
abstract interface class InteractionRepository {
  Future<void> record(
    String eventType,
    int productId, {
    String? color,
    String? size,
    int? quantity,
  });
  Future<void> flush();
}

/// 문의와 재입고 알림의 목업 데이터를 추후 서버 저장소로 교체합니다.
abstract interface class SupportRepository {
  Future<List<InquiryEntry>> getInquiries();
  Future<InquiryEntry> createInquiry(
    String kind,
    String title,
    String body, {
    int? productId,
  });
  Future<Set<String>> getRestockKeys();
  Future<void> saveRestockKeys(Set<String> keys);
}
