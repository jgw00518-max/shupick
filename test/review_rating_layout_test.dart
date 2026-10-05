import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/presentation/localization.dart';
import 'package:shupick/presentation/shared/app_theme.dart';
import 'package:shupick/presentation/screens/public_reviews.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('리뷰 별점은 작은 화면과 확대 글자에서도 표시된다: dark=$dark', (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? ShoepickTheme.dark() : ShoepickTheme.light(),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.4)),
              child: LocaleScope(
                language: dark ? 'English' : '한국어',
                child: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: PublicReviews(
                      data: {
                        'count': 2,
                        'average': 3.5,
                        'hasMore': true,
                        'items': [
                          {
                            'id': 1,
                            'rating': 3,
                            'color': '오프화이트',
                            'size': 250,
                            'fitSize': '정사이즈',
                            'fitWidth': '적당함',
                            'fitComfort': '편함',
                            'content': '사이즈가 잘 맞고 매장에서 편하게 수령했습니다.',
                            'photos': [],
                          },
                        ],
                      },
                      loading: false,
                      error: null,
                      onReload: () {},
                      onMore: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.star_half_rounded), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(6));
      expect(find.byIcon(Icons.star_outline_rounded), findsNWidgets(3));
      expect(
        find.bySemanticsLabel(dark ? 'Rating 3.5 out of 5' : '평점 5점 만점에 3.5점'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}
