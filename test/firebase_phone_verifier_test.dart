import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/data/firebase_phone_verifier.dart';

class _User implements User {
  @override
  String? phoneNumber = '+821012345678';
  bool forced = false;
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    forced = forceRefresh;
    return 'synthetic-proof';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Credential implements UserCredential {
  _Credential(this.user);
  @override
  final User user;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements FirebaseAuth {
  final user = _User();
  final requests = <String?>[];
  final resendTokens = <int?>[];
  final completed = <PhoneVerificationCompleted>[];
  int signIns = 0;
  int signOuts = 0;
  String? failure;
  Future<void>? nativeWait;

  @override
  Future<void> signOut() async {
    signOuts++;
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    signIns++;
    return _Credential(user);
  }

  @override
  Future<void> verifyPhoneNumber({
    String? phoneNumber,
    PhoneMultiFactorInfo? multiFactorInfo,
    required PhoneVerificationCompleted verificationCompleted,
    required PhoneVerificationFailed verificationFailed,
    required PhoneCodeSent codeSent,
    required PhoneCodeAutoRetrievalTimeout codeAutoRetrievalTimeout,
    String? autoRetrievedSmsCodeForTesting,
    Duration timeout = const Duration(seconds: 30),
    int? forceResendingToken,
    MultiFactorSession? multiFactorSession,
  }) async {
    requests.add(phoneNumber);
    resendTokens.add(forceResendingToken);
    completed.add(verificationCompleted);
    if (failure != null) {
      verificationFailed(
        FirebaseAuthException(
          code: failure!,
          message: 'private-phone-or-token',
        ),
      );
    } else {
      codeSent('synthetic-verification-id', 7);
    }
    // Native completion can arrive after a callback (including an error).
    await (nativeWait ?? Future<void>.delayed(Duration.zero));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'idle and closing unused verifier never initialize Firebase or send SMS',
    () async {
      int created = 0;
      final verifier = FirebasePhoneVerifier(
        authFactory: () async {
          created++;
          return _Auth();
        },
      );
      expect(created, 0);
      await verifier.close();
      expect(created, 0);
      await expectLater(
        verifier.sendCode('01012345678', onAutomaticVerification: (_) {}),
        throwsStateError,
      );
    },
  );

  test(
    'SMS code verification uses only auxiliary Auth and refreshes its proof',
    () async {
      final auth = _Auth();
      final verifier = FirebasePhoneVerifier(authFactory: () async => auth);
      await verifier.sendCode('010-1234-5678', onAutomaticVerification: (_) {});
      expect(auth.requests, ['+821012345678']);
      expect(auth.signIns, 0);
      final proof = await verifier.verifyCode('123456');
      expect(proof.number, '+821012345678');
      expect(proof.idToken, 'synthetic-proof');
      expect(auth.user.forced, true);
      expect(auth.signIns, 1);
      await verifier.close();
      expect(auth.signOuts, 2);
    },
  );

  test(
    'same-number resend uses native token and new-number request clears it',
    () async {
      final auth = _Auth();
      final verifier = FirebasePhoneVerifier(authFactory: () async => auth);
      await verifier.sendCode('01012345678', onAutomaticVerification: (_) {});
      await verifier.sendCode('01012345678', onAutomaticVerification: (_) {});
      await verifier.sendCode('01087654321', onAutomaticVerification: (_) {});
      expect(auth.resendTokens, [null, 7, null]);
      await verifier.close();
    },
  );

  test(
    'native callback failure before native future completes is sanitized',
    () async {
      final auth = _Auth()..failure = 'billing-not-enabled';
      final nativeDone = Completer<void>();
      auth.nativeWait = nativeDone.future;
      final verifier = FirebasePhoneVerifier(authFactory: () async => auth);
      await expectLater(
        verifier.sendCode('01012345678', onAutomaticVerification: (_) {}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'safe message',
            contains('문자 발송 요금제'),
          ),
        ),
      );
      expect(auth.signIns, 0);
      nativeDone.complete();
      await verifier.close();
    },
  );

  test(
    'invalid code and wrong signed-in phone cannot produce a proof',
    () async {
      final auth = _Auth();
      final verifier = FirebasePhoneVerifier(authFactory: () async => auth);
      await verifier.sendCode('01012345678', onAutomaticVerification: (_) {});
      await expectLater(verifier.verifyCode('123'), throwsStateError);
      expect(auth.signIns, 0);
      auth.user.phoneNumber = '+821087654321';
      await expectLater(verifier.verifyCode('123456'), throwsStateError);
      await verifier.close();
    },
  );

  test(
    'late automatic callbacks from prior request or closed screen are ignored',
    () async {
      final auth = _Auth();
      final verifier = FirebasePhoneVerifier(authFactory: () async => auth);
      int proofs = 0;
      await verifier.sendCode(
        '01012345678',
        onAutomaticVerification: (_) => proofs++,
      );
      await verifier.sendCode(
        '01087654321',
        onAutomaticVerification: (_) => proofs++,
      );
      final credential = PhoneAuthProvider.credential(
        verificationId: 'synthetic-id',
        smsCode: '123456',
      );
      auth.completed.first(credential);
      await Future<void>.delayed(Duration.zero);
      expect(proofs, 0);
      expect(auth.signIns, 0);
      await verifier.close();
      auth.completed.last(credential);
      await Future<void>.delayed(Duration.zero);
      expect(proofs, 0);
      expect(auth.signIns, 0);
    },
  );
}
