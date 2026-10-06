import '../domain/models.dart';
import 'dart:convert';
import '../domain/repositories.dart';
import 'local_database.dart';

/// Refreshes the device cache from the current source and uses it if that
/// source is unavailable. The mock source can later become a FastAPI source.
class SqliteCachedProductRepository
    implements ProductRepository, CatalogRepository {
  @override
  Future<CatalogMetadata> getCatalog() async {
    final source = _source;
    if (source is CatalogRepository) {
      final db = await _database.database;
      await db.execute(
        'CREATE TABLE IF NOT EXISTS catalog_metadata_cache (id INTEGER PRIMARY KEY,payload TEXT NOT NULL)',
      );
      try {
        final metadata = await (source as CatalogRepository).getCatalog();
        await db.rawInsert(
          'INSERT OR REPLACE INTO catalog_metadata_cache (id,payload) VALUES (1,?)',
          [
            jsonEncode({
              'categories': metadata.categories,
              'brands': metadata.brands,
            }),
          ],
        );
        return metadata;
      } catch (_) {
        final rows = await db.query('catalog_metadata_cache', where: 'id = 1');
        if (rows.isEmpty) rethrow;
        final json =
            jsonDecode(rows.single['payload'] as String)
                as Map<String, dynamic>;
        return CatalogMetadata(
          categories: (json['categories'] as Map<String, dynamic>).map(
            (key, value) => MapEntry(key, (value as List).cast<String>()),
          ),
          brands: (json['brands'] as Map<String, dynamic>).map(
            (key, value) => MapEntry(key, (value as List).cast<int>()),
          ),
        );
      }
    }
    return const CatalogMetadata(categories: {}, brands: {});
  }

  SqliteCachedProductRepository(this._database, this._source);

  final LocalDatabase _database;
  final ProductRepository _source;

  @override
  Future<List<Product>> getProducts() async {
    try {
      final products = await _source.getProducts();
      await _database.cacheProducts(products);
      return products;
    } catch (_) {
      final cached = await _database.cachedProducts();
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  /// 옵션 재고는 주문 가능 여부가 자주 바뀌므로 항상 원격 원본에서 조회합니다.
  @override
  Future<List<ProductOption>> getProductOptions(int productId) =>
      _source.getProductOptions(productId);
}
