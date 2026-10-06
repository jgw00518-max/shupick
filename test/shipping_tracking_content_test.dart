import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/presentation/shared/app_theme.dart';
import 'package:shupick/presentation/shared/shipping_tracking_content.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'NotoSansKR',
    )..addFont(rootBundle.load('assets/fonts/NotoSansKR-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  const code = 'ORD-20261006-C3D71064419E';
  Map<String, dynamic> snapshot(String status) => {
    'order_status': status,
    'order_number': code,
    'branch_name': 'SHOEPICK 강남구점',
    'address': '서울특별시 강남구 테헤란로 123 신발 쇼핑센터 2층',
    'phone': '02-1234-5678',
    'pickup_deadline_at': '2026-10-20T18:00:00',
    'businessHours': [
      {
        'day_of_week': 1,
        'opens_at': '10:00:00',
        'closes_at': '19:00:00',
        'is_closed': 0,
      },
      {'day_of_week': 7, 'opens_at': null, 'closes_at': null, 'is_closed': 1},
    ],
    'history': [
      {'new_status': 'PAID', 'changed_at': '2026-10-05T12:30:00'},
      {'new_status': status, 'changed_at': '2026-10-06T09:15:00'},
    ],
  };
  Future<void> pump(
    WidgetTester tester,
    String status, {
    bool confirmed = false,
    bool dark = false,
    GlobalKey? boundary,
    double width = 320,
    double scale = 1.3,
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
          debugShowCheckedModeBanner: false,
          theme: dark ? ShoepickTheme.dark() : ShoepickTheme.light(),
          home: Scaffold(
            appBar: AppBar(title: const Text('픽업 배송 조회')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ShippingTrackingContent(
                data: snapshot(status),
                purchaseConfirmed: confirmed,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('좁은 화면과 큰 글씨에서도 픽업 정보와 코드 복사를 유지한다', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pump(tester, 'READY_FOR_PICKUP');
    expect(find.text('2026.10.20  18:00'), findsOneWidget);
    await tester.ensureVisible(find.text('코드 복사'));
    await tester.tap(find.text('코드 복사'));
    await tester.pumpAndSettle();
    expect(copied, code);
    await tester.ensureVisible(find.text('10:00 - 19:00'));
    expect(find.text('휴무'), findsOneWidget);
    await tester.ensureVisible(find.text('상태 변경 이력'));
    expect(tester.takeException(), isNull);
  });
  testWidgets('완료와 취소 주문은 사용할 수 없는 픽업 코드를 노출하지 않는다', (tester) async {
    await pump(tester, 'COMPLETED', confirmed: true, dark: true);
    expect(find.text('코드 복사'), findsNothing);
    await tester.ensureVisible(find.text('상태 변경 이력'));
    expect(tester.takeException(), isNull);
    await pump(tester, 'CANCELED');
    expect(find.text('배송 진행 상황'), findsNothing);
    expect(find.text('코드 복사'), findsNothing);
    expect(find.text('취소된 주문입니다.'), findsOneWidget);
  });
  testWidgets('결제 대기는 배송 단계를 완료로 표시하지 않는다', (tester) async {
    await pump(tester, 'PENDING_PAYMENT');
    expect(find.text('현재'), findsNothing);
    expect(find.text('코드 복사'), findsNothing);
  });
  testWidgets('배송 조회 화면 미리보기', (tester) async {
    final boundary = GlobalKey();
    await pump(tester, 'SHIPPING', boundary: boundary, width: 393, scale: 1);
    final folder = Platform.environment['SHOEPICK_PREVIEW_DIR'];
    if (folder != null) {
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$folder/shipping-tracking.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
