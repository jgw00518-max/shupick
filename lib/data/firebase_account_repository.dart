import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../domain/repositories.dart';

class FirebaseAccountRepository implements AccountRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  bool _googleInitialized = false;

  Future<void> _initializeGoogle() async {
    if (_googleInitialized) return;

    await _googleSignIn.initialize();
    _googleInitialized = true;
  }

  @override
  Future<bool> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);

      return true;
    } on FirebaseAuthException {
      return false;
    }
  }

  @override
  Future<void> signUp(String email, String password) async {
    try {
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
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

      return true;
    } on GoogleSignInException {
      return false;
    } on FirebaseAuthException {
      return false;
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
