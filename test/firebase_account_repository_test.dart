import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shupick/data/firebase_account_repository.dart';
import 'package:shupick/data/social_login_client.dart';
import 'package:shupick/domain/repositories.dart';
import 'package:shupick/domain/customer_enrollment.dart';

class _TokenResult implements IdTokenResult {
  _TokenResult(this.signInProvider, {this.claims});

  @override
  final String? signInProvider;
  @override
  final Map<String, dynamic>? claims;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UserInfo implements UserInfo {
  _UserInfo(this.providerId);

  @override
  final String providerId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _User implements User {
  _User({
    required this.uid,
    this.email,
    this.displayName = '소셜 회원',
    this.idToken = 'synthetic-firebase-id-token',
    this.events,
    this.signInProvider = 'custom',
    this.providerData = const [],
    this.tokenResultError,
    this.tokenResultFuture,
    this.claims,
    this.onReload,
  });

  @override
  final String uid;
  @override
  final String? email;
  @override
  final String? displayName;
  final String? idToken;
  final List<String>? events;
  final String? signInProvider;
  @override
  final List<UserInfo> providerData;
  final Object? tokenResultError;
  final Future<IdTokenResult>? tokenResultFuture;
  final Map<String, dynamic>? claims;
  final Future<void> Function()? onReload;
  int tokenResultRequests = 0;
  int reloads = 0;

  @override
  Future<void> reload() async {
    reloads++;
    events?.add('firebase-profile-reload');
    await onReload?.call();
  }

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    events?.add('firebase-id-token');
    return idToken;
  }

  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async {
    tokenResultRequests++;
    if (tokenResultError != null) throw tokenResultError!;
    if (tokenResultFuture != null) return tokenResultFuture!;
    return _TokenResult(signInProvider, claims: claims);
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
  _Auth({this.currentUser, this.nextUser, this.events});

  @override
  User? currentUser;
  User? nextUser;
  final List<String>? events;
  final List<String> customTokens = [];
  FirebaseAuthException? customTokenError;
  FirebaseAuthException? passwordError;
  FirebaseAuthException? credentialError;
  int emailSignIns = 0;
  int signUps = 0;
  final List<AuthCredential> credentials = [];
  int signOuts = 0;

  @override
  Stream<User?> authStateChanges() => Stream.value(currentUser);

  @override
  Future<UserCredential> signInWithCustomToken(String token) async {
    events?.add('firebase-custom-token');
    customTokens.add(token);
    if (customTokenError != null) throw customTokenError!;
    currentUser = nextUser;
    return _Credential(currentUser!);
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    emailSignIns++;
    if (passwordError != null) throw passwordError!;
    currentUser = nextUser;
    return _Credential(currentUser!);
  }

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    signUps++;
    if (passwordError != null) throw passwordError!;
    currentUser = nextUser;
    return _Credential(currentUser!);
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    credentials.add(credential);
    if (credentialError != null) throw credentialError!;
    currentUser = nextUser;
    return _Credential(currentUser!);
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    events?.add('firebase-sign-out');
    currentUser = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GoogleAccount implements GoogleSignInAccount {
  _GoogleAccount(this.idToken);

  final String? idToken;

  @override
  GoogleSignInAuthentication get authentication =>
      GoogleSignInAuthentication(idToken: idToken);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Google implements GoogleSignIn {
  _Google();

  final String? idToken = 'synthetic-google-id-token';
  GoogleSignInException? error;
  int initializations = 0;
  int signOuts = 0;

  @override
  Future<void> initialize({
    String? clientId,
    String? serverClientId,
    String? nonce,
    String? hostedDomain,
  }) async {
    initializations++;
  }

  @override
  Future<GoogleSignInAccount> authenticate({
    List<String> scopeHint = const [],
  }) async {
    if (error != null) throw error!;
    return _GoogleAccount(idToken);
  }

  @override
  Future<void> signOut() async {
    signOuts++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Social implements SocialLoginClient {
  _Social({this.token, this.events});

  final String? token;
  final List<String>? events;
  int signOuts = 0;
  bool logoutFails = false;

  @override
  Future<String?> kakaoCustomToken() async {
    events?.add('kakao');
    return token;
  }

  @override
  Future<String?> naverCustomToken() async {
    events?.add('naver');
    return token;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    events?.add('provider-sign-out');
    if (logoutFails) throw StateError('synthetic-provider-logout-error');
  }
}

void main() {
  FirebaseAccountRepository repository(
    _Auth auth,
    MockClient client, {
    _Social? social,
    _Google? google,
  }) => FirebaseAccountRepository(
    firebaseAuth: auth,
    client: client,
    baseUrl: 'http://127.0.0.1:8000',
    socialLoginClient: social ?? _Social(),
    googleSignIn: google ?? _Google(),
  );

  group('phone enrollment', () {
    VerifiedPhone proof() => VerifiedPhone(
      number: '+821012345678',
      idToken: 'synthetic-phone-proof',
    );

    test('preflight failure never creates an email account', () async {
      final auth = _Auth();
      final account = repository(
        auth,
        MockClient((request) async {
          expect(request.url.path, '/auth/phone/validate');
          expect(request.headers['Authorization'], isNull);
          return http.Response('{}', 401);
        }),
      );
      await expectLater(
        account.signUpWithEnrollment(
          'synthetic@example.com',
          'synthetic-password',
          proof(),
          null,
        ),
        throwsStateError,
      );
      expect(auth.signUps, 0);
      expect(auth.currentUser, isNull);
    });

    test(
      'successful signup saves using primary UID bearer, never phone bearer',
      () async {
        final auth = _Auth(
          nextUser: _User(uid: 'primary-uid', email: 'synthetic@example.com'),
        );
        final paths = <String>[];
        final account = repository(
          auth,
          MockClient((request) async {
            paths.add(request.url.path);
            expect(request.url.query, isEmpty);
            if (request.url.path == '/auth/me') {
              return http.Response('{}', 404);
            }
            if (request.url.path == '/auth/customer/enrollment') {
              expect(
                request.headers['Authorization'],
                'Bearer synthetic-firebase-id-token',
              );
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              expect(body['phoneToken'], 'synthetic-phone-proof');
              expect(body['phoneConsent'], true);
              expect(body['birthDate'], '2000-01-02');
              expect(body['birthdayConsent'], true);
              expect(body.containsKey('customerId'), false);
            }
            return http.Response('{}', 200);
          }),
        );
        await account.signUpWithEnrollment(
          'synthetic@example.com',
          'synthetic-password',
          proof(),
          DateTime(2000, 1, 2),
        );
        expect(paths, [
          '/auth/phone/validate',
          '/auth/me',
          '/auth/customer/sync',
          '/auth/customer/enrollment',
        ]);
        expect(auth.signUps, 1);
        expect(auth.currentUser?.uid, 'primary-uid');
        expect(auth.credentials, isEmpty);
        expect(auth.signOuts, 0);
      },
    );

    test(
      'post-signup storage failure explains recovery without deleting account',
      () async {
        final auth = _Auth(nextUser: _User(uid: 'created-primary-uid'));
        final account = repository(
          auth,
          MockClient(
            (request) async => http.Response(
              '{}',
              request.url.path == '/auth/customer/enrollment' ? 503 : 200,
            ),
          ),
        );
        await expectLater(
          account.signUpWithEnrollment(
            'synthetic@example.com',
            'synthetic-password',
            proof(),
            null,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('이메일 계정은 생성되었지만'),
            ),
          ),
        );
        expect(auth.currentUser?.uid, 'created-primary-uid');
        expect(auth.signOuts, 0);
      },
    );

    test('signed-out profile and storage requests never send HTTP', () async {
      final account = repository(
        _Auth(),
        MockClient((_) async => fail('Guest must not send HTTP')),
      );
      await expectLater(account.getEnrollmentProfile(), throwsStateError);
      await expectLater(
        account.saveEnrollment(proof(), null),
        throwsStateError,
      );
    });

    test('masked profile loads without changing primary identity', () async {
      final auth = _Auth(currentUser: _User(uid: 'primary-A'));
      final account = repository(
        auth,
        MockClient(
          (_) async => http.Response(
            '{"phoneVerified":true,"maskedPhone":"010-****-5678","birthDate":"2000-01-02"}',
            200,
          ),
        ),
      );
      final profile = await account.getEnrollmentProfile();
      expect(profile.phoneVerified, true);
      expect(profile.maskedPhone, '010-****-5678');
      expect(profile.birthDate, DateTime(2000, 1, 2));
      expect(account.enrollmentUserId, 'primary-A');
    });

    test('late HTTP result for previous account is discarded', () async {
      final auth = _Auth(currentUser: _User(uid: 'primary-A'));
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final account = repository(
        auth,
        MockClient((_) {
          started.complete();
          return response.future;
        }),
      );
      final pending = account.getEnrollmentProfile();
      final assertion = expectLater(pending, throwsStateError);
      await started.future;
      auth.currentUser = _User(uid: 'primary-B');
      response.complete(http.Response('{"phoneVerified":true}', 200));
      await assertion;
    });
  });

  test(
    'email-less existing social session restores with GET /auth/me only',
    () async {
      final user = _User(uid: 'kakao:synthetic-subject');
      final auth = _Auth(currentUser: user);
      final requests = <http.Request>[];
      final account = repository(
        auth,
        MockClient((request) async {
          requests.add(request);
          expect(request.method, 'GET');
          expect(request.url.path, '/auth/me');
          expect(request.headers['Authorization'], 'Bearer ${user.idToken}');
          return http.Response('{"customerId": 1}', 200);
        }),
      );

      expect(await account.restoreSession(), isTrue);
      expect(account.userId, user.uid);
      expect(account.email, isNull);
      expect(account.displayName, '소셜 회원');
      expect(account.loginProvider, AccountLoginProvider.kakao);
      expect(requests, hasLength(1));
      expect(auth.customTokens, isEmpty);
    },
  );

  test(
    'signed-out session makes no profile request or Firebase write',
    () async {
      final auth = _Auth();
      final account = repository(
        auth,
        MockClient(
          (_) async => fail('No HTTP is expected for a signed-out session'),
        ),
      );

      expect(await account.restoreSession(), isFalse);
      expect(account.userId, isNull);
      expect(account.loginProvider, isNull);
      expect(auth.customTokens, isEmpty);
    },
  );

  test(
    'email-less unlinked social session never invents an email or posts sync',
    () async {
      final requests = <http.Request>[];
      final account = repository(
        _Auth(currentUser: _User(uid: 'naver:synthetic-subject')),
        MockClient((request) async {
          requests.add(request);
          return http.Response('{"detail":"Customer not found"}', 404);
        }),
      );

      await expectLater(account.restoreSession(), throwsStateError);
      expect(
        requests.map((request) => '${request.method} ${request.url.path}'),
        ['GET /auth/me'],
      );
    },
  );

  test('existing email account remains a read-only profile lookup', () async {
    final user = _User(
      uid: 'synthetic-email-user',
      email: 'existing@example.com',
      displayName: 'Existing profile',
    );
    var requests = 0;
    final account = repository(
      _Auth(currentUser: user),
      MockClient((request) async {
        requests++;
        expect(request.method, 'GET');
        expect(request.url.path, '/auth/me');
        return http.Response('{}', 200);
      }),
    );

    expect(await account.restoreSession(), isTrue);
    expect(account.email, 'existing@example.com');
    expect(account.displayName, 'Existing profile');
    expect(requests, 1);
  });

  test(
    'unlinked email account retains ensure-only customer synchronization',
    () async {
      final user = _User(
        uid: 'synthetic-email-user',
        email: 'existing@example.com',
        displayName: '  Existing profile  ',
      );
      final requests = <http.Request>[];
      final account = repository(
        _Auth(currentUser: user),
        MockClient((request) async {
          requests.add(request);
          expect(request.headers['Authorization'], 'Bearer ${user.idToken}');
          if (request.method == 'GET') return http.Response('{}', 404);
          expect(request.method, 'POST');
          expect(request.url.path, '/auth/customer/sync');
          expect(jsonDecode(request.body), {
            'ensureOnly': true,
            'customerName': 'Existing profile',
          });
          return http.Response('{}', 200);
        }),
      );

      expect(await account.restoreSession(), isTrue);
      expect(requests, hasLength(2));
    },
  );

  test(
    'missing Firebase ID token blocks profile lookup without substituting another token',
    () async {
      final account = repository(
        _Auth(
          currentUser: _User(uid: 'kakao:synthetic-subject', idToken: null),
        ),
        MockClient(
          (_) async => fail('Missing Firebase ID token must not call HTTP'),
        ),
      );

      await expectLater(account.restoreSession(), throwsStateError);
    },
  );

  for (final provider in ['kakao', 'naver']) {
    test(
      '$provider custom token is exchanged before Firebase ID-token profile lookup',
      () async {
        final events = <String>[];
        final user = _User(uid: '$provider:synthetic-subject', events: events);
        final auth = _Auth(nextUser: user, events: events);
        final social = _Social(token: 'synthetic-custom-token', events: events);
        final account = repository(
          auth,
          MockClient((request) async {
            events.add('mysql-profile');
            expect(auth.currentUser, same(user));
            expect(request.method, 'GET');
            expect(request.url.path, '/auth/me');
            expect(request.headers['Authorization'], 'Bearer ${user.idToken}');
            expect(
              request.headers['Authorization'],
              isNot(contains(social.token!)),
            );
            expect(request.url.query, isEmpty);
            return http.Response('{}', 200);
          }),
          social: social,
        );

        final success = provider == 'kakao'
            ? await account.signInWithKakao()
            : await account.signInWithNaver();
        expect(success, isTrue);
        expect(auth.customTokens, ['synthetic-custom-token']);
        expect(account.userId, user.uid);
        expect(account.email, isNull);
        expect(
          account.loginProvider,
          provider == 'kakao'
              ? AccountLoginProvider.kakao
              : AccountLoginProvider.naver,
        );
        expect(events, [
          provider,
          'firebase-custom-token',
          'firebase-id-token',
          'mysql-profile',
          if (provider == 'naver') 'firebase-profile-reload',
        ]);
      },
    );

    test(
      '$provider cancellation returns false without changing an existing Firebase user',
      () async {
        final oldUser = _User(uid: 'existing-user');
        final auth = _Auth(currentUser: oldUser);
        final account = repository(
          auth,
          MockClient(
            (_) async => fail('Cancelled login must not call the backend'),
          ),
          social: _Social(),
        );

        final success = provider == 'kakao'
            ? await account.signInWithKakao()
            : await account.signInWithNaver();
        expect(success, isFalse);
        expect(auth.currentUser, same(oldUser));
        expect(auth.customTokens, isEmpty);
        expect(auth.signOuts, 0);
      },
    );
  }

  test(
    'naver reload reads the latest server-updated name without changing UID',
    () async {
      final auth = _Auth();
      final user = _User(
        uid: 'naver:synthetic-subject',
        displayName: '네이버 회원',
        onReload: () async {
          auth.currentUser = _User(
            uid: 'naver:synthetic-subject',
            displayName: 'Consented nickname',
          );
        },
      );
      auth.nextUser = user;
      final account = repository(
        auth,
        MockClient((_) async => http.Response('{}', 200)),
        social: _Social(token: 'synthetic-custom-token'),
      );

      expect(await account.signInWithNaver(), isTrue);
      expect(user.reloads, 1);
      expect(account.userId, user.uid);
      expect(account.displayName, 'Consented nickname');
      expect(account.loginProvider, AccountLoginProvider.naver);
      expect(auth.customTokens, ['synthetic-custom-token']);
      expect(auth.signOuts, 0);
    },
  );

  test(
    'optional naver profile refresh failure does not undo successful login',
    () async {
      final user = _User(
        uid: 'naver:synthetic-subject',
        displayName: 'Existing chosen name',
        onReload: () async => throw FirebaseAuthException(
          code: 'network-request-failed',
          message: 'synthetic-private-provider-body',
        ),
      );
      final auth = _Auth(nextUser: user);
      final account = repository(
        auth,
        MockClient((_) async => http.Response('{}', 200)),
        social: _Social(token: 'synthetic-custom-token'),
      );

      expect(await account.signInWithNaver(), isTrue);
      expect(account.userId, user.uid);
      expect(account.displayName, 'Existing chosen name');
      expect(account.loginProvider, AccountLoginProvider.naver);
      expect(auth.signOuts, 0);
    },
  );

  testWidgets(
    'optional naver profile refresh times out without blocking login',
    (tester) async {
      final started = Completer<void>();
      final neverReturns = Completer<void>();
      final user = _User(
        uid: 'naver:synthetic-subject',
        onReload: () {
          started.complete();
          return neverReturns.future;
        },
      );
      final auth = _Auth(nextUser: user);
      final account = repository(
        auth,
        MockClient((_) async => http.Response('{}', 200)),
        social: _Social(token: 'synthetic-custom-token'),
      );
      final login = account.signInWithNaver();
      await tester.pump();
      expect(started.isCompleted, isTrue);
      await tester.pump(const Duration(seconds: 6));
      expect(await login, isTrue);
      expect(account.userId, user.uid);
      expect(account.loginProvider, AccountLoginProvider.naver);
      expect(auth.signOuts, 0);
      neverReturns.complete();
      await tester.pump();
    },
  );

  test(
    'naver refresh never copies an old name into a different current user',
    () async {
      final started = Completer<void>();
      final finish = Completer<void>();
      final user = _User(
        uid: 'naver:old-subject',
        displayName: 'Old account name',
        onReload: () {
          started.complete();
          return finish.future;
        },
      );
      final auth = _Auth(nextUser: user);
      final account = repository(
        auth,
        MockClient((_) async => http.Response('{}', 200)),
        social: _Social(token: 'synthetic-custom-token'),
      );
      final login = account.signInWithNaver();
      await started.future;
      auth.currentUser = _User(
        uid: 'different-current-user',
        displayName: 'Other account',
      );
      finish.complete();

      expect(await login, isTrue);
      expect(account.userId, 'different-current-user');
      expect(account.displayName, 'Other account');
      expect(account.loginProvider, isNull);
    },
  );

  test(
    'Firebase custom-token rejection is generic and never queries MySQL',
    () async {
      final auth = _Auth()
        ..customTokenError = FirebaseAuthException(
          code: 'invalid-custom-token',
          message: 'synthetic-private-provider-body',
        );
      final account = repository(
        auth,
        MockClient(
          (_) async => fail('Rejected Firebase login must not query MySQL'),
        ),
        social: _Social(token: 'synthetic-custom-token'),
      );

      await expectLater(
        account.signInWithKakao(),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            isNot(contains('synthetic-private-provider-body')),
          ),
        ),
      );
      expect(auth.currentUser, isNull);
    },
  );

  test(
    'profile authorization failure is not reported as social login success',
    () async {
      final auth = _Auth(nextUser: _User(uid: 'naver:synthetic-subject'));
      final account = repository(
        auth,
        MockClient((_) async => http.Response('{}', 401)),
        social: _Social(token: 'synthetic-custom-token'),
      );

      await expectLater(account.signInWithNaver(), throwsStateError);
      expect(auth.customTokens, hasLength(1));
      expect(account.userId, 'naver:synthetic-subject');
      expect(account.loginProvider, AccountLoginProvider.naver);
    },
  );

  test('provider logout failure cannot undo Firebase logout', () async {
    final events = <String>[];
    final auth = _Auth(
      currentUser: _User(uid: 'kakao:synthetic-subject'),
      events: events,
    );
    final social = _Social(events: events)..logoutFails = true;
    final account = repository(
      auth,
      MockClient((_) async => fail('Logout must not request a profile')),
      social: social,
    );

    await account.signOut();
    expect(auth.currentUser, isNull);
    expect(account.userId, isNull);
    expect(account.loginProvider, isNull);
    expect(auth.signOuts, 1);
    expect(social.signOuts, 1);
    expect(events, ['firebase-sign-out', 'provider-sign-out']);
  });

  for (final entry in <(String?, String, AccountLoginProvider?)>[
    ('password', 'email-user', AccountLoginProvider.email),
    ('google.com', 'google-user', AccountLoginProvider.google),
    ('custom', 'kakao:scoped-user', AccountLoginProvider.kakao),
    ('custom', 'naver:scoped-user', AccountLoginProvider.naver),
    ('google.com', 'naver:linked-user', AccountLoginProvider.google),
    ('password', 'kakao:linked-user', AccountLoginProvider.email),
    ('custom', 'unrecognized-custom-user', null),
    ('phone', 'kakao:not-custom', null),
    ('anonymous', 'ordinary-user', null),
    ('apple.com', 'naver:not-custom', null),
    (null, 'kakao:missing-token-provider', null),
  ]) {
    test(
      'restore identifies ${entry.$1} for ${entry.$2} without email guessing',
      () async {
        final account = repository(
          _Auth(
            currentUser: _User(
              uid: entry.$2,
              email: 'same-contact@gmail.com',
              displayName: '카카오 네이버 구글 회원',
              signInProvider: entry.$1,
              providerData: [_UserInfo('password'), _UserInfo('google.com')],
              claims: {'social_provider': 'kakao'},
            ),
          ),
          MockClient((_) async => http.Response('{}', 200)),
        );

        expect(await account.restoreSession(), isTrue);
        expect(account.loginProvider, entry.$3);
      },
    );
  }

  test(
    'token metadata failure is unknown and does not block profile restoration',
    () async {
      final user = _User(
        uid: 'naver:scoped-user',
        tokenResultError: FirebaseAuthException(code: 'network-request-failed'),
        providerData: [_UserInfo('google.com')],
      );
      var profileRequests = 0;
      final account = repository(
        _Auth(currentUser: user),
        MockClient((_) async {
          profileRequests++;
          return http.Response('{}', 200);
        }),
      );

      expect(await account.restoreSession(), isTrue);
      expect(account.userId, user.uid);
      expect(account.loginProvider, isNull);
      expect(profileRequests, 1);
    },
  );

  for (final signUp in [false, true]) {
    test(
      'email ${signUp ? 'signup' : 'login'} remembers password method immediately',
      () async {
        final user = _User(
          uid: 'email-user',
          email: 'contact@gmail.com',
          signInProvider: 'google.com',
          providerData: [_UserInfo('google.com')],
        );
        final auth = _Auth(nextUser: user);
        late final FirebaseAccountRepository account;
        account = repository(
          auth,
          MockClient((_) async {
            expect(account.loginProvider, AccountLoginProvider.email);
            return http.Response('{}', 200);
          }),
        );

        if (signUp) {
          await account.signUp('contact@gmail.com', 'synthetic-password');
          expect(auth.signUps, 1);
        } else {
          expect(
            await account.signIn('contact@gmail.com', 'synthetic-password'),
            isTrue,
          );
          expect(auth.emailSignIns, 1);
        }
        expect(account.loginProvider, AccountLoginProvider.email);
        expect(user.tokenResultRequests, 0);
      },
    );
  }

  test(
    'Google login remembers actual method even for a linked social UID',
    () async {
      final auth = _Auth(
        nextUser: _User(
          uid: 'naver:linked-user',
          signInProvider: 'custom',
          providerData: [_UserInfo('password'), _UserInfo('google.com')],
        ),
      );
      final google = _Google();
      final account = repository(
        auth,
        MockClient((_) async => http.Response('{}', 200)),
        google: google,
      );

      expect(await account.signInWithGoogle(), isTrue);
      expect(account.loginProvider, AccountLoginProvider.google);
      expect(auth.credentials.single.providerId, 'google.com');
      expect(google.initializations, 1);
      await account.signOut();
      expect(account.loginProvider, isNull);
      expect(google.signOuts, 1);
    },
  );

  for (final provider in ['google', 'kakao', 'naver']) {
    test(
      '$provider cancellation preserves the existing session method',
      () async {
        final auth = _Auth(
          currentUser: _User(uid: 'email-user', signInProvider: 'password'),
        );
        final google = _Google()
          ..error = const GoogleSignInException(
            code: GoogleSignInExceptionCode.canceled,
          );
        final account = repository(
          auth,
          MockClient((_) async => http.Response('{}', 200)),
          google: google,
          social: _Social(),
        );
        expect(await account.restoreSession(), isTrue);

        final success = switch (provider) {
          'google' => await account.signInWithGoogle(),
          'kakao' => await account.signInWithKakao(),
          _ => await account.signInWithNaver(),
        };
        expect(success, isFalse);
        expect(account.loginProvider, AccountLoginProvider.email);
        expect(auth.customTokens, isEmpty);
      },
    );
  }

  test(
    'UID change drops cached provider and never reuses it when old UID returns',
    () async {
      final oldUser = _User(uid: 'old-user', signInProvider: 'google.com');
      final auth = _Auth(currentUser: oldUser);
      final account = repository(
        auth,
        MockClient((_) async => http.Response('{}', 200)),
      );
      expect(await account.restoreSession(), isTrue);
      expect(account.loginProvider, AccountLoginProvider.google);

      auth.currentUser = _User(uid: 'new-user', signInProvider: 'password');
      expect(account.loginProvider, isNull);
      auth.currentUser = oldUser;
      expect(account.loginProvider, isNull);
      expect(await account.restoreSession(), isTrue);
      expect(account.loginProvider, AccountLoginProvider.google);

      auth.currentUser = null;
      expect(account.loginProvider, isNull);
      expect(await account.restoreSession(), isFalse);
    },
  );

  test(
    'rejected password and custom-token attempts cannot relabel an existing session',
    () async {
      final oldUser = _User(uid: 'old-user', signInProvider: 'google.com');
      final auth = _Auth(currentUser: oldUser)
        ..passwordError = FirebaseAuthException(code: 'invalid-credential')
        ..customTokenError = FirebaseAuthException(
          code: 'invalid-custom-token',
        );
      final account = repository(
        auth,
        MockClient((_) async => http.Response('{}', 200)),
        social: _Social(token: 'synthetic-custom-token'),
      );
      expect(await account.restoreSession(), isTrue);
      expect(
        await account.signIn('contact@example.com', 'synthetic-password'),
        isFalse,
      );
      expect(account.loginProvider, AccountLoginProvider.google);
      await expectLater(account.signInWithNaver(), throwsStateError);
      expect(account.loginProvider, AccountLoginProvider.google);
      expect(auth.currentUser, same(oldUser));
    },
  );

  for (final sameUid in [false, true]) {
    test(
      'late restore metadata cannot overwrite a newer ${sameUid ? 'same UID' : 'other UID'} login',
      () async {
        final pendingMetadata = Completer<IdTokenResult>();
        final oldUser = _User(
          uid: 'old-user',
          tokenResultFuture: pendingMetadata.future,
        );
        final auth = _Auth(
          currentUser: oldUser,
          nextUser: _User(
            uid: sameUid ? 'old-user' : 'new-user',
            signInProvider: 'password',
          ),
        );
        final account = repository(
          auth,
          MockClient((_) async => http.Response('{}', 200)),
        );
        final pendingRestore = account.restoreSession();
        await Future<void>.delayed(Duration.zero);
        expect(oldUser.tokenResultRequests, 1);

        expect(
          await account.signIn('contact@example.com', 'synthetic-password'),
          isTrue,
        );
        pendingMetadata.complete(_TokenResult('google.com'));
        expect(await pendingRestore, isTrue);
        expect(account.loginProvider, AccountLoginProvider.email);
        expect(account.userId, sameUid ? 'old-user' : 'new-user');
      },
    );
  }
  for (final code in [
    GoogleSignInExceptionCode.clientConfigurationError,
    GoogleSignInExceptionCode.unknownError,
  ]) {
    test(
      'Google non-cancel failures expose only a safe enum code: $code',
      () async {
        final google = _Google()
          ..error = GoogleSignInException(
            code: code,
            description: 'synthetic-private-token-and-email',
          );
        final account = repository(
          _Auth(),
          MockClient((_) async => fail('No server request on native failure')),
          google: google,
        );
        await expectLater(
          account.signInWithGoogle(),
          throwsA(
            isA<StateError>()
                .having(
                  (error) => error.message,
                  'diagnostic',
                  contains('[GOOGLE:${code.name}]'),
                )
                .having(
                  (error) => error.message,
                  'no private details',
                  isNot(contains('synthetic-private-token-and-email')),
                ),
          ),
        );
      },
    );
  }
}
