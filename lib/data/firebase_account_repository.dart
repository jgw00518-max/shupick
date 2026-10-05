import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../domain/repositories.dart';
import 'api_product_repository.dart';

class FirebaseAccountRepository implements AccountRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  bool _googleInitialized = false;

  /// Firebase 계정을 MySQL 고객 프로필과 연결해 이후 주문 인증에 사용합니다.
  Future<void> _syncCustomerProfile({
    String? customerName,
    String? phone,
    DateTime? birthDate,
  }) async {
    final user = _auth.currentUser;
    final token = await user?.getIdToken();
    final email = user?.email;
    if (user == null || token == null || email == null) {
      throw StateError('회원 인증 정보를 확인하지 못했습니다.');
    }
    final response = await http.post(
      Uri.parse('$defaultApiBaseUrl/auth/customer/sync'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode({
        'customerName':
            customerName ??
            (user.displayName?.trim().isNotEmpty == true
                ? user.displayName!.trim()
                : email.split('@').first),
        'phone': ?phone,
        if (birthDate != null)
          'birthDate': birthDate.toIso8601String().split('T').first,
      }),
    );
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
  Future<void> signUp(
    String email,
    String password, {
    String? name,
    String? phone,
    DateTime? birthDate,
  }) async {
    try {
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (name != null) await _auth.currentUser?.updateDisplayName(name.trim());
      await _syncCustomerProfile(
        customerName: name?.trim(),
        phone: phone,
        birthDate: birthDate,
      );
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

  @override
  Future<void> signOut() async {
    await _auth.signOut();

    await _initializeGoogle();
    await _googleSignIn.signOut();
  }

  @override
  String? get displayName => FirebaseAuth.instance.currentUser?.displayName;

  @override
  String? get email => FirebaseAuth.instance.currentUser?.email;
}
