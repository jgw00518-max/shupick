import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shupick/app/store_controller.dart';
import 'package:shupick/data/mock_repositories.dart';
import 'package:shupick/domain/models.dart';
import 'package:shupick/presentation/screens/commerce_screens.dart';
import 'package:shupick/presentation/shared/app_theme.dart';

class SeoulBranchesRepository extends MockOrderRepository {
  @override
  Future<List<PickupBranch>> getPickupBranches() async => [
    for (var index = 0; index < pickupDistricts.length; index++)
      PickupBranch(
        id: index + 1,
        code: 'SEL-$index',
        name:
            'SHOEPICK ${pickupDistricts[index] == '중구' ? '중구' : pickupDistricts[index].replaceFirst(RegExp(r'구$'), '')}점',
        districtCode: 'DISTRICT-$index',
        districtName: pickupDistricts[index],
        address: '서울특별시 ${pickupDistricts[index]} 가상로 ${101 + index}, 1층',
        phone: '02-0000-${1001 + index}',
        businessHours: [
          for (var day = 1; day <= 7; day++)
            {
              'dayOfWeek': day,
              'isClosed': day == 7,
              'opensAt': day == 7 ? null : '10:30:00',
              'closesAt': day == 7 ? null : '20:00:00',
            },
        ],
      ),
  ];
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'NotoSansKR',
    )..addFont(rootBundle.load('assets/fonts/NotoSansKR-Variable.ttf'))).load();
  });

  testWidgets('서울 25개 구가 선택 가능하고 변경 시 해당 지점·가상 연락처·운영시간을 표시한다', (tester) async {
    tester.view.physicalSize = const Size(440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const product = Product(
      id: 100,
      name: 'SHOEPICK 러너',
      category: '스포츠',
      price: 89000,
      imageUrl: 'https://example.invalid/shoe.png',
      color: '블랙',
      gender: '공용',
    );
    final store = StoreController(
      productsRepository: MockProductRepository(),
      accountRepository: MockAccountRepository(),
      orderRepository: SeoulBranchesRepository(),
      reviewRepository: MockReviewRepository(),
      shoppingRepository: MockShoppingRepository(),
      supportRepository: MockSupportRepository(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ShoepickTheme.light(),
        home: Scaffold(
          body: CheckoutScreen(
            store: store,
            lines: const [CartItem(product: product, size: '250', color: '블랙')],
            fromCart: false,
            onComplete: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>).first,
    );
    expect(field.items, hasLength(25));
    expect(
      field.items!.map((item) => item.value).toSet(),
      pickupDistricts.toSet(),
    );
    expect(field.onChanged, isNotNull);
    field.onChanged!('강남구');
    await tester.pumpAndSettle();
    expect(find.text('SHOEPICK 강남점'), findsOneWidget);
    expect(find.text('주소 · 서울특별시 강남구 가상로 101, 1층'), findsOneWidget);
    expect(find.text('대리점 연락처 · 02-0000-1001'), findsOneWidget);
    expect(find.text('월요일 · 10:30 - 20:00'), findsOneWidget);
    expect(find.text('토요일 · 10:30 - 20:00'), findsOneWidget);
    expect(find.text('일요일 · 휴무'), findsOneWidget);
    field.onChanged!('중랑구');
    await tester.pumpAndSettle();
    expect(find.text('SHOEPICK 중랑점'), findsOneWidget);
    expect(find.text('SHOEPICK 강남점'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
