import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;

import 'api_product_repository.dart';

typedef KakaoAccessTokenProvider = Future<String?> Function();
typedef SocialBrowserAuth =
    Future<String> Function(String url, String callbackScheme);

/// Provider credentials are exchanged on the backend, not used as Firebase IDs.
abstract interface class SocialLoginClient {
  Future<String?> kakaoCustomToken();
  Future<String?> naverCustomToken();
  Future<void> signOut();
}

class NativeSocialLoginClient implements SocialLoginClient {
  factory NativeSocialLoginClient({
    http.Client? client,
    String? baseUrl,
    String? kakaoNativeAppKey,
    KakaoAccessTokenProvider? kakaoAccessToken,
    SocialBrowserAuth? browserAuth,
  }) => NativeSocialLoginClient._(
    client ?? http.Client(),
    (baseUrl ?? defaultApiBaseUrl).replaceFirst(RegExp(r'/$'), ''),
    kakaoNativeAppKey ?? const String.fromEnvironment('KAKAO_NATIVE_APP_KEY'),
    kakaoAccessToken,
    browserAuth,
  );

  NativeSocialLoginClient._(
    this._client,
    this._baseUrl,
    this._kakaoNativeAppKey,
    this._kakaoAccessToken,
    this._browserAuth,
  );

  static const callbackScheme = 'com.example.shupick.auth';
  static const _networkTimeout = Duration(seconds: 15);
  static const _loginTimeout = Duration(minutes: 3);

  final http.Client _client;
  final String _baseUrl;
  final String _kakaoNativeAppKey;
  final KakaoAccessTokenProvider? _kakaoAccessToken;
  final SocialBrowserAuth? _browserAuth;
  bool _kakaoSdkInitialized = false;

  @override
  Future<String?> kakaoCustomToken() async {
    if (_kakaoAccessToken == null) {
      _requireNativePlatform();
      if (_kakaoNativeAppKey.trim().isEmpty) {
        throw StateError('카카오 로그인 앱 키 설정을 먼저 완료해주세요.');
      }
    }
    String? accessToken;
    try {
      accessToken = await (_kakaoAccessToken ?? _nativeKakaoAccessToken)()
          .timeout(_loginTimeout);
    } catch (error) {
      if (_isKakaoCancellation(error)) return null;
      if (error is TimeoutException) {
        throw StateError('카카오 로그인 시간이 초과되었습니다. 다시 시도해주세요.');
      }
      throw StateError('카카오 로그인을 완료하지 못했습니다. 다시 시도해주세요.');
    }
    if (accessToken == null) return null;
    if (accessToken.trim().isEmpty) {
      throw StateError('카카오 인증 정보를 확인하지 못했습니다.');
    }
    final response = await _post('/auth/social/kakao', {
      'accessToken': accessToken,
    });
    return _customToken(response);
  }

  Future<String?> _nativeKakaoAccessToken() async {
    if (!_kakaoSdkInitialized) {
      await kakao.KakaoSdk.init(
        nativeAppKey: _kakaoNativeAppKey,
        loggingEnabled: false,
      );
      _kakaoSdkInitialized = true;
    }
    if (await kakao.isKakaoTalkInstalled()) {
      try {
        return (await kakao.UserApi.instance.loginWithKakaoTalk()).accessToken;
      } catch (error) {
        // An intentional cancellation must never open another login screen.
        if (_isKakaoCancellation(error)) return null;
        // The installed app may lack a logged-in Kakao account; use the
        // official account-browser fallback, while surfacing its failures.
      }
    }
    return (await kakao.UserApi.instance.loginWithKakaoAccount()).accessToken;
  }

  static bool _isKakaoCancellation(Object error) =>
      (error is PlatformException && error.code == 'CANCELED') ||
      (error is kakao.KakaoClientException &&
          error.reason == kakao.ClientErrorCause.cancelled);

  @override
  Future<String?> naverCustomToken() async {
    if (_browserAuth == null) _requireNativePlatform();
    // The verifier remains in this call's memory and is never put in a URL.
    final verifier = _randomVerifier();
    final challenge = _withoutPadding(
      base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes),
    );
    final start = await _post('/auth/social/naver/start', {
      'challenge': challenge,
    });
    final state = start['state'];
    final authorizationUrl = start['authorizationUrl'];
    if (state is! String ||
        state.isEmpty ||
        state.length > 256 ||
        authorizationUrl is! String ||
        !_isNaverAuthorizationUrl(authorizationUrl, state)) {
      throw StateError('네이버 로그인 서버 응답을 확인하지 못했습니다.');
    }

    String callbackUrl;
    try {
      callbackUrl = await (_browserAuth ?? _nativeBrowserAuth)(
        authorizationUrl,
        callbackScheme,
      ).timeout(_loginTimeout);
    } on PlatformException catch (error) {
      if (error.code == 'CANCELED') return null;
      throw StateError('네이버 로그인 화면을 열지 못했습니다. 다시 시도해주세요.');
    } on TimeoutException {
      throw StateError('네이버 로그인 시간이 초과되었습니다. 다시 시도해주세요.');
    } catch (_) {
      throw StateError('네이버 로그인을 완료하지 못했습니다. 다시 시도해주세요.');
    }
    final callback = Uri.tryParse(callbackUrl);
    if (callback == null ||
        callback.scheme != callbackScheme ||
        callback.host != 'naver' ||
        callback.userInfo.isNotEmpty ||
        callback.hasPort ||
        callback.hasFragment ||
        (callback.path.isNotEmpty && callback.path != '/') ||
        _singleQueryValue(callback, 'state') != state) {
      throw StateError('네이버 로그인 요청을 확인하지 못했습니다. 다시 시도해주세요.');
    }
    final error = _singleQueryValue(callback, 'error');
    if (error != null) {
      if (error == 'access_denied' ||
          error == 'cancelled' ||
          error == 'canceled') {
        return null;
      }
      throw StateError('네이버 인증을 완료하지 못했습니다. 다시 시도해주세요.');
    }
    if (callback.queryParametersAll.containsKey('error')) {
      throw StateError('네이버 로그인 요청을 확인하지 못했습니다. 다시 시도해주세요.');
    }
    final complete = await _post('/auth/social/naver/complete', {
      'state': state,
      'verifier': verifier,
    });
    return _customToken(complete);
  }

  static String _randomVerifier() {
    final random = Random.secure();
    return _withoutPadding(
      base64Url.encode(List<int>.generate(32, (_) => random.nextInt(256))),
    );
  }

  static String _withoutPadding(String value) => value.replaceAll('=', '');

  static String? _singleQueryValue(Uri uri, String key) {
    final values = uri.queryParametersAll[key];
    if (values == null || values.length != 1 || values.first.isEmpty) {
      return null;
    }
    return values.first;
  }

  static bool _isNaverAuthorizationUrl(String value, String state) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'nid.naver.com' ||
        uri.path != '/oauth2/authorize' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        uri.hasFragment ||
        _singleQueryValue(uri, 'state') != state ||
        _singleQueryValue(uri, 'response_type') != 'code') {
      return false;
    }
    return !const {
      'access_token',
      'refresh_token',
      'id_token',
      'customToken',
      'client_secret',
    }.any(uri.queryParametersAll.containsKey);
  }

  static Future<String> _nativeBrowserAuth(String url, String scheme) =>
      FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: scheme);

  static void _requireNativePlatform() {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      throw StateError('카카오·네이버 로그인은 Android 또는 iOS 앱에서 사용해주세요.');
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, String> body,
  ) async {
    http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(body),
          )
          .timeout(_networkTimeout);
    } catch (_) {
      throw StateError('로그인 서버에 연결하지 못했습니다. 서버 상태를 확인해주세요.');
    }
    // Do not surface response bodies, credentials, or provider SDK messages.
    switch (response.statusCode) {
      case 503:
        throw StateError('소셜 로그인 서버 설정을 먼저 완료해주세요.');
      case 401:
        throw StateError('소셜 인증을 확인하지 못했습니다. 다시 로그인해주세요.');
      case 409:
        throw StateError('회원 계정 상태를 확인해주세요. 관리자에게 문의해주세요.');
      case 429:
        throw StateError('로그인 요청이 많습니다. 잠시 후 다시 시도해주세요.');
    }
    if (response.statusCode != 200) {
      throw StateError('소셜 로그인을 완료하지 못했습니다. 다시 시도해주세요.');
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // A malformed upstream response must not reveal its contents.
    }
    throw StateError('소셜 로그인 서버 응답을 확인하지 못했습니다.');
  }

  static String _customToken(Map<String, dynamic> response) {
    final token = response['customToken'];
    if (token is! String || token.trim().isEmpty) {
      throw StateError('회원 인증 정보를 확인하지 못했습니다.');
    }
    return token;
  }

  @override
  Future<void> signOut() async {
    if (!_kakaoSdkInitialized) return;
    try {
      await kakao.UserApi.instance.logout().timeout(_networkTimeout);
    } catch (_) {
      // Firebase sign-out is handled by the account repository independently.
    }
  }
}
