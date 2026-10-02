import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../domain/models.dart';
import '../domain/repositories.dart';
import 'api_product_repository.dart';

typedef IdTokenProvider = Future<String> Function();

/// Firebase 인증 고객의 주문을 생성하고 MySQL 재고를 예약한 뒤 결제를 확정합니다.
class ApiOrderRepository
    implements
        OrderRepository,
        CheckoutBenefitsRepository,
        AccountBenefitsRepository {
  ApiOrderRepository({
    required this.productsRepository,
    http.Client? client,
    String? baseUrl,
    IdTokenProvider? idTokenProvider,
  }) : _client = client ?? http.Client(),
       _baseUrl = (baseUrl ?? defaultApiBaseUrl).replaceFirst(
         RegExp(r'/$'),
         '',
       ),
       _idTokenProvider = idTokenProvider ?? _firebaseIdToken;

  final ProductRepository productsRepository;
  final http.Client _client;
  final String _baseUrl;
  final IdTokenProvider _idTokenProvider;
  final Random _random = Random.secure();

  @override
  Future<Map<String, dynamic>> getAccountBenefits() async {
    return _decode(
          await _client.get(
            Uri.parse('$_baseUrl/account/benefits'),
            headers: await _headers(),
          ),
          expected: {200},
        )
        as Map<String, dynamic>;
  }

  @override
  Future<void> confirmOrder(int orderId) async {
    _decode(
      await _client.post(
        Uri.parse('$_baseUrl/orders/$orderId/confirm'),
        headers: await _headers(),
      ),
      expected: {200},
    );
  }

  /// 로그인 고객에게 속한 주문의 실제 배송·픽업 상태를 조회합니다.
  Future<Map<String, dynamic>> getTracking(int orderId) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/orders/$orderId/tracking'),
      headers: await _headers(),
    );
    return _decode(response, expected: {200}) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getReturns() async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/returns'),
      headers: await _headers(),
    );
    return (_decode(response, expected: {200}) as List)
        .cast<Map<String, dynamic>>();
  }

  /// 반품 수량에 배분된 환불액과 포인트를 서버 기준으로 조회합니다.
  Future<Map<String, dynamic>> getReturnQuote(int returnId) async {
    return _decode(
          await _client.get(
            Uri.parse('$_baseUrl/returns/$returnId/quote'),
            headers: await _headers(),
          ),
          expected: {200},
        )
        as Map<String, dynamic>;
  }

  /// 전체 주문 반품을 접수하며 검수·환불은 직원 승인 후 처리됩니다.
  Future<void> requestReturn(
    StoreOrder order,
    String reason, {
    Map<String, int>? quantities,
  }) async {
    if (order.id == null) throw const ApiOrderException('서버 주문이 없습니다.');
    final response = await _client.post(
      Uri.parse('$_baseUrl/orders/${order.id}/returns'),
      headers: await _headers(),
      body: jsonEncode({
        'reason': reason,
        if (quantities != null)
          'items': quantities.entries
              .map((entry) => {'itemKey': entry.key, 'quantity': entry.value})
              .toList(),
        'unworn': true,
        'undamaged': true,
        'completePackaging': true,
      }),
    );
    _decode(response, expected: {201});
  }

  @override
  Future<int> getPointBalance() async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/points/wallet'),
      headers: await _headers(),
    );
    return (_decode(response, expected: {200})
            as Map<String, dynamic>)['balance']
        as int;
  }

  @override
  Future<List<CheckoutCoupon>> getCoupons() async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/coupons'),
      headers: await _headers(),
    );
    return (_decode(response, expected: {200}) as List).map((value) {
      final json = value as Map<String, dynamic>;
      return CheckoutCoupon(
        id: json['id'] as int,
        name: json['name'] as String,
        type: json['discountType'] as String,
        value: json['discountValue'] as int,
        minimum: json['minimumOrderAmount'] as int,
        maximum: json['maximumDiscountAmount'] as int?,
      );
    }).toList();
  }

  static Future<String> _firebaseIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const ApiOrderException('주문하려면 먼저 로그인해주세요.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const ApiOrderException('로그인 인증 정보를 가져오지 못했습니다.');
    }
    return token;
  }

  String _key(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

  Future<Map<String, String>> _headers() async => {
    'Authorization': 'Bearer ${await _idTokenProvider()}',
    'Content-Type': 'application/json; charset=utf-8',
  };

  dynamic _decode(http.Response response, {required Set<int> expected}) {
    final decoded = response.bodyBytes.isEmpty
        ? null
        : jsonDecode(utf8.decode(response.bodyBytes));
    if (!expected.contains(response.statusCode)) {
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      throw ApiOrderException(
        detail is String ? detail : '주문 처리 실패 (${response.statusCode})',
      );
    }
    return decoded;
  }

  @override
  Future<List<PickupBranch>> getPickupBranches() async {
    final response = await _client.get(Uri.parse('$_baseUrl/branches/pickup'));
    final decoded = _decode(response, expected: {200});
    if (decoded is! List) {
      throw const ApiOrderException('대리점 응답 형식이 올바르지 않습니다.');
    }
    return decoded
        .map((value) => value as Map<String, dynamic>)
        .map(
          (json) => PickupBranch(
            id: json['branchId'] as int,
            code: json['branchCode'] as String,
            name: json['branchName'] as String,
            districtCode: json['districtCode'] as String,
            districtName: json['districtName'] as String,
            address: json['address'] as String,
            phone: json['phone'] as String,
            businessHours: (json['businessHours'] as List? ?? [])
                .cast<Map<String, dynamic>>(),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<StoreOrder>> getOrders() async {
    // 비로그인 상태에서도 상품 목록은 조회할 수 있습니다.
    if (_idTokenProvider == _firebaseIdToken &&
        FirebaseAuth.instance.currentUser == null) {
      return const [];
    }
    final response = await _client.get(
      Uri.parse('$_baseUrl/orders'),
      headers: await _headers(),
    );
    final decoded = _decode(response, expected: {200}) as List;
    return decoded
        .map((value) => _orderFromJson(value as Map<String, dynamic>))
        .toList();
  }

  /// 주문 당시 가격·상품명으로 상세를 구성하여 현재 상품 변경을 반영하지 않습니다.
  StoreOrder _orderFromJson(Map<String, dynamic> json) => StoreOrder(
    id: json['orderId'] as int,
    number: json['orderNumber'] as String,
    date: DateTime.parse(json['orderedAt'] as String),
    district: json['district'] as String,
    status: json['orderStatus'] as String,
    purchaseConfirmed: json['purchaseConfirmed'] as bool? ?? false,
    canceled: json['orderStatus'] == 'CANCELED',
    paidTotal: json['paidTotal'] as int,
    couponDiscount: json['couponDiscount'] as int,
    pointsUsed: json['pointsUsed'] as int,
    items: (json['items'] as List)
        .map((value) {
          final item = value as Map<String, dynamic>;
          return CartItem(
            product: Product(
              id: item['productId'] as int,
              name: item['name'] as String,
              category: '',
              price: item['unitPrice'] as int,
              imageUrl: item['imageUrl'] as String,
              color: item['color'] as String,
              gender: '',
            ),
            color: item['color'] as String,
            size: item['size'] as String,
            quantity: item['quantity'] as int,
          );
        })
        .toList(growable: false),
  );

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
    if (couponDiscount != 0 && customerCouponId == null) {
      throw const ApiOrderException('할인에 사용할 쿠폰을 선택해주세요.');
    }
    final branches = await getPickupBranches();
    final branch = branches
        .where((item) => item.districtName == district)
        .firstOrNull;
    if (branch == null) throw const ApiOrderException('선택한 지역의 픽업 대리점이 없습니다.');

    final optionCache = <int, List<ProductOption>>{};
    final requestItems = <Map<String, int>>[];
    for (final item in items) {
      final options = optionCache[item.product.id] ??= await productsRepository
          .getProductOptions(item.product.id);
      final option = options
          .where(
            (value) =>
                value.color == item.color &&
                value.size == item.size &&
                value.isAvailable,
          )
          .firstOrNull;
      if (option == null) {
        throw ApiOrderException(
          '${item.product.name} ${item.color} ${item.size} 재고가 없습니다.',
        );
      }
      requestItems.add({
        'productVariantId': option.productVariantId,
        'quantity': item.quantity,
      });
    }

    final headers = await _headers();
    final reserveResponse = await _client.post(
      Uri.parse('$_baseUrl/orders/reserve'),
      headers: headers,
      body: jsonEncode({
        'pickupBranchId': branch.id,
        'idempotencyKey': _key('flutter-order'),
        'items': requestItems,
      }),
    );
    final reserved =
        _decode(reserveResponse, expected: {201}) as Map<String, dynamic>;
    final orderId = reserved['orderId'] as int;

    final paymentResponse = await _client.post(
      Uri.parse('$_baseUrl/orders/$orderId/payments/complete'),
      headers: headers,
      body: jsonEncode({
        'paymentMethod': switch (paymentMethod) {
          '카카오페이' => 'KAKAO_PAY',
          '네이버페이' => 'NAVER_PAY',
          _ => 'CARD',
        },
        'transactionKey': _key('flutter-payment'),
        'customerCouponId': customerCouponId,
        'pointsUsed': pointsUsed,
      }),
    );
    final paid =
        _decode(paymentResponse, expected: {200}) as Map<String, dynamic>;
    return StoreOrder(
      id: orderId,
      number: paid['orderNumber'] as String,
      items: List.unmodifiable(items),
      date: DateTime.now(),
      district: district,
      paidTotal: paid['paidTotal'] as int? ?? paidTotal,
      couponDiscount: paid['couponDiscount'] as int? ?? couponDiscount,
      pointsUsed: paid['pointsUsed'] as int? ?? pointsUsed,
      status: paid['orderStatus'] as String,
    );
  }

  @override
  Future<StoreOrder> cancelOrder(StoreOrder order) async {
    if (order.id == null) throw const ApiOrderException('서버 주문 번호가 없습니다.');
    final response = await _client.post(
      Uri.parse('$_baseUrl/orders/${order.id}/cancel'),
      headers: await _headers(),
      body: jsonEncode({'reason': '고객 주문 취소'}),
    );
    final decoded = _decode(response, expected: {200}) as Map<String, dynamic>;
    return StoreOrder(
      id: order.id,
      number: order.number,
      items: order.items,
      date: order.date,
      district: order.district,
      canceled: decoded['orderStatus'] == 'CANCELED',
      paidTotal: order.paidTotal,
      couponDiscount: order.couponDiscount,
      pointsUsed: order.pointsUsed,
      status: decoded['orderStatus'] as String,
    );
  }
}

class ApiOrderException implements Exception {
  const ApiOrderException(this.message);

  final String message;

  @override
  String toString() => message;
}
