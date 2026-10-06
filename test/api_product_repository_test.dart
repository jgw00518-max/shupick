import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shupick/data/api_product_repository.dart';

void main() {
  test('추천 응답의 한글 상품과 서버 순서·공동 조회 여부를 변환한다', () async {
    final repository = ApiProductRepository(
      baseUrl: 'http://test',
      client: MockClient((request) async {
        expect(request.url.path, '/products/91/recommendations');
        final product = {
          'name': '추천 러너',
          'category': '스포츠',
          'price': 89000,
          'imageUrl': '',
          'color': '블랙',
          'gender': '공용',
          'middleCategory': '스포츠',
          'subcategory': '러닝화',
          'images': <String, String>{},
          'reviewCount': 0,
          'salesCount': 0,
        };
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'products': [
                {...product, 'id': 300},
                {...product, 'id': 200},
              ],
              'coViewedProductIds': [300],
            }),
          ),
          200,
        );
      }),
    );
    final result = await repository.getRecommendations(91);
    expect(result.products.map((p) => p.id), [300, 200]);
    expect(result.products.first.name, '추천 러너');
    expect(result.coViewedProductIds, {300});
    expect(result.hasCustomerViews, isTrue);
  });

  test('추천 API 오류를 전달하여 상위 계층에서 유사 상품으로 대체할 수 있다', () async {
    final repository = ApiProductRepository(
      baseUrl: 'http://test',
      client: MockClient((_) async => http.Response('unavailable', 503)),
    );
    expect(
      repository.getRecommendations(91),
      throwsA(isA<ApiProductException>()),
    );
  });

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
