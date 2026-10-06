import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:shupick/data/social_login_client.dart';

http.Response jsonResponse(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

const state = 'synthetic-naver-state';
String authorizeUrl([String currentState = state]) =>
    Uri.https('nid.naver.com', '/oauth2/authorize', {
      'client_id': 'public-test-client-id',
      'response_type': 'code',
      'state': currentState,
      'scope': 'openid',
    }).toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Kakao exchanges access token through JSON POST without native plugins',
    () async {
      final client = NativeSocialLoginClient(
        baseUrl: 'http://test/',
        kakaoAccessToken: () async => 'synthetic-kakao-access-token',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.toString(), 'http://test/auth/social/kakao');
          expect(request.url.query, isEmpty);
          expect(jsonDecode(request.body), {
            'accessToken': 'synthetic-kakao-access-token',
          });
          expect(request.headers['content-type'], contains('application/json'));
          return jsonResponse({
            'customToken': 'synthetic-firebase-custom-token',
          });
        }),
      );
      expect(
        await client.kakaoCustomToken(),
        'synthetic-firebase-custom-token',
      );
      await client.signOut();
    },
  );

  test('Kakao cancellation does not exchange credentials', () async {
    for (final cancel in [
      PlatformException(code: 'CANCELED', message: 'synthetic-private-message'),
      kakao.KakaoClientException(
        kakao.ClientErrorCause.cancelled,
        'synthetic-private-message',
      ),
    ]) {
      final client = NativeSocialLoginClient(
        kakaoAccessToken: () async => throw cancel,
        client: MockClient((_) async => fail('No request after cancellation')),
      );
      expect(await client.kakaoCustomToken(), isNull);
    }
  });

  test('null access token is a cancellation; an empty token is not', () async {
    final canceled = NativeSocialLoginClient(
      kakaoAccessToken: () async => null,
      client: MockClient((_) async => fail('No request after cancellation')),
    );
    expect(await canceled.kakaoCustomToken(), isNull);
    final invalid = NativeSocialLoginClient(kakaoAccessToken: () async => '');
    await expectLater(invalid.kakaoCustomToken(), throwsStateError);
  });

  test('non-cancellation SDK failures surface a sanitized error', () async {
    final client = NativeSocialLoginClient(
      kakaoAccessToken: () async => throw PlatformException(
        code: 'BAD_CONFIGURATION',
        message: 'synthetic-private-key',
      ),
      client: MockClient((_) async => fail('No request after SDK failure')),
    );
    await expectLater(
      client.kakaoCustomToken(),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'safe message',
          isNot(contains('synthetic-private-key')),
        ),
      ),
    );
  });

  test('missing Kakao key fails before calling native SDK', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final client = NativeSocialLoginClient(kakaoNativeAppKey: '');
    await expectLater(
      client.kakaoCustomToken(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'configuration message',
          contains('앱 키 설정'),
        ),
      ),
    );
  });

  test(
    'NAVER uses random verifier, SHA256 challenge and app-state-bound POST completion',
    () async {
      String? sentChallenge;
      var requestCount = 0;
      final client = NativeSocialLoginClient(
        baseUrl: 'http://test',
        browserAuth: (url, scheme) async {
          expect(url, authorizeUrl());
          expect(scheme, NativeSocialLoginClient.callbackScheme);
          expect(url, isNot(contains('client_secret')));
          return '$scheme://naver?state=$state';
        },
        client: MockClient((request) async {
          requestCount++;
          expect(request.method, 'POST');
          expect(request.url.query, isEmpty);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (request.url.path.endsWith('/start')) {
            expect(body.keys, ['challenge']);
            sentChallenge = body['challenge'] as String;
            expect(sentChallenge, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
            return jsonResponse({
              'state': state,
              'authorizationUrl': authorizeUrl(),
            });
          }
          expect(request.url.path, '/auth/social/naver/complete');
          expect(body.keys.toSet(), {'state', 'verifier'});
          expect(body['state'], state);
          final verifier = body['verifier'] as String;
          expect(verifier, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
          expect(
            base64Url
                .encode(sha256.convert(ascii.encode(verifier)).bytes)
                .replaceAll('=', ''),
            sentChallenge,
          );
          return jsonResponse({
            'customToken': 'synthetic-naver-firebase-token',
          });
        }),
      );
      expect(await client.naverCustomToken(), 'synthetic-naver-firebase-token');
      expect(requestCount, 2);
    },
  );

  test('NAVER verifier and challenge are fresh for each attempt', () async {
    final challenges = <String>[];
    final client = NativeSocialLoginClient(
      browserAuth: (_, scheme) async => '$scheme://naver?state=$state',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/start')) {
          challenges.add(
            (jsonDecode(request.body) as Map<String, dynamic>)['challenge']
                as String,
          );
          return jsonResponse({
            'state': state,
            'authorizationUrl': authorizeUrl(),
          });
        }
        return jsonResponse({'customToken': 'synthetic-custom-token'});
      }),
    );
    await client.naverCustomToken();
    await client.naverCustomToken();
    expect(challenges.toSet(), hasLength(2));
  });

  for (final callback in [
    'other.scheme://naver?state=$state',
    '${NativeSocialLoginClient.callbackScheme}://other?state=$state',
    '${NativeSocialLoginClient.callbackScheme}://naver?state=wrong-state',
    '${NativeSocialLoginClient.callbackScheme}://naver?state=$state&state=$state',
    '${NativeSocialLoginClient.callbackScheme}://naver?state=$state#fragment',
  ]) {
    test(
      'NAVER rejects unexpected callback $callback without token redemption',
      () async {
        final client = NativeSocialLoginClient(
          browserAuth: (_, _) async => callback,
          client: MockClient((request) async {
            expect(request.url.path, '/auth/social/naver/start');
            return jsonResponse({
              'state': state,
              'authorizationUrl': authorizeUrl(),
            });
          }),
        );
        await expectLater(client.naverCustomToken(), throwsStateError);
      },
    );
  }

  for (final url in [
    authorizeUrl().replaceFirst('https:', 'http:'),
    authorizeUrl().replaceFirst('nid.naver.com', 'nid.naver.com.evil.example'),
    authorizeUrl().replaceFirst('/oauth2/authorize', '/oauth2.0/authorize'),
    authorizeUrl('wrong-state'),
    '${authorizeUrl()}&client_secret=synthetic-secret',
  ]) {
    test('NAVER does not open an unexpected authorization URL $url', () async {
      final client = NativeSocialLoginClient(
        browserAuth: (_, _) async => fail('Untrusted URL must not be opened'),
        client: MockClient(
          (_) async => jsonResponse({'state': state, 'authorizationUrl': url}),
        ),
      );
      await expectLater(client.naverCustomToken(), throwsStateError);
    });
  }

  test('NAVER user cancellation returns null and does not complete', () async {
    for (final cancelBrowser in <SocialBrowserAuth>[
      (_, _) async => throw PlatformException(code: 'CANCELED'),
      (_, scheme) async => '$scheme://naver?state=$state&error=access_denied',
    ]) {
      final client = NativeSocialLoginClient(
        browserAuth: cancelBrowser,
        client: MockClient((request) async {
          expect(request.url.path, '/auth/social/naver/start');
          return jsonResponse({
            'state': state,
            'authorizationUrl': authorizeUrl(),
          });
        }),
      );
      expect(await client.naverCustomToken(), isNull);
    }
  });

  test(
    'NAVER provider and browser failures are not treated as cancellation',
    () async {
      for (final failedBrowser in <SocialBrowserAuth>[
        (_, scheme) async => '$scheme://naver?state=$state&error=server_error',
        (_, _) async => throw PlatformException(
          code: 'NO_BROWSER',
          message: 'synthetic-secret',
        ),
      ]) {
        final client = NativeSocialLoginClient(
          browserAuth: failedBrowser,
          client: MockClient((request) async {
            expect(request.url.path, '/auth/social/naver/start');
            return jsonResponse({
              'state': state,
              'authorizationUrl': authorizeUrl(),
            });
          }),
        );
        await expectLater(
          client.naverCustomToken(),
          throwsA(
            isA<StateError>().having(
              (error) => error.toString(),
              'safe message',
              isNot(contains('synthetic-secret')),
            ),
          ),
        );
      }
    },
  );

  for (final status in [401, 409, 503]) {
    test(
      'backend $status is surfaced without body or credential disclosure',
      () async {
        final client = NativeSocialLoginClient(
          kakaoAccessToken: () async => 'synthetic-provider-token',
          client: MockClient(
            (_) async => http.Response('synthetic-private-key', status),
          ),
        );
        await expectLater(
          client.kakaoCustomToken(),
          throwsA(
            isA<StateError>().having(
              (error) => error.toString(),
              'safe message',
              isNot(contains('synthetic-private-key')),
            ),
          ),
        );
      },
    );
  }

  test(
    'malformed backend response and missing custom token are rejected',
    () async {
      for (final response in [
        http.Response('not-json-secret', 200),
        jsonResponse({}),
      ]) {
        final client = NativeSocialLoginClient(
          kakaoAccessToken: () async => 'synthetic-token',
          client: MockClient((_) async => response),
        );
        await expectLater(client.kakaoCustomToken(), throwsStateError);
      }
    },
  );
}
