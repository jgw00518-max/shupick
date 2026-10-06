import 'package:get/get.dart';

import '../data/api_product_repository.dart';
import '../data/api_order_repository.dart';
import '../data/firebase_account_repository.dart';
import '../data/local_database.dart';
import '../data/local_settings_repository.dart';
import '../data/api_support_repository.dart';
import '../data/api_review_repository.dart';
import '../data/api_interaction_repository.dart';
import '../data/sqlite_cached_product_repository.dart';
import '../data/sqlite_shopping_repository.dart';
import '../domain/repositories.dart';
import 'store_controller.dart';
import 'store_navigation_controller.dart';

/// 앱에서 사용하는 저장소와 GetX 컨트롤러의 생성 책임을 모읍니다.
class StoreBinding extends Bindings {
  StoreBinding({
    this.productsRepository,
    this.accountRepository,
    this.shoppingRepository,
    this.settingsRepository,
    this.reviewRepository,
    this.interactionRepository,
    this.supportRepository,
  });

  final ProductRepository? productsRepository;
  final AccountRepository? accountRepository;
  final ShoppingRepository? shoppingRepository;
  final SettingsRepository? settingsRepository;
  final ReviewRepository? reviewRepository;
  final InteractionRepository? interactionRepository;
  final SupportRepository? supportRepository;

  @override
  void dependencies() {
    Get.lazyPut<ProductRepository>(
      () =>
          productsRepository ??
          SqliteCachedProductRepository(
            LocalDatabase.instance,
            ApiProductRepository(),
          ),
    );
    Get.lazyPut<AccountRepository>(
      () => accountRepository ?? FirebaseAccountRepository(),
    );
    Get.lazyPut<OrderRepository>(
      () => ApiOrderRepository(productsRepository: Get.find()),
    );
    Get.lazyPut<ReviewRepository>(
      () => reviewRepository ?? ApiReviewRepository(),
    );
    Get.lazyPut<ShoppingRepository>(
      () =>
          shoppingRepository ??
          SqliteShoppingRepository(LocalDatabase.instance),
    );
    Get.lazyPut<SettingsRepository>(
      () => settingsRepository ?? LocalSettingsRepository(),
    );
    Get.lazyPut<SupportRepository>(
      () => supportRepository ?? ApiSupportRepository(),
    );
    Get.put(StoreNavigationController());
    Get.put(
      StoreController(
        productsRepository: Get.find(),
        accountRepository: Get.find(),
        orderRepository: Get.find(),
        reviewRepository: Get.find(),
        shoppingRepository: Get.find(),
        supportRepository: Get.find(),
        interactionRepository:
            interactionRepository ??
            (accountRepository == null
                ? ApiInteractionRepository(LocalDatabase.instance)
                : null),
      ),
    );
  }
}
