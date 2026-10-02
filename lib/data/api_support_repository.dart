import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../domain/models.dart';
import '../domain/repositories.dart';
import 'api_product_repository.dart';

/// 로그인 고객의 문의와 SKU별 재입고 신청을 서버에 저장합니다.
class ApiSupportRepository implements SupportRepository {
  ApiSupportRepository({
    http.Client? client,
    String? baseUrl,
    this.tokenProvider,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? defaultApiBaseUrl;
  final http.Client _client;
  final String _baseUrl;
  final Future<String> Function()? tokenProvider;
  bool get _guest =>
      tokenProvider == null && FirebaseAuth.instance.currentUser == null;
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
      throw StateError(json is Map ? '${json['detail']}' : '문의 처리 실패');
    }
    return json;
  }

  InquiryEntry _entry(Map<String, dynamic> json) => InquiryEntry(
    id: json['id'] as int,
    kind: json['kind'] as String,
    title: json['title'] as String,
    body: json['body'] as String,
    date: json['date'] as String,
    answer: json['answer'] as String?,
  );
  @override
  Future<List<InquiryEntry>> getInquiries() async {
    if (_guest) return [];
    final json =
        _decode(
              await _client.get(
                Uri.parse('$_baseUrl/inquiries'),
                headers: await _headers(),
              ),
            )
            as List;
    return json.map((row) => _entry(row as Map<String, dynamic>)).toList();
  }

  @override
  Future<InquiryEntry> createInquiry(
    String kind,
    String title,
    String body, {
    int? productId,
  }) async {
    final code = switch (kind) {
      '상품 문의' => 'PRODUCT',
      '배송 문의' => 'DELIVERY',
      '결제 문의' => 'PAYMENT',
      _ => 'OTHER',
    };
    return _entry(
      _decode(
            await _client.post(
              Uri.parse('$_baseUrl/inquiries'),
              headers: await _headers(),
              body: jsonEncode({
                'kind': code,
                'title': title,
                'body': body,
                'productId': productId,
              }),
            ),
          )
          as Map<String, dynamic>,
    );
  }

  @override
  Future<Set<String>> getRestockKeys() async {
    if (_guest) return {};
    return (_decode(
              await _client.get(
                Uri.parse('$_baseUrl/restock-subscriptions'),
                headers: await _headers(),
              ),
            )
            as List)
        .cast<String>()
        .toSet();
  }

  @override
  Future<void> saveRestockKeys(Set<String> keys) async {
    _decode(
      await _client.put(
        Uri.parse('$_baseUrl/restock-subscriptions'),
        headers: await _headers(),
        body: jsonEncode({'keys': keys.toList()}),
      ),
    );
  }
}
