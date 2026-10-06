import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/data/firestore_access_probe.dart';
import 'package:shupick/presentation/shared/firestore_access_check_card.dart';

void main() {
  Widget host({Key? key, FirestoreAccessProbe Function()? factory}) =>
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FirestoreAccessCheckCard(key: key, probeFactory: factory),
          ),
        ),
      );

  testWidgets('idle build does not access Firebase', (tester) async {
    await tester.pumpWidget(host());
    expect(find.text('Firestore 접근 검사'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'one tap reads exactly three paths; duplicate taps are disabled',
    (tester) async {
      var reads = 0;
      final pending = Completer<AccessProbeDocument>();
      await tester.pumpWidget(
        host(
          factory: () => FirestoreAccessProbe(
            currentUid: () => 'owner',
            readDocument: (_) {
              reads++;
              return pending.future;
            },
          ),
        ),
      );
      await tester.tap(find.text('Firestore 접근 검사'));
      await tester.pump();
      expect(reads, 3);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      pending.complete(
        const AccessProbeDocument(exists: true, ownerUid: 'owner'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('본인 문서 읽기 허용'), findsNWidgets(3));
      expect(find.text('owner'), findsNothing);
    },
  );

  testWidgets('guest denial is shown without private error details', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        factory: () => FirestoreAccessProbe(
          currentUid: () => null,
          readDocument: (_) async => throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
            message: 'private-token',
          ),
        ),
      ),
    );
    await tester.tap(find.text('Firestore 접근 검사'));
    await tester.pumpAndSettle();
    expect(find.text('검사 인증: 비회원'), findsOneWidget);
    expect(find.textContaining('읽기 차단 (permission-denied)'), findsNWidgets(3));
    expect(find.textContaining('private-token'), findsNothing);
  });

  testWidgets('successful guest read is flagged as a security problem', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        factory: () => FirestoreAccessProbe(
          currentUid: () => null,
          readDocument: (_) async =>
              const AccessProbeDocument(exists: true, ownerUid: 'secret-owner'),
        ),
      ),
    );
    await tester.tap(find.text('Firestore 접근 검사'));
    await tester.pumpAndSettle();
    expect(find.textContaining('보안 확인 필요'), findsNWidgets(3));
    expect(find.textContaining('secret-owner'), findsNothing);
  });

  testWidgets('configuration errors are sanitized, not reported as blocked', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(factory: () => throw StateError('private-config')),
    );
    await tester.tap(find.text('Firestore 접근 검사'));
    await tester.pumpAndSettle();
    expect(find.textContaining('검사를 실행하지 못했습니다'), findsOneWidget);
    expect(find.textContaining('permission-denied'), findsNothing);
    expect(find.textContaining('private-config'), findsNothing);
  });

  testWidgets('account-key replacement clears the previous result', (
    tester,
  ) async {
    final probe = FirestoreAccessProbe(
      currentUid: () => 'owner',
      readDocument: (_) async =>
          const AccessProbeDocument(exists: true, ownerUid: 'owner'),
    );
    await tester.pumpWidget(
      host(key: const ValueKey('owner'), factory: () => probe),
    );
    await tester.tap(find.text('Firestore 접근 검사'));
    await tester.pumpAndSettle();
    expect(find.textContaining('본인 문서 읽기 허용'), findsNWidgets(3));
    await tester.pumpWidget(
      host(key: const ValueKey('other'), factory: () => probe),
    );
    expect(find.textContaining('본인 문서 읽기 허용'), findsNothing);
  });

  testWidgets('finishing a read after disposal is safe', (tester) async {
    final pending = Completer<AccessProbeDocument>();
    await tester.pumpWidget(
      host(
        factory: () => FirestoreAccessProbe(
          currentUid: () => 'owner',
          readDocument: (_) => pending.future,
        ),
      ),
    );
    await tester.tap(find.text('Firestore 접근 검사'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete(
      const AccessProbeDocument(exists: true, ownerUid: 'owner'),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
