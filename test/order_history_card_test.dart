import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/domain/models.dart';
import 'package:shupick/presentation/shared/app_theme.dart';
import 'package:shupick/presentation/shared/order_history_card.dart';

const item = CartItem(
  product: Product(
    id: 1,
    name: '에어 라이트 러너',
    category: '운동화',
    price: 89000,
    imageUrl: 'https://example.invalid/shoe.png',
    color: '화이트',
    gender: '공용',
  ),
  size: '260',
  color: '화이트',
);

void main() {
  setUpAll(() async {
    final font = FontLoader('NotoSansKR')
      ..addFont(rootBundle.load('assets/fonts/NotoSansKR-Variable.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  Future<void> pumpCard(
    WidgetTester tester,
    String status, {
    bool confirmed = false,
    bool reviewed = false,
    VoidCallback? onCode,
    VoidCallback? onConfirm,
    VoidCallback? onReview,
    double width = 320,
    double scale = 1.3,
    GlobalKey? boundary,
  }) async {
    tester.view.physicalSize = Size(width, 852);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          theme: ShoepickTheme.light(),
          home: Scaffold(
            appBar: AppBar(title: const Text('주문 내역')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: OrderHistoryCard(
                order: StoreOrder(
                  number: 'DEMO26-O013',
                  items: const [item],
                  date: DateTime(2026, 10, 5),
                  district: '성동구',
                  status: status,
                  paidTotal: 79000,
                  couponDiscount: 10000,
                  purchaseConfirmed: confirmed,
                ),
                onDetail: () {},
                onShipping: () {},
                onCode: onCode ?? () {},
                onConfirm: onConfirm ?? () {},
                onReturn: () {},
                onReview: (_) => onReview?.call(),
                hasReview: (_) => reviewed,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('픽업 대기 주문은 실제 결제액과 픽업 동작을 표시한다', (tester) async {
    var opened = false;
    await pumpCard(tester, 'READY_FOR_PICKUP', onCode: () => opened = true);
    expect(find.text('픽업 가능'), findsOneWidget);
    expect(find.text('79,000원'), findsOneWidget);
    expect(find.text('구매확정'), findsNothing);
    await tester.ensureVisible(find.text('픽업 코드'));
    await tester.tap(find.text('픽업 코드'));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('수령 완료와 구매확정의 행동을 구분한다', (tester) async {
    var confirmed = false;
    var codeOpened = false;
    await pumpCard(tester, 'COMPLETED', onConfirm: () => confirmed = true);
    expect(find.text('리뷰 작성 (1,000P)'), findsNothing);
    await tester.ensureVisible(find.text('구매확정'));
    await tester.tap(find.text('구매확정'));
    expect(confirmed, isTrue);
    expect(find.text('반품 신청'), findsOneWidget);
    await pumpCard(
      tester,
      'COMPLETED',
      confirmed: true,
      onCode: () => codeOpened = true,
    );
    final codeButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('픽업 코드'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(codeButton.onPressed, isNull);
    await tester.ensureVisible(find.text('픽업 코드'));
    await tester.tap(find.text('픽업 코드'));
    expect(codeOpened, isFalse);
    expect(find.text('구매확정 완료'), findsOneWidget);
    expect(find.text('리뷰 작성 (1,000P)'), findsOneWidget);
    expect(find.text('반품 신청'), findsNothing);
    await pumpCard(tester, 'REFUNDED');
    expect(find.text('환불 완료'), findsOneWidget);
    expect(find.text('픽업 코드'), findsNothing);
    expect(find.text('구매확정'), findsNothing);
  });
  testWidgets('주문 카드 미리보기: 일반 휴대폰 화면', (tester) async {
    final boundary = GlobalKey();
    await pumpCard(
      tester,
      'READY_FOR_PICKUP',
      width: 393,
      scale: 1,
      boundary: boundary,
    );
    final folder = Platform.environment['SHOEPICK_PREVIEW_DIR'];
    if (folder != null) {
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$folder/order-history.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
