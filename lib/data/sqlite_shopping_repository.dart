import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';
import 'local_database.dart';

/// Stores device shopping state. Until authentication returns a stable server
/// customer ID, the application uses the guest owner.
class SqliteShoppingRepository implements ShoppingRepository {
  SqliteShoppingRepository(this._database, {this.ownerKey = 'guest'});

  final LocalDatabase _database;
  final String ownerKey;
  Future<void> _writes = Future.value();

  @override
  Future<ShoppingSnapshot> load(List<Product> products) async {
    await _writes;
    final db = await _database.database;
    final productById = {for (final product in products) product.id: product};
    for (final product in await _database.cachedProducts()) {
      productById.putIfAbsent(product.id, () => product);
    }
    final cartRows = await db.query(
      'cart_items',
      where: 'owner_key = ?',
      whereArgs: [ownerKey],
      orderBy: 'cart_item_id',
    );
    final wishRows = await db.query(
      'favorites',
      columns: ['product_id'],
      where: 'owner_key = ?',
      whereArgs: [ownerKey],
      orderBy: 'created_at DESC',
    );
    final viewRows = await db.query(
      'product_views',
      columns: ['product_id'],
      where: 'owner_key = ?',
      whereArgs: [ownerKey],
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
    final next = _writes.then((_) => _saveSnapshot(snapshot));
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> _saveSnapshot(ShoppingSnapshot snapshot) async {
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      for (final table in ['cart_items', 'favorites', 'product_views']) {
        await txn.delete(table, where: 'owner_key = ?', whereArgs: [ownerKey]);
      }
      for (final item in snapshot.cart) {
        await txn.insert('cart_items', {
          'owner_key': ownerKey,
          'product_id': item.product.id,
          'color': item.color,
          'size': item.size,
          'quantity': item.quantity.clamp(1, 99),
          'added_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final productId in snapshot.wishedIds) {
        await txn.insert('favorites', {
          'owner_key': ownerKey,
          'product_id': productId,
          'created_at': now,
        });
      }
      // A larger view_id means a more recently viewed product.
      for (final productId in snapshot.recentIds.reversed) {
        await txn.insert('product_views', {
          'owner_key': ownerKey,
          'product_id': productId,
          'viewed_at': now,
        });
      }
    });
  }
}
