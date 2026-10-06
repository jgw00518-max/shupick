import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shupick/data/api_review_repository.dart';
import 'package:shupick/domain/models.dart';

void main() {
  test('리뷰 조회와 수정 요청은 인증 및 구매 항목 식별자를 유지한다', () async {
    final requests = <http.Request>[];
    final repository = ApiReviewRepository(
      baseUrl: 'http://test',
      tokenProvider: () async => 'token',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(
            request.method == 'GET'
                ? [
                    {
                      'id': 12,
                      'orderNumber': 'ORD-1',
                      'itemKey': '1-250-블랙',
                      'rating': 4,
                      'content': '후기',
                      'fitSize': '정사이즈',
                      'fitWidth': '적당함',
                      'fitComfort': '편함',
                      'photos': ['photo'],
                    },
                  ]
                : {'id': 1},
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final reviews = await repository.getReviews();
    expect(reviews.single.id, 12);
    expect(reviews.single.photos, ['photo']);
    await repository.updateReview(reviews.single);
    expect(requests.last.headers['authorization'], 'Bearer token');
    expect(jsonDecode(requests.last.body)['itemKey'], '1-250-블랙');
  });
  test('서버 중복 작성 오류는 호출자에게 전달된다', () async {
    final repository = ApiReviewRepository(
      baseUrl: 'http://test',
      tokenProvider: () async => 'token',
      client: MockClient(
        (_) async => http.Response('{"detail":"duplicate"}', 409),
      ),
    );
    expect(
      repository.addReview(
        const ProductReview(
          orderNumber: 'ORD',
          itemKey: 'key',
          rating: 5,
          content: '후기',
        ),
      ),
      throwsStateError,
    );
  });
}
