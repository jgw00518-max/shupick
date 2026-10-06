import 'dart:convert';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../domain/repositories.dart';
import 'api_product_repository.dart';
import 'local_database.dart';

/// 인증된 고객의 행동을 SQLite 큐에 보관하고 성공 응답 후에만 제거합니다.
class ApiInteractionRepository implements InteractionRepository {
  ApiInteractionRepository(
    this.database, {
    http.Client? client,
    String? baseUrl,
    String? Function()? uidProvider,
    Future<String?> Function()? tokenProvider,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? defaultApiBaseUrl,
       _uid = uidProvider ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _token =
           tokenProvider ??
           (() =>
               FirebaseAuth.instance.currentUser?.getIdToken() ??
               Future.value(null));
  final LocalDatabase database;
  final http.Client _client;
  final String _baseUrl;
  final String? Function() _uid;
  final Future<String?> Function() _token;
  final String _session = _key();
  Future<void> _pending = Future.value();
  static String _key() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  Future<void> _ensureQueue() async {
    final db = await database.database;
    await db.execute('''CREATE TABLE IF NOT EXISTS interaction_queue (
      event_key TEXT PRIMARY KEY,customer_uid TEXT NOT NULL,payload TEXT NOT NULL,
      queued_at TEXT NOT NULL)''');
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final next = _pending.then((_) => operation());
    _pending = next.catchError((Object _) {});
    return next;
  }

  @override
  Future<void> record(
    String eventType,
    int productId, {
    String? color,
    String? size,
    int? quantity,
  }) {
    final uid = _uid();
    if (uid == null) return Future.value();
    final now = DateTime.now().toUtc().toIso8601String();
    final key = _key();
    final payload = {
      'eventKey': key,
      'sessionKey': _session,
      'productId': productId,
      'eventType': eventType,
      'color': color,
      'size': size == null ? null : int.tryParse(size),
      'quantity': quantity,
      'occurredAt': now,
    };
    return _serialize(() async {
      await _ensureQueue();
      final db = await database.database;
      await db.insert('interaction_queue', {
        'event_key': key,
        'customer_uid': uid,
        'payload': jsonEncode(payload),
        'queued_at': now,
      });
      await _flush();
    });
  }

  @override
  Future<void> flush() => _serialize(_flush);
  Future<void> _flush() async {
    final uid = _uid();
    if (uid == null) return;
    await _ensureQueue();
    final db = await database.database;
    final rows = await db.query(
      'interaction_queue',
      where: 'customer_uid = ?',
      whereArgs: [uid],
      orderBy: 'queued_at,event_key',
      limit: 50,
    );
    final token = await _token();
    if (token == null || _uid() != uid) return;
    for (final row in rows) {
      if (_uid() != uid) return;
      try {
        final response = await _client
            .post(
              Uri.parse('$_baseUrl/interactions'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: row['payload'] as String,
            )
            .timeout(const Duration(seconds: 10));
        if (response.statusCode != 201) return;
        await db.delete(
          'interaction_queue',
          where: 'event_key = ? AND customer_uid = ?',
          whereArgs: [row['event_key'], uid],
        );
      } catch (_) {
        return;
      }
    }
  }
}
