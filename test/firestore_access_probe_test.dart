import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/data/firestore_access_probe.dart';

void main() {
  FirestoreAccessProbe probe({
    String? uid = 'owner',
    required Future<AccessProbeDocument> Function(String) read,
  }) => FirestoreAccessProbe(currentUid: () => uid, readDocument: read);

  void expectAll(FirestoreAccessReport report, FirestoreAccessOutcome outcome) {
    expect(report.results.map((r) => r.path), FirestoreAccessProbe.paths);
    expect(report.results.map((r) => r.outcome), everyElement(outcome));
  }

  test('reads only the three approved paths and allows their owner', () async {
    final requested = <String>[];
    final report = await probe(
      read: (path) async {
        requested.add(path);
        return const AccessProbeDocument(exists: true, ownerUid: 'owner');
      },
    ).run();
    expect(requested, FirestoreAccessProbe.paths);
    expect(report.signedIn, isTrue);
    expectAll(report, FirestoreAccessOutcome.ownAllowed);
  });

  for (final uid in ['other-user', null]) {
    test('reading another account document is unsafe for $uid', () async {
      final report = await probe(
        uid: uid,
        read: (_) async {
          return const AccessProbeDocument(exists: true, ownerUid: 'owner');
        },
      ).run();
      expect(report.signedIn, uid != null);
      expectAll(report, FirestoreAccessOutcome.unauthorizedAllowed);
    });
    test('permission-denied is a blocked read for $uid', () async {
      final report = await probe(
        uid: uid,
        read: (_) async {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          );
        },
      ).run();
      expectAll(report, FirestoreAccessOutcome.blocked);
    });
  }

  for (final entry in {
    'missing': const AccessProbeDocument(exists: false),
    'cached': const AccessProbeDocument(
      exists: true,
      ownerUid: 'owner',
      isFromCache: true,
    ),
    'pending writes': const AccessProbeDocument(
      exists: true,
      ownerUid: 'owner',
      hasPendingWrites: true,
    ),
  }.entries) {
    test('${entry.key} is not security evidence', () async {
      expectAll(
        await probe(read: (_) async => entry.value).run(),
        FirestoreAccessOutcome.unverified,
      );
    });
  }

  test('readable document with missing ownership is unsafe', () async {
    expectAll(
      await probe(
        read: (_) async => const AccessProbeDocument(exists: true),
      ).run(),
      FirestoreAccessOutcome.unauthorizedAllowed,
    );
  });

  for (final error in [
    FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
    FirebaseException(plugin: 'cloud_firestore', code: 'unauthenticated'),
    FirebaseException(plugin: 'firebase_auth', code: 'permission-denied'),
    StateError('do not expose private error messages'),
  ]) {
    test('$error is inconclusive, not a rule denial', () async {
      expectAll(
        await probe(read: (_) async => throw error).run(),
        FirestoreAccessOutcome.unverified,
      );
    });
  }

  test('timeout is inconclusive', () async {
    final report = await FirestoreAccessProbe(
      currentUid: () => 'owner',
      readDocument: (_) => Completer<AccessProbeDocument>().future,
      timeout: const Duration(milliseconds: 1),
    ).run();
    expectAll(report, FirestoreAccessOutcome.unverified);
  });

  for (final denied in [true, false]) {
    test(
      'account changes discard ${denied ? 'denied' : 'allowed'} results',
      () async {
        String? uid = 'owner';
        final pending = Completer<AccessProbeDocument>();
        final check = FirestoreAccessProbe(
          currentUid: () => uid,
          readDocument: (_) => pending.future,
        ).run();
        uid = null;
        if (denied) {
          pending.completeError(
            FirebaseException(
              plugin: 'cloud_firestore',
              code: 'permission-denied',
            ),
          );
        } else {
          pending.complete(
            const AccessProbeDocument(exists: true, ownerUid: 'owner'),
          );
        }
        final report = await check;
        expect(report.accountChanged, isTrue);
        expect(report.results, isEmpty);
      },
    );
  }

  test('a failed document does not hide the other document results', () async {
    final report = await probe(
      read: (path) async {
        if (path == 'fulfillmentStatuses/2') {
          throw StateError('network failure');
        }
        return const AccessProbeDocument(exists: true, ownerUid: 'owner');
      },
    ).run();
    expect(report.results.map((r) => r.outcome), [
      FirestoreAccessOutcome.ownAllowed,
      FirestoreAccessOutcome.unverified,
      FirestoreAccessOutcome.ownAllowed,
    ]);
  });
}
