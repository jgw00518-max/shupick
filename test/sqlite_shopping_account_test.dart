import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/data/local_database.dart';
import 'package:shupick/data/sqlite_shopping_repository.dart';
import 'package:shupick/domain/models.dart';
import 'package:shupick/domain/repositories.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A gate delays real temporary-SQLite work without mocking account storage.
class _GatedDatabase extends LocalDatabase {
  _GatedDatabase({required super.path});

  Completer<void>? _gate;
  Completer<void>? _entered;

  void blockAccess() {
    expect(_gate, isNull);
    _gate = Completer<void>();
    _entered = Completer<void>();
  }

  Future<void> get entered => _entered!.future;

  void releaseAccess() {
    final gate = _gate;
    _gate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<Database> get database async {
    final gate = _gate;
    if (gate != null) {
      if (!_entered!.isCompleted) _entered!.complete();
      await gate.future;
    }
    return super.database;
  }
}

const _products = [
  Product(
    id: 101,
    name: 'Synthetic shoe A',
    category: '운동화',
    price: 10000,
    imageUrl: 'synthetic-a.png',
    color: '블랙',
    gender: '공용',
  ),
  Product(
    id: 102,
    name: 'Synthetic shoe B',
    category: '운동화',
    price: 20000,
    imageUrl: 'synthetic-b.png',
    color: '화이트',
    gender: '공용',
  ),
  Product(
    id: 103,
    name: 'Synthetic guest shoe',
    category: '운동화',
    price: 30000,
    imageUrl: 'synthetic-guest.png',
    color: '그레이',
    gender: '공용',
  ),
];

ShoppingSnapshot _snapshot(Product product, {int quantity = 1}) =>
    ShoppingSnapshot(
      cart: [
        CartItem(
          product: product,
          size: '260',
          color: product.color,
          quantity: quantity,
        ),
      ],
      wishedIds: {product.id},
      recentIds: [product.id],
    );

void _expectSnapshot(
  ShoppingSnapshot snapshot,
  Product product, {
  int quantity = 1,
}) {
  expect(snapshot.cart, hasLength(1));
  expect(snapshot.cart.single.product.id, product.id);
  expect(snapshot.cart.single.quantity, quantity);
  expect(snapshot.wishedIds, {product.id});
  expect(snapshot.recentIds, [product.id]);
}

void _expectEmpty(ShoppingSnapshot snapshot) {
  expect(snapshot.cart, isEmpty);
  expect(snapshot.wishedIds, isEmpty);
  expect(snapshot.recentIds, isEmpty);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory directory;
  late String databasePath;
  late _GatedDatabase database;
  late SqliteShoppingRepository shopping;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'shupick_account_sqlite_',
    );
    databasePath = '${directory.path}/accounts.sqlite';
    database = _GatedDatabase(path: databasePath);
    await database.cacheProducts(_products);
    shopping = SqliteShoppingRepository(database);
  });

  tearDown(() async {
    database.releaseAccess();
    await database.close();
    try {
      // This target is the exact directory created by this test, never app data.
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Windows can briefly retain SQLite handles after closing the connection.
    }
  });

  test(
    'guest and two Firebase UIDs keep all three shopping lists separate',
    () async {
      expect(shopping, isA<AccountScopedShoppingRepository>());
      expect(shopping.ownerKey, 'guest:v2');
      await shopping.save(_snapshot(_products[2], quantity: 3));

      shopping.selectAccount('account-A');
      expect(shopping.ownerKey, 'firebase:account-A');
      _expectEmpty(await shopping.load(_products));
      await shopping.save(_snapshot(_products[0]));

      shopping.selectAccount('account-B');
      expect(shopping.ownerKey, 'firebase:account-B');
      _expectEmpty(await shopping.load(_products));
      await shopping.save(_snapshot(_products[1], quantity: 2));

      shopping.selectAccount('account-A');
      _expectSnapshot(await shopping.load(_products), _products[0]);
      shopping.selectAccount('account-B');
      _expectSnapshot(
        await shopping.load(_products),
        _products[1],
        quantity: 2,
      );
      shopping.selectAccount(null);
      expect(shopping.ownerKey, 'guest:v2');
      _expectSnapshot(
        await shopping.load(_products),
        _products[2],
        quantity: 3,
      );

      final db = await database.database;
      for (final table in ['cart_items', 'favorites', 'product_views']) {
        final rows = await db.query(table, columns: ['owner_key']);
        expect(rows.map((row) => row['owner_key']).toSet(), {
          'guest:v2',
          'firebase:account-A',
          'firebase:account-B',
        });
      }
    },
  );

  test(
    'a new repository restores the selected UID after database reopening',
    () async {
      await shopping.save(_snapshot(_products[2]));
      shopping.selectAccount('account-A');
      await shopping.save(_snapshot(_products[0], quantity: 4));
      shopping.selectAccount('account-B');
      await shopping.save(_snapshot(_products[1], quantity: 2));
      await database.close();

      database = _GatedDatabase(path: databasePath);
      shopping = SqliteShoppingRepository(database);
      _expectSnapshot(await shopping.load([]), _products[2]);
      shopping.selectAccount('account-A');
      _expectSnapshot(await shopping.load([]), _products[0], quantity: 4);
      shopping.selectAccount('account-B');
      _expectSnapshot(await shopping.load([]), _products[1], quantity: 2);
    },
  );

  test(
    'legacy guest rows are preserved but never exposed or auto-migrated',
    () async {
      final legacy = SqliteShoppingRepository(database, ownerKey: 'guest');
      await legacy.save(_snapshot(_products[0], quantity: 5));
      final db = await database.database;
      final before = {
        for (final table in ['cart_items', 'favorites', 'product_views'])
          table: await db.query(
            table,
            where: 'owner_key = ?',
            whereArgs: ['guest'],
          ),
      };

      _expectEmpty(await shopping.load(_products));
      shopping.selectAccount('account-A');
      _expectEmpty(await shopping.load(_products));
      await shopping.save(_snapshot(_products[1]));
      shopping.selectAccount(null);
      _expectEmpty(await shopping.load(_products));
      await shopping.save(_snapshot(_products[2]));

      _expectSnapshot(await legacy.load(_products), _products[0], quantity: 5);
      for (final table in ['cart_items', 'favorites', 'product_views']) {
        expect(
          await db.query(table, where: 'owner_key = ?', whereArgs: ['guest']),
          before[table],
        );
      }
    },
  );

  test('a pending load stays bound to the UID selected at call time', () async {
    shopping.selectAccount('account-A');
    await shopping.save(_snapshot(_products[0]));
    shopping.selectAccount('account-B');
    await shopping.save(_snapshot(_products[1]));
    shopping.selectAccount('account-A');
    database.blockAccess();

    final pendingLoad = shopping.load(_products);
    try {
      await database.entered;
      shopping.selectAccount('account-B');
    } finally {
      database.releaseAccess();
    }

    _expectSnapshot(await pendingLoad, _products[0]);
    _expectSnapshot(await shopping.load(_products), _products[1]);
  });

  test(
    'queued saves keep their original UIDs across further account switches',
    () async {
      shopping.selectAccount('account-A');
      database.blockAccess();
      final firstSave = shopping.save(_snapshot(_products[0]));
      late Future<void> secondSave;
      try {
        await database.entered;
        shopping.selectAccount('account-B');
        secondSave = shopping.save(_snapshot(_products[1], quantity: 2));
        shopping.selectAccount(null);
      } finally {
        database.releaseAccess();
      }
      await Future.wait([firstSave, secondSave]);

      _expectEmpty(await shopping.load(_products));
      shopping.selectAccount('account-A');
      _expectSnapshot(await shopping.load(_products), _products[0]);
      shopping.selectAccount('account-B');
      _expectSnapshot(
        await shopping.load(_products),
        _products[1],
        quantity: 2,
      );
    },
  );

  test(
    'load waiting for a pending save captures its UID before that wait',
    () async {
      shopping.selectAccount('account-B');
      await shopping.save(_snapshot(_products[1]));
      shopping.selectAccount('account-A');
      database.blockAccess();
      final pendingSave = shopping.save(_snapshot(_products[0], quantity: 6));
      late Future<ShoppingSnapshot> pendingLoad;
      try {
        await database.entered;
        pendingLoad = shopping.load(_products);
        shopping.selectAccount('account-B');
      } finally {
        database.releaseAccess();
      }

      await pendingSave;
      _expectSnapshot(await pendingLoad, _products[0], quantity: 6);
      _expectSnapshot(await shopping.load(_products), _products[1]);
    },
  );

  test(
    'save copies caller-owned lists and sets before asynchronous work starts',
    () async {
      shopping.selectAccount('account-A');
      final cart = [
        CartItem(product: _products[0], size: '260', color: '블랙', quantity: 2),
      ];
      final wishes = {_products[0].id};
      final recent = [_products[0].id];
      final snapshot = ShoppingSnapshot(
        cart: cart,
        wishedIds: wishes,
        recentIds: recent,
      );

      final pendingSave = shopping.save(snapshot);
      cart
        ..clear()
        ..add(CartItem(product: _products[1], size: '270', color: '화이트'));
      wishes
        ..clear()
        ..add(_products[1].id);
      recent
        ..clear()
        ..add(_products[1].id);
      shopping.selectAccount('account-B');
      await pendingSave;

      _expectEmpty(await shopping.load(_products));
      shopping.selectAccount('account-A');
      _expectSnapshot(
        await shopping.load(_products),
        _products[0],
        quantity: 2,
      );
    },
  );

  test('serialized saves for one UID keep only the latest snapshot', () async {
    shopping.selectAccount('account-A');
    database.blockAccess();
    final first = shopping.save(_snapshot(_products[0]));
    late Future<void> second;
    try {
      await database.entered;
      second = shopping.save(_snapshot(_products[1], quantity: 7));
    } finally {
      database.releaseAccess();
    }

    await Future.wait([first, second]);
    _expectSnapshot(await shopping.load(_products), _products[1], quantity: 7);
  });
}
