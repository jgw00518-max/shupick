import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

enum FirestoreAccessOutcome {
  ownAllowed,
  blocked,
  unauthorizedAllowed,
  unverified,
}

/// Only the fields needed to assess access; never exposes the document payload.
class AccessProbeDocument {
  const AccessProbeDocument({
    required this.exists,
    this.ownerUid,
    this.isFromCache = false,
    this.hasPendingWrites = false,
  });

  final bool exists;
  final String? ownerUid;
  final bool isFromCache;
  final bool hasPendingWrites;
}

class FirestoreAccessResult {
  const FirestoreAccessResult(this.path, this.outcome);
  final String path;
  final FirestoreAccessOutcome outcome;
}

class FirestoreAccessReport {
  const FirestoreAccessReport({
    required this.signedIn,
    required this.results,
    this.accountChanged = false,
  });
  final bool signedIn;
  final List<FirestoreAccessResult> results;
  final bool accountChanged;
}

/// Read-only client probe for the existing, explicitly approved test order.
/// No Admin SDK, sign-in, writes, arbitrary paths, or cached-read fallback.
class FirestoreAccessProbe {
  FirestoreAccessProbe({
    required this.currentUid,
    required this.readDocument,
    this.timeout = const Duration(seconds: 10),
  });

  static const paths = [
    'orderStatuses/2',
    'fulfillmentStatuses/2',
    'pickupStatuses/2',
  ];
  final String? Function() currentUid;
  final Future<AccessProbeDocument> Function(String path) readDocument;
  final Duration timeout;

  factory FirestoreAccessProbe.live() {
    if (!kDebugMode || Firebase.app().options.projectId != 'shupick-71b8f') {
      throw StateError('Access probe is limited to the debug test project.');
    }
    final auth = FirebaseAuth.instance;
    final firestore = FirebaseFirestore.instance;
    return FirestoreAccessProbe(
      currentUid: () => auth.currentUser?.uid,
      readDocument: (path) async {
        final snapshot = await firestore
            .doc(path)
            .get(const GetOptions(source: Source.server));
        final owner = snapshot.data()?['customerUid'];
        return AccessProbeDocument(
          exists: snapshot.exists,
          ownerUid: owner is String ? owner : null,
          isFromCache: snapshot.metadata.isFromCache,
          hasPendingWrites: snapshot.metadata.hasPendingWrites,
        );
      },
    );
  }

  Future<FirestoreAccessReport> run() async {
    final uid = currentUid();
    final results = await Future.wait(paths.map((path) => _read(path, uid)));
    // A late result must not be attributed to a different account.
    final changed = currentUid() != uid;
    return FirestoreAccessReport(
      signedIn: uid != null,
      results: changed ? const [] : List.unmodifiable(results),
      accountChanged: changed,
    );
  }

  Future<FirestoreAccessResult> _read(String path, String? uid) async {
    var outcome = FirestoreAccessOutcome.unverified;
    try {
      final document = await readDocument(path).timeout(timeout);
      if (document.exists &&
          !document.isFromCache &&
          !document.hasPendingWrites) {
        outcome = uid != null && document.ownerUid == uid
            ? FirestoreAccessOutcome.ownAllowed
            : FirestoreAccessOutcome.unauthorizedAllowed;
      }
    } on FirebaseException catch (error) {
      // Network/auth/config errors are not evidence of rule enforcement.
      if (error.plugin == 'cloud_firestore' &&
          error.code == 'permission-denied') {
        outcome = FirestoreAccessOutcome.blocked;
      }
    } catch (_) {
      // Do not display or log exception messages, tokens, or document contents.
    }
    return FirestoreAccessResult(path, outcome);
  }
}
