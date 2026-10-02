import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shupick/data/api_product_repository.dart';

void main() {
  test('MySQL 분류와 브랜드별 상품 ID를 변환한다', () async {
    final repository = ApiProductRepository(
      baseUrl: 'http://test',
      client: MockClient((request) async {
        expect(request.url.path, '/catalog');
        return http.Response(
          jsonEncode({
            'categoryTree': {
              '운동화': ['러닝화'],
            },
            'brands': [
              {
                'brand_name': 'Nike',
                'productIds': [1, 2],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final catalog = await repository.getCatalog();
    expect(catalog.categories['운동화'], ['러닝화']);
    expect(catalog.brands['Nike'], [1, 2]);
  });
  test('API 상품 응답을 Product 목록으로 변환한다', () async {
    final client = MockClient(
      (_) async => http.Response(
        '''[{"id":1,"name":"Silver Current","category":"신발","price":129000,"imageUrl":"https://example.com/black.jpg","color":"블랙","gender":"남성","middleCategory":"운동화","subcategory":"운동화","images":{"블랙":"https://example.com/black.jpg"},"reviewCount":1,"salesCount":1}]''',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    final products = await ApiProductRepository(
      client: client,
      baseUrl: 'http://example.test',
    ).getProducts();

    expect(products, hasLength(1));
    expect(products.single.name, 'Silver Current');
    expect(products.single.colors, ['블랙']);
  });

  test('API 오류 상태를 예외로 전달한다', () async {
    final repository = ApiProductRepository(
      client: MockClient((_) async => http.Response('error', 503)),
      baseUrl: 'http://example.test',
    );

    expect(repository.getProducts(), throwsA(isA<ApiProductException>()));
  });

  test('API 상품 옵션 응답을 재고 모델로 변환한다', () async {
    final client = MockClient(
      (_) async => http.Response(
        '''[{"productVariantId":1,"productCode":"NK-M-SN-0001-BLK-250","color":"블랙","size":"250","availableQuantity":20,"inventoryStatus":"AVAILABLE"}]''',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    final options = await ApiProductRepository(
      client: client,
      baseUrl: 'http://example.test',
    ).getProductOptions(1);

    expect(options.single.productCode, 'NK-M-SN-0001-BLK-250');
    expect(options.single.availableQuantity, 20);
    expect(options.single.isAvailable, isTrue);
  });
}
