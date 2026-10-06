import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../domain/customer_enrollment.dart';

/// A separate Auth instance prevents SMS sign-in from replacing the shopper UID.
/// Never links phone credentials to, merges, or deletes a customer account.
class FirebasePhoneVerifier implements PhoneVerifier {
  FirebasePhoneVerifier({this.authFactory});
  final Future<FirebaseAuth> Function()? authFactory;
  static int _nextInstance = 0;
  final String _appName = 'shupick-phone-${++_nextInstance}';
  FirebaseApp? _app;
  Future<FirebaseAuth>? _initialization;
  String? _verificationId;
  String? _number;
  int? _resendingToken;
  int _generation = 0;
  bool _closed = false;

  Future<FirebaseAuth> _auth() => _initialization ??= () async {
    if (authFactory != null) return authFactory!();
    final app = await Firebase.initializeApp(
      name: _appName,
      options: Firebase.app().options,
    );
    _app = app;
    final auth = FirebaseAuth.instanceFor(app: app);
    await auth.signOut(); // Never restore an old auxiliary phone session.
    return auth;
  }();

  bool _active(int generation) => !_closed && generation == _generation;

  String _message(FirebaseAuthException error) => switch (error.code) {
    'invalid-verification-code' => '인증번호가 올바르지 않습니다.',
    'session-expired' ||
    'invalid-verification-id' => '인증번호가 만료되었습니다. 다시 요청해주세요.',
    'too-many-requests' ||
    'quota-exceeded' => '문자 요청 한도를 초과했습니다. 잠시 후 다시 시도해주세요.',
    'operation-not-allowed' ||
    'billing-not-enabled' ||
    'configuration-not-found' => 'Firebase 전화번호 인증 설정과 문자 발송 요금제를 확인해주세요.',
    'app-not-authorized' ||
    'invalid-app-credential' ||
    'missing-client-identifier' => 'Firebase Android 앱 인증 설정(SHA 인증서)을 확인해주세요.',
    'network-request-failed' => '네트워크 연결을 확인해주세요.',
    _ => '휴대폰 인증을 완료하지 못했습니다. 설정을 확인하고 다시 시도해주세요.',
  };

  @override
  Future<void> sendCode(
    String phone, {
    required void Function(VerifiedPhone) onAutomaticVerification,
  }) async {
    if (_closed) throw StateError('휴대폰 인증 화면을 다시 열어주세요.');
    final generation = ++_generation;
    final number = normalizeKoreanMobile(phone);
    if (_number != number) _resendingToken = null;
    _number = number;
    _verificationId = null;
    final ready = Completer<void>();
    // Native callbacks can fail before verifyPhoneNumber itself completes.
    // Attach an error handler immediately; the awaited original still throws.
    ready.future.ignore();
    try {
      final auth = await _auth().timeout(const Duration(seconds: 15));
      if (!_active(generation)) throw StateError('휴대폰 인증이 취소되었습니다.');
      await auth.signOut().timeout(const Duration(seconds: 10));
      if (!_active(generation)) throw StateError('휴대폰 인증이 취소되었습니다.');
      final nativeRequest = auth.verifyPhoneNumber(
        phoneNumber: number,
        forceResendingToken: _resendingToken,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (credential) async {
          if (!_active(generation)) return;
          try {
            final proof = await _verify(credential, generation);
            if (_active(generation)) onAutomaticVerification(proof);
            if (!ready.isCompleted) ready.complete();
          } catch (error) {
            if (!ready.isCompleted) ready.completeError(error);
          }
        },
        verificationFailed: (error) {
          if (_active(generation) && !ready.isCompleted) {
            ready.completeError(StateError(_message(error)));
          }
        },
        codeSent: (verificationId, resendingToken) {
          if (!_active(generation)) return;
          _verificationId = verificationId;
          _resendingToken = resendingToken;
          if (!ready.isCompleted) ready.complete();
        },
        codeAutoRetrievalTimeout: (verificationId) {
          if (!_active(generation)) return;
          _verificationId = verificationId;
          if (!ready.isCompleted) ready.complete();
        },
      );
      await Future.wait([
        nativeRequest,
        ready.future,
      ], eagerError: true).timeout(const Duration(seconds: 90));
      if (!_active(generation)) throw StateError('휴대폰 인증이 취소되었습니다.');
    } on FirebaseAuthException catch (error) {
      throw StateError(_message(error));
    } on TimeoutException {
      _generation++;
      throw StateError('인증번호 요청 시간이 초과되었습니다. 다시 시도해주세요.');
    }
  }

  Future<VerifiedPhone> _verify(
    PhoneAuthCredential credential,
    int generation,
  ) async {
    final auth = await _auth();
    if (!_active(generation)) throw StateError('휴대폰 인증이 취소되었습니다.');
    final result = await auth.signInWithCredential(credential);
    final user = result.user;
    final token = await user?.getIdToken(true);
    if (!_active(generation) || user?.phoneNumber != _number || token == null) {
      throw StateError('휴대폰 인증을 다시 진행해주세요.');
    }
    return VerifiedPhone(number: _number!, idToken: token);
  }

  @override
  Future<VerifiedPhone> verifyCode(String code) async {
    if (_closed ||
        _verificationId == null ||
        !RegExp(r'^\d{6}$').hasMatch(code.trim())) {
      throw StateError('문자로 받은 인증번호 6자리를 입력해주세요.');
    }
    try {
      return await _verify(
        PhoneAuthProvider.credential(
          verificationId: _verificationId!,
          smsCode: code.trim(),
        ),
        _generation,
      ).timeout(const Duration(seconds: 20));
    } on FirebaseAuthException catch (error) {
      throw StateError(_message(error));
    } on TimeoutException {
      _generation++;
      _verificationId = null;
      throw StateError('인증 확인 시간이 초과되었습니다. 다시 시도해주세요.');
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _generation++;
    _verificationId = null;
    _number = null;
    _resendingToken = null;
    try {
      if (_initialization != null) {
        final auth = await _initialization!.timeout(
          const Duration(seconds: 15),
        );
        await auth.signOut().timeout(const Duration(seconds: 10));
      }
    } catch (_) {}
    try {
      await _app?.delete().timeout(const Duration(seconds: 10));
    } catch (_) {}
  }
}
