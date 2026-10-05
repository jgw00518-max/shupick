import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shupick/app/store_binding.dart';
import 'package:shupick/app/shupick_app.dart';
import 'package:shupick/data/mock_repositories.dart';
import 'package:shupick/domain/models.dart';
import 'package:shupick/domain/repositories.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemorySettingsRepository implements SettingsRepository {
  String currentLanguage = '한국어';
  bool currentDark = false;
  bool currentPush = true;

  @override
  Future<String> language() async => currentLanguage;
  @override
  Future<bool> dark() async => currentDark;
  @override
  Future<bool> push() async => currentPush;
  @override
  Future<void> saveLanguage(String value) async => currentLanguage = value;
  @override
  Future<void> saveDark(bool value) async => currentDark = value;
  @override
  Future<void> savePush(bool value) async => currentPush = value;
}

void main() {
  tearDown(Get.reset);

  Future<void> pumpReady(WidgetTester tester) async {
    await tester.pumpWidget(
      ShupickApp(
        binding: StoreBinding(
          productsRepository: MockProductRepository(),
          accountRepository: MockAccountRepository(),
          reviewRepository: MockReviewRepository(),
          supportRepository: MockSupportRepository(),
          shoppingRepository: MockShoppingRepository(),
          settingsRepository: MemorySettingsRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('비회원 홈에서 상품과 마이페이지로 이동할 수 있다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpReady(tester);
    expect(find.text('SHOEPICK'), findsOneWidget);
    expect(find.text('기획전'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('로그인 / 회원가입'), findsOneWidget);
  });

  testWidgets('설정에서 영어를 선택하면 화면 문구가 전환된다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpReady(tester);
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('설정').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Dark mode'), findsOneWidget);
  });

  testWidgets('카테고리에서 성별과 신발 종류를 선택해 상품 목록으로 이동한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpReady(tester);
    await tester.tap(find.byTooltip('카테고리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('여성'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('스니커즈'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('캔버스/단화'));
    await tester.pumpAndSettle();
    expect(find.text('여성 · 캔버스/단화'), findsWidgets);
  });

  testWidgets('API 상품이 한 개여도 홈 기획전을 안전하게 표시한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ShupickApp(
        binding: StoreBinding(
          productsRepository: _SingleProductRepository(),
          accountRepository: MockAccountRepository(),
          reviewRepository: MockReviewRepository(),
          supportRepository: MockSupportRepository(),
          shoppingRepository: MockShoppingRepository(),
          settingsRepository: MemorySettingsRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('기획전'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _SingleProductRepository implements ProductRepository {
  @override
  Future<List<Product>> getProducts() async => const [
    Product(
      id: 1,
      name: 'Silver Current',
      category: '신발',
      price: 129000,
      imageUrl: 'https://example.com/black.jpg',
      color: '블랙',
      gender: '남성',
      middleCategory: '운동화',
      subcategory: '운동화',
      images: {'블랙': 'https://example.com/black.jpg'},
      reviewCount: 1,
      salesCount: 1,
    ),
  ];

  @override
  Future<List<ProductOption>> getProductOptions(int productId) async => const [
    ProductOption(
      productVariantId: 1,
      productCode: 'NK-M-SN-0001-BLK-250',
      color: '블랙',
      size: '250',
      availableQuantity: 20,
      inventoryStatus: 'AVAILABLE',
    ),
  ];
}
