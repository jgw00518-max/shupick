import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shupick/data/local_database.dart';
import 'package:shupick/data/local_settings_repository.dart';
import 'package:shupick/data/sqlite_shopping_repository.dart';
import 'package:shupick/domain/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'settings migrate once and shopping state survives database reopening',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
            'language': 'English',
            'dark': true,
            'push': false,
          });
      final directory = await Directory.systemTemp.createTemp(
        'shupick_sqlite_',
      );
      final path = '${directory.path}/test.sqlite';
      final product = Product(
        id: 101,
        name: '테스트 신발',
        category: '운동화',
        price: 59000,
        imageUrl: 'shoe.png',
        color: '블랙',
        gender: '남성',
        images: const {'블랙': 'black.png'},
      );
      try {
        final firstDb = LocalDatabase(path: path);
        final settings = LocalSettingsRepository(database: firstDb);
        expect(await settings.language(), 'English');
        expect(await settings.dark(), isTrue);
        expect(await settings.push(), isFalse);
        await settings.saveDark(false);

        await firstDb.cacheProducts([product]);
        final shopping = SqliteShoppingRepository(firstDb);
        await shopping.save(
          ShoppingSnapshot(
            cart: [
              CartItem(product: product, size: '260', color: '블랙', quantity: 2),
            ],
            wishedIds: const {101},
            recentIds: const [101],
          ),
        );
        await firstDb.close();

        // Simulate an app restart, including a new repository and DB connection.
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.withData({'language': '한국어'});
        final reopenedDb = LocalDatabase(path: path);
        final reopenedSettings = LocalSettingsRepository(database: reopenedDb);
        expect(await reopenedSettings.language(), 'English');
        expect(await reopenedSettings.dark(), isFalse);
        expect(await reopenedSettings.push(), isFalse);
        final restored = await SqliteShoppingRepository(reopenedDb).load([]);
        expect(restored.cart.single.product.name, '테스트 신발');
        expect(restored.cart.single.quantity, 2);
        expect(restored.wishedIds, {101});
        expect(restored.recentIds, [101]);

        final member = SqliteShoppingRepository(
          reopenedDb,
          ownerKey: 'user:42',
        );
        expect((await member.load([])).cart, isEmpty);
        await reopenedDb.close();
      } finally {
        // The Windows SQLite native library may release the file handle just
        // after close returns. A locked temp file must not hide an assertion.
        try {
          await directory.delete(recursive: true);
        } on FileSystemException {
          // The OS temp directory will clean up the file later.
        }
      }
    },
  );
}
