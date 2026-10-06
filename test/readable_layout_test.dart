import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shupick/app/shupick_app.dart';
import 'package:shupick/app/store_binding.dart';
import 'package:shupick/app/store_navigation_controller.dart';
import 'package:shupick/data/mock_repositories.dart';
import 'package:shupick/presentation/store_shell.dart';
import 'package:shupick/presentation/shared/store_widgets.dart';
import 'widget_test.dart' show MemorySettingsRepository;

void main() {
  setUpAll(() async {
    final loader = FontLoader('NotoSansKR')
      ..addFont(rootBundle.load('assets/fonts/NotoSansKR-Variable.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  tearDown(Get.reset);
  for (final width in [320.0, 393.0]) {
    testWidgets('주요 화면의 실제 글꼴과 확대 글자는 잘리지 않는다: $width', (tester) async {
      tester.view.physicalSize = Size(width, 852);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = width == 320
          ? 1.3
          : 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      SharedPreferences.setMockInitialValues({});
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ShupickApp(
            binding: StoreBinding(
              productsRepository: MockProductRepository(),
              accountRepository: MockAccountRepository(),
              reviewRepository: MockReviewRepository(),
              supportRepository: MockSupportRepository(),
              shoppingRepository: MockShoppingRepository(),
              settingsRepository: MemorySettingsRepository(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      Future<void> capture(String name) async {
        final folder = Platform.environment['SHOEPICK_PREVIEW_DIR'];
        if (folder == null || width != 393) return;
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$folder/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      await tester.runAsync(() => capture('home-readability'));
      Get.find<StoreNavigationController>().go(StorePage.catalog);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => capture('catalog-readability'));
      await tester.tap(find.byType(ProductCard).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => capture('detail-readability'));
      await tester.tap(find.text('구매하기').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => capture('options-readability'));
      Get.back();
      await tester.pumpAndSettle();
      Get.find<StoreNavigationController>().go(StorePage.profile);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
