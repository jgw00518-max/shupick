import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';

/// One on-device database. Server IDs in shopping tables are logical references;
/// only cached product options have a SQLite foreign key.
class LocalDatabase {
  LocalDatabase({this.path});

  static final LocalDatabase instance = LocalDatabase();
  final String? path;
  Future<Database>? _opening;

  Future<Database> get database => _opening ??= _open();

  Future<Database> _open() async {
    final databasePath =
        path ?? p.join(await getDatabasesPath(), 'shupick.sqlite');
    return openDatabase(
      databasePath,
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE app_settings (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            language TEXT NOT NULL DEFAULT '한국어',
            dark_mode INTEGER NOT NULL DEFAULT 0 CHECK (dark_mode IN (0, 1)),
            push_enabled INTEGER NOT NULL DEFAULT 1 CHECK (push_enabled IN (0, 1)),
            prefs_migrated INTEGER NOT NULL DEFAULT 0 CHECK (prefs_migrated IN (0, 1)),
            updated_at TEXT NOT NULL
          )
        ''');
        await db.insert('app_settings', {
          'id': 1,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
        await db.execute('''
          CREATE TABLE cached_products (
            product_id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            price INTEGER NOT NULL CHECK (price >= 0),
            image_url TEXT NOT NULL,
            color TEXT NOT NULL,
            gender TEXT NOT NULL,
            middle_category TEXT NOT NULL,
            subcategory TEXT NOT NULL,
            images_json TEXT NOT NULL,
            review_count INTEGER NOT NULL,
            sales_count INTEGER NOT NULL,
            cached_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_product_options (
            option_id INTEGER PRIMARY KEY,
            product_id INTEGER NOT NULL REFERENCES cached_products(product_id)
              ON DELETE CASCADE,
            color TEXT NOT NULL,
            size TEXT NOT NULL,
            image_url TEXT,
            UNIQUE (product_id, color, size)
          )
        ''');
        await db.execute('''
          CREATE TABLE recent_searches (
            search_id INTEGER PRIMARY KEY,
            owner_key TEXT NOT NULL,
            keyword TEXT NOT NULL,
            searched_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE product_views (
            view_id INTEGER PRIMARY KEY,
            owner_key TEXT NOT NULL,
            product_id INTEGER NOT NULL,
            viewed_at TEXT NOT NULL,
            UNIQUE (owner_key, product_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE favorites (
            owner_key TEXT NOT NULL,
            product_id INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            PRIMARY KEY (owner_key, product_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE cart_items (
            cart_item_id INTEGER PRIMARY KEY,
            owner_key TEXT NOT NULL,
            product_id INTEGER NOT NULL,
            color TEXT NOT NULL,
            size TEXT NOT NULL,
            quantity INTEGER NOT NULL CHECK (quantity BETWEEN 1 AND 99),
            added_at TEXT NOT NULL,
            UNIQUE (owner_key, product_id, color, size)
          )
        ''');
        await db.execute(
          'CREATE INDEX product_views_owner_order '
          'ON product_views(owner_key, view_id DESC)',
        );
        await db.execute(
          'CREATE INDEX recent_searches_owner_order '
          'ON recent_searches(owner_key, search_id DESC)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Apply future schema migrations here, one version at a time.
      },
    );
  }

  Future<void> cacheProducts(List<Product> products) async {
    final db = await database;
    final cachedAt = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      for (final product in products) {
        await txn.insert('cached_products', {
          'product_id': product.id,
          'name': product.name,
          'category': product.category,
          'price': product.price,
          'image_url': product.imageUrl,
          'color': product.color,
          'gender': product.gender,
          'middle_category': product.middleCategory,
          'subcategory': product.subcategory,
          'images_json': jsonEncode(product.images),
          'review_count': product.reviewCount,
          'sales_count': product.salesCount,
          'cached_at': cachedAt,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<Product>> cachedProducts() async {
    final db = await database;
    final rows = await db.query('cached_products', orderBy: 'product_id');
    return [
      for (final row in rows)
        Product(
          id: row['product_id'] as int,
          name: row['name'] as String,
          category: row['category'] as String,
          price: row['price'] as int,
          imageUrl: row['image_url'] as String,
          color: row['color'] as String,
          gender: row['gender'] as String,
          middleCategory: row['middle_category'] as String,
          subcategory: row['subcategory'] as String,
          images:
              (jsonDecode(row['images_json'] as String) as Map<String, dynamic>)
                  .map((key, value) => MapEntry(key, value as String)),
          reviewCount: row['review_count'] as int,
          salesCount: row['sales_count'] as int,
        ),
    ];
  }

  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  }
}
