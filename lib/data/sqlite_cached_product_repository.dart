import '../domain/models.dart';
import '../domain/repositories.dart';
import 'local_database.dart';

/// Refreshes the device cache from the current source and uses it if that
/// source is unavailable. The mock source can later become a FastAPI source.
class SqliteCachedProductRepository implements ProductRepository {
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
}
