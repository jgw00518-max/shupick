import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/models.dart';
import '../domain/repositories.dart';

/// 실행 플랫폼에 맞는 개발 API 주소를 선택하고 dart-define 재정의를 허용합니다.
String get defaultApiBaseUrl {
  const override = String.fromEnvironment('API_BASE_URL');
  if (override.isNotEmpty) return override;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000';
  }
  return 'http://127.0.0.1:8000';
}

/// FastAPI 상품 JSON을 앱의 상품·옵션 모델로 변환합니다.
class ApiProductRepository
    implements
        ProductRepository,
        CatalogRepository,
        ProductRecommendationRepository {
  ApiProductRepository({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = (baseUrl ?? defaultApiBaseUrl).replaceFirst(RegExp(r'/$'), '');

  final http.Client _client;
  final String _baseUrl;

  @override
  Future<ProductRecommendations> getRecommendations(int productId) async {
    final response = await _client
        .get(Uri.parse('$_baseUrl/products/$productId/recommendations'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw ApiProductException('추천 상품 조회 실패 (${response.statusCode})');
    }
    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return ProductRecommendations(
      products: (json['products'] as List)
          .map((item) => _productFromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      coViewedProductIds: (json['coViewedProductIds'] as List)
          .cast<int>()
          .toSet(),
    );
  }

  @override
  Future<CatalogMetadata> getCatalog() async {
    final response = await _client.get(Uri.parse('$_baseUrl/catalog'));
    if (response.statusCode != 200) {
      throw ApiProductException('분류 조회 실패 (${response.statusCode})');
    }
    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return CatalogMetadata(
      categories: (json['categoryTree'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, (value as List).cast<String>()),
      ),
      brands: {
        for (final brand in json['brands'] as List)
          brand['brand_name'] as String: (brand['productIds'] as List)
              .cast<int>(),
      },
    );
  }

  @override
  Future<List<Product>> getProducts() async {
    final response = await _client.get(Uri.parse('$_baseUrl/products'));
    if (response.statusCode != 200) {
      throw ApiProductException('상품 조회 실패 (${response.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) {
      throw const ApiProductException('상품 응답 형식이 올바르지 않습니다.');
    }
    return decoded
        .map((item) => _productFromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<List<ProductOption>> getProductOptions(int productId) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/products/$productId/options'),
    );
    if (response.statusCode != 200) {
      throw ApiProductException('상품 옵션 조회 실패 (${response.statusCode})');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) {
      throw const ApiProductException('상품 옵션 응답 형식이 올바르지 않습니다.');
    }
    return decoded
        .map((item) => _productOptionFromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Product _productFromJson(Map<String, dynamic> json) => Product(
    id: json['id'] as int,
    name: json['name'] as String,
    category: json['category'] as String,
    price: json['price'] as int,
    imageUrl: json['imageUrl'] as String,
    color: json['color'] as String,
    gender: json['gender'] as String,
    middleCategory: json['middleCategory'] as String,
    subcategory: json['subcategory'] as String,
    images: (json['images'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, value as String),
    ),
    reviewCount: json['reviewCount'] as int,
    salesCount: json['salesCount'] as int,
  );

  ProductOption _productOptionFromJson(Map<String, dynamic> json) =>
      ProductOption(
        productVariantId: json['productVariantId'] as int,
        productCode: json['productCode'] as String,
        color: json['color'] as String,
        size: json['size'] as String,
        availableQuantity: json['availableQuantity'] as int,
        inventoryStatus: json['inventoryStatus'] as String,
      );
}

class ApiProductException implements Exception {
  const ApiProductException(this.message);

  final String message;

  @override
  String toString() => message;
}
