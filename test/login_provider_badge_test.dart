import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/domain/repositories.dart';
import 'package:shupick/presentation/shared/login_provider_badge.dart';

Future<void> _showBadge(
  WidgetTester tester,
  AccountLoginProvider? provider, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(child: LoginProviderBadge(provider: provider)),
        ),
      ),
    ),
  );
}

void main() {
  for (final provider in [
    AccountLoginProvider.kakao,
    AccountLoginProvider.naver,
    AccountLoginProvider.google,
  ]) {
    testWidgets('$provider sign-in mark keeps the button tooltip unique', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IconButton(
              tooltip: '서비스 로그인',
              onPressed: () {},
              icon: LoginProviderBadge.signInButton(provider: provider),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(LoginProviderBadge)),
        const Size(32, 32),
      );
      expect(find.byType(Tooltip), findsOneWidget);
      expect(find.text('K'), findsNothing);
      expect(find.text('k'), findsNothing);
      expect(find.text('G'), findsNothing);
      if (provider == AccountLoginProvider.naver) {
        expect(find.text('N'), findsOneWidget);
      } else {
        expect(
          find.descendant(
            of: find.byType(LoginProviderBadge),
            matching: find.byType(CustomPaint),
          ),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final provider in [null, AccountLoginProvider.email]) {
    testWidgets('$provider does not show a social login badge', (tester) async {
      await _showBadge(tester, provider);
      expect(find.byType(Tooltip), findsNothing);
      expect(tester.getSize(find.byType(LoginProviderBadge)), Size.zero);
    });
  }

  const labels = {
    AccountLoginProvider.kakao: '카카오 로그인',
    AccountLoginProvider.naver: '네이버 로그인',
    AccountLoginProvider.google: '구글 로그인',
  };
  for (final entry in labels.entries) {
    for (final brightness in Brightness.values) {
      testWidgets('${entry.key} is accessible and compact in $brightness', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        try {
          await _showBadge(
            tester,
            entry.key,
            brightness: brightness,
            textScale: 3,
          );
          expect(
            tester.getSize(find.byType(LoginProviderBadge)),
            const Size(24, 24),
          );
          expect(find.byTooltip(entry.value), findsOneWidget);
          expect(find.bySemanticsLabel(entry.value), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  testWidgets('Kakao uses a lowercase k and its yellow background', (
    tester,
  ) async {
    await _showBadge(tester, AccountLoginProvider.kakao);
    expect(find.text('k'), findsOneWidget);
    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(LoginProviderBadge),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect((box.decoration as BoxDecoration).color, const Color(0xFFFEE500));
  });

  testWidgets('Naver uses a white N on its green background', (tester) async {
    await _showBadge(tester, AccountLoginProvider.naver);
    final text = tester.widget<Text>(find.text('N'));
    expect(text.style?.color, Colors.white);
    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(LoginProviderBadge),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect((box.decoration as BoxDecoration).color, const Color(0xFF03C75A));
  });

  testWidgets('Google paints the multicolor mark without an image download', (
    tester,
  ) async {
    await _showBadge(tester, AccountLoginProvider.google);
    expect(
      find.descendant(
        of: find.byType(LoginProviderBadge),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    expect(find.byType(Image), findsNothing);
  });
}
