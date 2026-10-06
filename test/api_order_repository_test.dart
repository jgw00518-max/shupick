import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shupick/data/api_order_repository.dart';
import 'package:shupick/domain/models.dart';
import 'package:shupick/domain/repositories.dart';

void main() {
  test('서버 주문의 당시 가격과 상태를 인증된 내역으로 복원한다', () async {
    final repository = ApiOrderRepository(
      productsRepository: _ProductRepository(),
      baseUrl: 'http://example.test',
      idTokenProvider: () async => 'token',
      client: MockClient((request) async {
        expect(request.url.path, '/orders');
        expect(request.headers['authorization'], 'Bearer token');
        return _jsonResponse([
          {
            'orderId': 41,
            'orderNumber': 'ORD-HISTORY',
            'orderStatus': 'READY_FOR_PICKUP',
            'orderedAt': '2026-10-02T10:00:00',
            'district': '성동구',
            'paidTotal': 20000,
            'couponDiscount': 0,
            'pointsUsed': 0,
            'items': [
              {
                'productId': 1,
                'name': '주문 당시 상품',
                'unitPrice': 10000,
                'imageUrl': '',
                'color': '블랙',
                'size': '250',
                'quantity': 2,
              },
            ],
          },
        ]);
      }),
    );
    final orders = await repository.getOrders();
    expect(orders.single.status, 'READY_FOR_PICKUP');
    expect(orders.single.items.single.total, 20000);
    expect(orders.single.items.single.product.name, '주문 당시 상품');
  });
  test('선택 옵션을 SKU로 변환해 예약 후 결제를 확정한다', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      switch (request.url.path) {
        case '/branches/pickup':
          return _jsonResponse([
            {
              'branchId': 1,
              'branchCode': 'SEL-SD',
              'branchName': 'SHOEPICK 성동점',
              'districtCode': 'SEOUL-SEONGDONG',
              'districtName': '성동구',
              'address': '서울특별시 성동구 테스트로 10',
              'phone': '02-0000-0001',
            },
          ]);
        case '/orders/reserve':
          return _jsonResponse({
            'orderId': 41,
            'orderNumber': 'ORD-TEST',
            'orderStatus': 'PENDING_PAYMENT',
            'reservedQuantity': 2,
            'paymentId': null,
            'fulfillmentId': null,
          }, statusCode: 201);
        case '/orders/41/payments/complete':
          return _jsonResponse({
            'orderId': 41,
            'orderNumber': 'ORD-TEST',
            'orderStatus': 'PAID',
            'reservedQuantity': 2,
            'paymentId': 7,
            'fulfillmentId': 9,
          });
        default:
          throw StateError('Unexpected request: ${request.url}');
      }
    });
    final product = _product;
    final repository = ApiOrderRepository(
      productsRepository: _ProductRepository(),
      client: client,
      baseUrl: 'http://example.test',
      idTokenProvider: () async => 'firebase-token',
    );

    final order = await repository.createOrder(
      [CartItem(product: product, size: '250', color: '블랙', quantity: 2)],
      '성동구',
      paidTotal: 258000,
      couponDiscount: 0,
      pointsUsed: 0,
      paymentMethod: '카드',
    );

    expect(order.id, 41);
    expect(order.status, 'PAID');
    final reserveBody = jsonDecode(requests[1].body) as Map<String, dynamic>;
    expect(reserveBody['pickupBranchId'], 1);
    expect(reserveBody['items'], [
      {'productVariantId': 11, 'quantity': 2},
    ]);
    expect(requests[1].headers['authorization'], 'Bearer firebase-token');
  });

  test('쿠폰 식별자 없이 요청한 할인은 차단한다', () async {
    final repository = ApiOrderRepository(
      productsRepository: _ProductRepository(),
      client: MockClient((_) async => throw StateError('should not call')),
      baseUrl: 'http://example.test',
      idTokenProvider: () async => 'token',
    );

    expect(
      repository.createOrder(
        [CartItem(product: _product, size: '250', color: '블랙')],
        '성동구',
        paidTotal: 124000,
        couponDiscount: 5000,
        pointsUsed: 0,
        paymentMethod: '카드',
      ),
      throwsA(isA<ApiOrderException>()),
    );
  });
}

http.Response _jsonResponse(Object body, {int statusCode = 200}) =>
    http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

const _product = Product(
  id: 1,
  name: 'Silver Current',
  category: '신발',
  price: 129000,
  imageUrl: 'shoe.jpg',
  color: '블랙',
  gender: '남성',
  images: {'블랙': 'shoe.jpg'},
);

class _ProductRepository implements ProductRepository {
  @override
  Future<List<Product>> getProducts() async => const [_product];

  @override
  Future<List<ProductOption>> getProductOptions(int productId) async => const [
    ProductOption(
      productVariantId: 11,
      productCode: 'NK-M-SN-0001-BLK-250',
      color: '블랙',
      size: '250',
      availableQuantity: 10,
      inventoryStatus: 'AVAILABLE',
    ),
  ];
}
