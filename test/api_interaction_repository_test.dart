import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shupick/data/api_interaction_repository.dart';
import 'package:shupick/data/local_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test('실패한 이벤트는 재시도하고 계정 변경 시 다른 고객 이벤트를 보내지 않는다', () async {
    final database = LocalDatabase(path: inMemoryDatabasePath);
    var uid = 'customer-a';
    var succeed = false;
    final bodies = <Map<String, dynamic>>[];
    final repository = ApiInteractionRepository(
      database,
      baseUrl: 'http://test',
      uidProvider: () => uid,
      tokenProvider: () async => 'token-$uid',
      client: MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{}', succeed ? 201 : 503);
      }),
    );
    try {
      await repository.record('VIEW', 1);
      final db = await database.database;
      expect((await db.query('interaction_queue')).length, 1);
      uid = 'customer-b';
      succeed = true;
      await repository.flush();
      expect(bodies.length, 1);
      uid = 'customer-a';
      await repository.flush();
      expect(bodies.length, 2);
      expect(bodies.first['eventKey'], bodies.last['eventKey']);
      expect(await db.query('interaction_queue'), isEmpty);
    } finally {
      await (await database.database).close();
    }
  });
}
