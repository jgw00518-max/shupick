import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/presentation/screens/public_reviews.dart';
import 'package:shupick/domain/models.dart';

void main() {
  testWidgets('본인 리뷰에만 수정·삭제 버튼을 표시한다', (tester) async {
    const owned = ProductReview(
      id: 1,
      orderNumber: 'ORD',
      itemKey: 'key',
      rating: 5,
      content: '내 후기',
    );
    ProductReview? edited;
    ProductReview? deleted;
    Map<String, dynamic> row(int id) => {
      'id': id,
      'rating': 5,
      'color': '블랙',
      'size': 250,
      'fitSize': '정사이즈',
      'fitWidth': '적당함',
      'fitComfort': '편함',
      'content': '후기',
      'photos': [],
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PublicReviews(
              data: {
                'count': 2,
                'average': 5,
                'items': [row(1), row(2)],
                'hasMore': false,
              },
              loading: false,
              error: null,
              onReload: () {},
              onMore: () {},
              ownedReviews: const {1: owned},
              onEdit: (review) {
                edited = review;
              },
              onDelete: (review) {
                deleted = review;
              },
            ),
          ),
        ),
      ),
    );
    expect(find.text('내 리뷰'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(15));
    expect(find.text('수정'), findsOneWidget);
    expect(find.text('삭제'), findsOneWidget);
    await tester.tap(find.text('수정'));
    await tester.tap(find.text('삭제'));
    expect(edited, same(owned));
    expect(deleted, same(owned));
  });
  testWidgets('실제 평점과 빈 리뷰 상태를 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PublicReviews(
            data: {'count': 0, 'average': 0, 'items': [], 'hasMore': false},
            loading: false,
            error: null,
            onReload: () {},
            onMore: () {},
          ),
        ),
      ),
    );
    expect(find.text('등록된 리뷰가 없습니다.'), findsOneWidget);
    expect(find.text('리뷰 0'), findsOneWidget);
    expect(find.text('0.0'), findsOneWidget);
    expect(find.byIcon(Icons.star_outline_rounded), findsNWidgets(5));
  });
  testWidgets('조회 실패 시 재시도를 제공한다', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PublicReviews(
            data: null,
            loading: false,
            error: 'offline',
            onReload: () {
              retried = true;
            },
            onMore: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('다시 시도'));
    expect(retried, isTrue);
  });
}
