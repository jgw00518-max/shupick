import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../domain/models.dart';
import '../domain/repositories.dart';
import 'api_product_repository.dart';

/// 리뷰의 구매자 검증과 영구 저장을 MySQL API에 위임합니다.
class ApiReviewRepository implements ReviewRepository {
  ApiReviewRepository({
    http.Client? client,
    String? baseUrl,
    this.tokenProvider,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? defaultApiBaseUrl;
  final http.Client _client;
  final String _baseUrl;
  final Future<String> Function()? tokenProvider;

  /// 비회원도 고객 식별 정보 없이 구매확정 리뷰를 조회합니다.
  Future<Map<String, dynamic>> getProductReviews(
    int productId, {
    int offset = 0,
  }) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/reviews/products/$productId?offset=$offset'),
    );
    return _decode(response) as Map<String, dynamic>;
  }

  Future<Map<String, String>> _headers() async {
    final token = tokenProvider != null
        ? await tokenProvider!()
        : await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) throw StateError('로그인이 필요합니다.');
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  dynamic _decode(http.Response response) {
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(json is Map ? '${json['detail']}' : '리뷰 처리 실패');
    }
    return json;
  }

  Map<String, dynamic> _body(ProductReview review) => {
    'orderNumber': review.orderNumber,
    'itemKey': review.itemKey,
    'rating': review.rating,
    'content': review.content,
    'fitSize': review.fitSize,
    'fitWidth': review.fitWidth,
    'fitComfort': review.fitComfort,
    'photos': review.photos,
  };
  @override
  Future<List<ProductReview>> getReviews() async {
    if (tokenProvider == null && FirebaseAuth.instance.currentUser == null) {
      return [];
    }
    final response = await _client.get(
      Uri.parse('$_baseUrl/reviews'),
      headers: await _headers(),
    );
    return (_decode(response) as List)
        .map(
          (json) => ProductReview(
            id: (json['id'] as num?)?.toInt(),
            orderNumber: json['orderNumber'] as String,
            itemKey: json['itemKey'] as String,
            rating: json['rating'] as int,
            content: json['content'] as String,
            fitSize: json['fitSize'] as String? ?? '정사이즈',
            fitWidth: json['fitWidth'] as String? ?? '적당함',
            fitComfort: json['fitComfort'] as String? ?? '편함',
            photos: (json['photos'] as List).cast<String>(),
          ),
        )
        .toList();
  }

  @override
  Future<void> addReview(ProductReview review) async {
    _decode(
      await _client.post(
        Uri.parse('$_baseUrl/reviews'),
        headers: await _headers(),
        body: jsonEncode(_body(review)),
      ),
    );
  }

  @override
  Future<void> updateReview(ProductReview review) async {
    _decode(
      await _client.put(
        Uri.parse('$_baseUrl/reviews'),
        headers: await _headers(),
        body: jsonEncode(_body(review)),
      ),
    );
  }

  @override
  Future<void> deleteReview(ProductReview review) async {
    _decode(
      await _client.delete(
        Uri.parse('$_baseUrl/reviews'),
        headers: await _headers(),
        body: jsonEncode({
          'orderNumber': review.orderNumber,
          'itemKey': review.itemKey,
        }),
      ),
    );
  }
}
