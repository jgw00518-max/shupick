import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/domain/models.dart';
import 'package:shupick/presentation/screens/commerce_screens.dart';

void main() {
  testWidgets('실제 대리점 연락처·주소·요일별 시간을 표시한다', (tester) async {
    const branch = PickupBranch(
      id: 1,
      code: 'SD',
      name: '실제 성동 대리점',
      districtCode: 'SEOUL-SEONGDONG',
      districtName: '성동구',
      address: '서울시 실제 주소',
      phone: '02-1234-5678',
      businessHours: [
        {
          'dayOfWeek': 1,
          'isClosed': false,
          'opensAt': '10:00:00',
          'closesAt': '19:00:00',
        },
        {'dayOfWeek': 7, 'isClosed': true, 'opensAt': null, 'closesAt': null},
      ],
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PickupStoreInfo(district: '성동구', branch: branch),
        ),
      ),
    );
    expect(find.text('실제 성동 대리점'), findsOneWidget);
    expect(find.text('대리점 연락처 · 02-1234-5678'), findsOneWidget);
    expect(find.text('월요일 · 10:00 - 19:00'), findsOneWidget);
    expect(find.text('일요일 · 휴무'), findsOneWidget);
    expect(find.textContaining('목업'), findsNothing);
  });
  testWidgets('미등록 정보를 예시로 대체하지 않는다', (tester) async {
    const branch = PickupBranch(
      id: 1,
      code: 'SD',
      name: '대리점',
      districtCode: 'SD',
      districtName: '성동구',
      address: '',
      phone: '',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PickupStoreInfo(district: '성동구', branch: branch),
        ),
      ),
    );
    expect(find.text('운영시간 · 미등록'), findsOneWidget);
    expect(find.text('대리점 연락처 · 미등록'), findsOneWidget);
  });
}
