import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../domain/repositories.dart';
import '../domain/customer_enrollment.dart';
import 'api_product_repository.dart';
import 'social_login_client.dart';

class FirebaseAccountRepository
    implements
        AccountRepository,
        SessionAccountRepository,
        IdentityAccountRepository,
        SocialAccountRepository,
        LoginProviderAccountRepository,
        EnrollmentAccountRepository {
  FirebaseAccountRepository({
    FirebaseAuth? firebaseAuth,
    http.Client? client,
    String? baseUrl,
    SocialLoginClient? socialLoginClient,
    GoogleSignIn? googleSignIn,
  }) : _auth = firebaseAuth ?? FirebaseAuth.instance,
       _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? defaultApiBaseUrl,
       _googleSignIn = googleSignIn ?? GoogleSignIn.instance,
       _socialLogin =
           socialLoginClient ??
           NativeSocialLoginClient(
             client: client,
             baseUrl: baseUrl ?? defaultApiBaseUrl,
           );

  final FirebaseAuth _auth;
  final http.Client _client;
  final String _baseUrl;
  final SocialLoginClient _socialLogin;
  final GoogleSignIn _googleSignIn;

  @override
  String? get enrollmentUserId => _auth.currentUser?.uid;

  Map<String, dynamic> _enrollmentBody(
    VerifiedPhone? phone,
    DateTime? birthDate,
  ) => {
    if (phone != null) 'phoneToken': phone.idToken,
    'phoneConsent': phone != null,
    'birthDate': birthDate == null
        ? null
        : '${birthDate.year.toString().padLeft(4, '0')}-${birthDate.month.toString().padLeft(2, '0')}-${birthDate.day.toString().padLeft(2, '0')}',
    'birthdayConsent': birthDate != null,
  };

  Future<Map<String, String>> _enrollmentHeaders() async {
    final user = _auth.currentUser;
    final token = await user?.getIdToken();
    if (user == null || token == null || _auth.currentUser?.uid != user.uid) {
      throw StateError('로그인 상태를 확인하고 다시 시도해주세요.');
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json; charset=utf-8',
    };
  }

  @override
  Future<EnrollmentProfile> getEnrollmentProfile() async {
    final uid = _auth.currentUser?.uid;
    final response = await _client
        .get(
          Uri.parse('$_baseUrl/auth/customer/enrollment'),
          headers: await _enrollmentHeaders(),
        )
        .timeout(const Duration(seconds: 10));
    if (_auth.currentUser?.uid != uid) throw StateError('계정이 변경되었습니다.');
    if (response.statusCode != 200) {
      throw StateError('추가 회원 정보를 불러오지 못했습니다. 서버와 DB 설정을 확인해주세요.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return EnrollmentProfile(
      phoneVerified: data['phoneVerified'] == true,
      maskedPhone: data['maskedPhone'] as String?,
      birthDate: DateTime.tryParse(data['birthDate'] as String? ?? ''),
    );
  }

  @override
  Future<void> saveEnrollment(VerifiedPhone? phone, DateTime? birthDate) async {
    if (phone?.expired == true) {
      throw StateError('휴대폰 인증 후 5분이 지났습니다. 다시 인증해주세요.');
    }
    final uid = _auth.currentUser?.uid;
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/auth/customer/enrollment'),
          headers: await _enrollmentHeaders(),
          body: jsonEncode(_enrollmentBody(phone, birthDate)),
        )
        .timeout(const Duration(seconds: 10));
    if (_auth.currentUser?.uid != uid) throw StateError('계정이 변경되었습니다.');
    if (response.statusCode == 401) {
      throw StateError('로그인 상태와 휴대폰 인증을 다시 확인해주세요.');
    }
    if (response.statusCode != 200) {
      throw StateError('추가 정보 저장에 실패했습니다. 서버와 DB 설정을 확인해주세요.');
    }
  }

  @override
  Future<void> signUpWithEnrollment(
    String email,
    String password,
    VerifiedPhone phone,
    DateTime? birthDate,
  ) async {
    if (phone.expired) throw StateError('휴대폰 인증 후 5분이 지났습니다. 다시 인증해주세요.');
    // Validate the signed proof and schema before creating an email account.
    final checked = await _client
        .post(
          Uri.parse('$_baseUrl/auth/phone/validate'),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode(_enrollmentBody(phone, birthDate)),
        )
        .timeout(const Duration(seconds: 10));
    if (checked.statusCode == 401) throw StateError('휴대폰 인증을 다시 진행해주세요.');
    if (checked.statusCode != 200) {
      throw StateError('회원가입 준비를 확인하지 못했습니다. 서버와 DB 설정을 확인해주세요.');
    }
    final before = _auth.currentUser?.uid;
    try {
      await signUp(email, password);
      await saveEnrollment(phone, birthDate);
    } catch (_) {
      if (_auth.currentUser?.uid != null && _auth.currentUser?.uid != before) {
        // Never delete a newly created account to guess the result of a timeout.
        throw StateError(
          '이메일 계정은 생성되었지만 추가 정보 저장을 완료하지 못했습니다. 로그인 후 설정에서 휴대폰 인증·생일 등록을 완료해주세요.',
        );
      }
      rethrow;
    }
  }

  bool _googleInitialized = false;
  AccountLoginProvider? _loginProvider;
  String? _loginProviderUserId;
  int _loginProviderGeneration = 0;

  void _clearLoginProvider() {
    _loginProviderGeneration++;
    _loginProvider = null;
    _loginProviderUserId = null;
  }

  void _rememberLoginProvider(AccountLoginProvider provider) {
    final uid = _auth.currentUser?.uid;
    _loginProviderGeneration++;
    _loginProviderUserId = uid;
    _loginProvider = uid == null ? null : provider;
  }

  Future<void> _restoreLoginProvider(User user) async {
    final generation = ++_loginProviderGeneration;
    _loginProviderUserId = user.uid;
    _loginProvider = null;
    try {
      final result = await user.getIdTokenResult().timeout(
        const Duration(seconds: 5),
      );
      if (generation != _loginProviderGeneration ||
          _auth.currentUser?.uid != user.uid) {
        return;
      }
      // Linked providerData describes available methods, not this session's
      // actual method. Names/contact email are never authentication evidence.
      _loginProvider = switch (result.signInProvider) {
        'password' => AccountLoginProvider.email,
        'google.com' => AccountLoginProvider.google,
        'custom' when user.uid.startsWith('kakao:') =>
          AccountLoginProvider.kakao,
        'custom' when user.uid.startsWith('naver:') =>
          AccountLoginProvider.naver,
        _ => null,
      };
    } catch (_) {
      // Presentation-only metadata must not block session/profile restoration.
      // A newer sign-in's cached provider is not cleared by this older failure.
    }
  }

  @override
  Future<bool> restoreSession() async {
    final user = await _auth.authStateChanges().first;
    if (user == null) {
      _clearLoginProvider();
      return false;
    }
    await _restoreLoginProvider(user);
    await _syncCustomerProfile();
    return true;
  }

  /// Firebase 계정을 MySQL 고객 프로필과 연결해 이후 주문 인증에 사용합니다.
  Future<void> _syncCustomerProfile() async {
    final user = _auth.currentUser;
    final token = await user?.getIdToken();
    final email = user?.email;
    if (user == null || token == null) {
      throw StateError('회원 인증 정보를 확인하지 못했습니다.');
    }
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json; charset=utf-8',
    };
    // 이미 연결된 고객은 조회만 합니다. 앱 시작 때 프로필을 덮어쓰지 않습니다.
    final profile = await _client
        .get(Uri.parse('$_baseUrl/auth/me'), headers: headers)
        .timeout(const Duration(seconds: 10));
    if (profile.statusCode == 200) return;
    if (profile.statusCode != 404) {
      throw StateError('MySQL 회원 정보 확인에 실패했습니다. (${profile.statusCode})');
    }
    // 소셜 고객은 검증된 공급자 ID를 통해 서버에서 생성됩니다.
    // 이메일 없는 소셜 계정을 임의 이메일로 새로 가입시키지 않습니다.
    if (email == null) {
      throw StateError('소셜 회원 정보가 연결되지 않았습니다. 해당 로그인으로 다시 시도해주세요.');
    }
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/auth/customer/sync'),
          headers: headers,
          body: jsonEncode({
            'ensureOnly': true,
            'customerName': user.displayName?.trim().isNotEmpty == true
                ? user.displayName!.trim()
                : email.split('@').first,
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError('MySQL 회원 정보 연결에 실패했습니다. (${response.statusCode})');
    }
  }

  Future<void> _initializeGoogle() async {
    if (_googleInitialized) return;

    await _googleSignIn.initialize();
    _googleInitialized = true;
  }

  @override
  Future<bool> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      _rememberLoginProvider(AccountLoginProvider.email);
      await _syncCustomerProfile();

      return true;
    } on FirebaseAuthException {
      return false;
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError('MySQL 회원 정보 연결에 실패했습니다.');
    }
  }

  @override
  Future<void> signUp(String email, String password) async {
    try {
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      _rememberLoginProvider(AccountLoginProvider.email);
      await _syncCustomerProfile();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw StateError('이미 가입한 이메일입니다.');
      }

      if (e.code == 'weak-password') {
        throw StateError('비밀번호가 너무 약합니다.');
      }

      if (e.code == 'invalid-email') {
        throw StateError('올바른 이메일 주소를 입력해주세요.');
      }

      throw StateError('회원가입에 실패했습니다.');
    }
  }

  @override
  Future<bool> signInWithGoogle() async {
    try {
      await _initializeGoogle();

      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();

      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      if (googleAuth.idToken == null) {
        return false;
      }

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      await _auth.signInWithCredential(credential);
      _rememberLoginProvider(AccountLoginProvider.google);
      await _syncCustomerProfile();

      return true;
    } on GoogleSignInException {
      return false;
    } on FirebaseAuthException {
      return false;
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError('MySQL 회원 정보 연결에 실패했습니다.');
    }
  }

  Future<bool> _signInWithSocial(
    Future<String?> Function() login,
    AccountLoginProvider provider,
  ) async {
    final token = await login();
    if (token == null) return false;
    try {
      await _auth.signInWithCustomToken(token);
      _rememberLoginProvider(provider);
    } on FirebaseAuthException {
      throw StateError('소셜 로그인 인증을 완료하지 못했습니다. 서버 설정을 확인해주세요.');
    }
    // 이후 주문/문의에는 공급자 토큰이 아닌 Firebase ID 토큰을 사용합니다.
    await _syncCustomerProfile();
    if (provider == AccountLoginProvider.naver) {
      // The backend may upgrade the default name via the Admin SDK. Read the
      // latest Firebase profile instead of relying on a cached displayName.
      // Optional presentation refresh must not undo an authenticated login.
      try {
        await _auth.currentUser?.reload().timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    return true;
  }

  @override
  Future<bool> signInWithKakao() => _signInWithSocial(
    _socialLogin.kakaoCustomToken,
    AccountLoginProvider.kakao,
  );

  @override
  Future<bool> signInWithNaver() => _signInWithSocial(
    _socialLogin.naverCustomToken,
    AccountLoginProvider.naver,
  );

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    _clearLoginProvider();

    // 공급자 SDK의 로그아웃 실패가 Firebase 로그아웃을 되돌리지는 않습니다.
    try {
      if (_googleInitialized) await _googleSignIn.signOut();
    } catch (_) {}
    try {
      await _socialLogin.signOut();
    } catch (_) {}
  }

  @override
  String? get displayName => _auth.currentUser?.displayName;

  @override
  String? get email => _auth.currentUser?.email;

  @override
  String? get userId => _auth.currentUser?.uid;

  @override
  AccountLoginProvider? get loginProvider {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid != _loginProviderUserId) {
      if (_loginProviderUserId != null || _loginProvider != null) {
        _clearLoginProvider();
      }
      return null;
    }
    return _loginProvider;
  }
}
