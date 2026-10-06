import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shupick/data/firebase_account_repository.dart';

class _User extends Fake implements User {
  @override
  String get uid => 'test-customer-uid';
  @override
  String get email => 'shupicktest01@example.com';
  @override
  String? get displayName => null;
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => 'test-token';
}

class _Auth extends Fake implements FirebaseAuth {
  _Auth(this.currentUser);
  @override
  final User? currentUser;
  @override
  Stream<User?> authStateChanges() => Stream.value(currentUser);
}

void main() {
  test('기존 Firebase 세션은 MySQL 연결 후 복원하고 반복 실행시 중복 생성하지 않는다', () async {
    var linked = false;
    var writes = 0;
    final repository = FirebaseAccountRepository(
      firebaseAuth: _Auth(_User()),
      baseUrl: 'http://test',
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-token');
        if (request.url.path == '/auth/me') {
          return http.Response('{}', linked ? 200 : 404);
        }
        expect(request.method, 'POST');
        expect(request.url.path, '/auth/customer/sync');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['ensureOnly'], isTrue);
        expect(body['customerName'], 'shupicktest01');
        expect(body.containsKey('phone'), isFalse);
        writes++;
        linked = true;
        return http.Response('{}', 200);
      }),
    );
    expect(await repository.restoreSession(), isTrue);
    expect(await repository.restoreSession(), isTrue);
    expect(writes, 1);
  });

  test('로그인 없는 세션에서는 서버를 호출하지 않는다', () async {
    final repository = FirebaseAccountRepository(
      firebaseAuth: _Auth(null),
      client: MockClient((_) async => throw StateError('Unexpected request')),
    );
    expect(await repository.restoreSession(), isFalse);
  });

  test('회원 확인이 인증 오류이면 재등록하지 않고 실패를 전달한다', () async {
    var calls = 0;
    final repository = FirebaseAccountRepository(
      firebaseAuth: _Auth(_User()),
      client: MockClient((request) async {
        calls++;
        expect(request.method, 'GET');
        return http.Response('{}', 401);
      }),
    );
    await expectLater(repository.restoreSession(), throwsStateError);
    expect(calls, 1);
  });

  test('회원 연결 실패는 복원 성공으로 처리하지 않는다', () async {
    final repository = FirebaseAccountRepository(
      firebaseAuth: _Auth(_User()),
      client: MockClient(
        (request) async =>
            http.Response('{}', request.method == 'GET' ? 404 : 409),
      ),
    );
    await expectLater(repository.restoreSession(), throwsStateError);
  });
}
