import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';
import 'local_database.dart';

/// Keeps each Firebase member and the anonymous device session separate.
/// Legacy 'guest' rows have unknown ownership and remain untouched.
class SqliteShoppingRepository
    implements ShoppingRepository, AccountScopedShoppingRepository {
  SqliteShoppingRepository(this._database, {String? ownerKey})
    : _ownerKey = ownerKey ?? 'guest:v2';

  final LocalDatabase _database;
  String _ownerKey;
  String get ownerKey => _ownerKey;
  Future<void> _writes = Future.value();

  @override
  void selectAccount(String? userId) {
    _ownerKey = userId == null ? 'guest:v2' : 'firebase:$userId';
  }

  @override
  Future<ShoppingSnapshot> load(List<Product> products) async {
    final owner = _ownerKey;
    await _writes;
    final db = await _database.database;
    final productById = {for (final product in products) product.id: product};
    for (final product in await _database.cachedProducts()) {
      productById.putIfAbsent(product.id, () => product);
    }
    final cartRows = await db.query(
      'cart_items',
      where: 'owner_key = ?',
      whereArgs: [owner],
      orderBy: 'cart_item_id',
    );
    final wishRows = await db.query(
      'favorites',
      columns: ['product_id'],
      where: 'owner_key = ?',
      whereArgs: [owner],
      orderBy: 'created_at DESC',
    );
    final viewRows = await db.query(
      'product_views',
      columns: ['product_id'],
      where: 'owner_key = ?',
      whereArgs: [owner],
      orderBy: 'view_id DESC',
    );
    return ShoppingSnapshot(
      cart: [
        for (final row in cartRows)
          if (productById[row['product_id']] != null)
            CartItem(
              product: productById[row['product_id']]!,
              color: row['color'] as String,
              size: row['size'] as String,
              quantity: row['quantity'] as int,
            ),
      ],
      wishedIds: {for (final row in wishRows) row['product_id'] as int},
      recentIds: [for (final row in viewRows) row['product_id'] as int],
    );
  }

  @override
  Future<void> save(ShoppingSnapshot snapshot) {
    // StoreController saves without awaiting. Serialize snapshots so an older
    // write cannot commit after a newer UI state.
    // Capture both owner and collections before waiting for earlier writes.
    final owner = _ownerKey;
    final captured = ShoppingSnapshot(
      cart: List.of(snapshot.cart),
      wishedIds: Set.of(snapshot.wishedIds),
      recentIds: List.of(snapshot.recentIds),
    );
    final next = _writes.then((_) => _saveSnapshot(owner, captured));
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> _saveSnapshot(String owner, ShoppingSnapshot snapshot) async {
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      for (final table in ['cart_items', 'favorites', 'product_views']) {
        await txn.delete(table, where: 'owner_key = ?', whereArgs: [owner]);
      }
      for (final item in snapshot.cart) {
        await txn.insert('cart_items', {
          'owner_key': owner,
          'product_id': item.product.id,
          'color': item.color,
          'size': item.size,
          'quantity': item.quantity.clamp(1, 99),
          'added_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final productId in snapshot.wishedIds) {
        await txn.insert('favorites', {
          'owner_key': owner,
          'product_id': productId,
          'created_at': now,
        });
      }
      // A larger view_id means a more recently viewed product.
      for (final productId in snapshot.recentIds.reversed) {
        await txn.insert('product_views', {
          'owner_key': owner,
          'product_id': productId,
          'viewed_at': now,
        });
      }
    });
  }
}
