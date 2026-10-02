import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shupick/app/store_binding.dart';
import 'package:shupick/app/shupick_app.dart';
import 'package:shupick/data/mock_repositories.dart';
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
    expect(find.text('SHUPICK'), findsOneWidget);
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
}
