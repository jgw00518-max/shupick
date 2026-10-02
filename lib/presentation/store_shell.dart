import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'localization.dart';

import '../app/store_controller.dart';
import '../app/store_navigation_controller.dart';
import '../data/mock_repositories.dart';
import '../data/local_settings_repository.dart';
import '../domain/models.dart';
import 'screens/account_screens.dart';
import 'screens/catalog_screens.dart';
import 'screens/commerce_screens.dart';
import 'screens/inquiry_screen.dart';
import 'screens/product_detail_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/support_screens.dart';
import 'shared/store_widgets.dart';

enum StorePage {
  home,
  catalog,
  search,
  campaign,
  detail,
  recent,
  wish,
  cart,
  checkout,
  profile,
  auth,
  orders,
  shipping,
  coupons,
  points,
  inquiry,
  settings,
}

/// 목업의 탭과 뒤로 가기 흐름을 한곳에서 관리합니다.
class StoreShell extends StatefulWidget {
  const StoreShell({super.key});
  @override
  State<StoreShell> createState() => _StoreShellState();
}

class _StoreShellState extends State<StoreShell> {
  final StoreController store = Get.find<StoreController>();
  final StoreNavigationController navigation =
      Get.find<StoreNavigationController>();
  final settings = LocalSettingsRepository();
  Product? selected;
  String campaign = '이번 주 특가';
  String? catalogGender;
  String catalogMiddle = '스니커즈';
  String catalogSubcategory = '전체';
  String drawerGender = '남성';
  String? drawerMiddle;
  List<CartItem> checkoutLines = [];
  bool checkoutFromCart = false;
  String? selectedOrderNumber = 'SS0928-1842';
  Product? inquiryProduct;
  bool dark = false;
  String language = '한국어';
  bool push = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final values = await Future.wait<Object>([
        settings.language(),
        settings.dark(),
        settings.push(),
      ]);
      if (mounted) {
        setState(() {
          language = values[0] as String;
          dark = values[1] as bool;
          push = values[2] as bool;
        });
      }
    } catch (_) {
      /* 저장소가 없어도 목업 화면은 사용할 수 있습니다. */
    }
  }

  void _saveSetting(Future<void> Function() save) {
    try {
      unawaited(save().catchError((Object _) {}));
    } catch (_) {
      /* 플러그인 없는 테스트에서도 설정 UI는 작동합니다. */
    }
  }

  void go(StorePage next) => navigation.go(next);

  void back() => navigation.back();

  StorePage get page => navigation.page;
  void openProduct(Product product) {
    store.view(product);
    selected = product;
    go(StorePage.detail);
  }

  void startCheckout(List<CartItem> lines, {bool fromCart = false}) {
    checkoutLines = List.of(lines);
    checkoutFromCart = fromCart;
    go(StorePage.checkout);
  }

  void openCatalog({
    String? gender,
    String middle = '스니커즈',
    String subcategory = '전체',
  }) {
    catalogGender = gender;
    catalogMiddle = middle;
    catalogSubcategory = subcategory;
    go(StorePage.catalog);
  }

  void message(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: LText(text)));

  String get title => switch (page) {
    StorePage.home => 'SHUPICK',
    StorePage.catalog => '전체 상품',
    StorePage.search => '검색',
    StorePage.campaign => campaign,
    StorePage.detail => '상품 상세',
    StorePage.recent => '최근 본 상품',
    StorePage.wish => '찜한 상품',
    StorePage.cart => '장바구니',
    StorePage.checkout => '주문하기',
    StorePage.profile => '마이페이지',
    StorePage.auth => '로그인 / 회원가입',
    StorePage.orders => '주문 내역',
    StorePage.shipping => '배송 조회',
    StorePage.coupons => '쿠폰',
    StorePage.points => '포인트',
    StorePage.inquiry => '고객센터',
    StorePage.settings => '설정',
  };

  bool get largerProductText => {
    StorePage.home,
    StorePage.catalog,
    StorePage.search,
    StorePage.campaign,
    StorePage.detail,
    StorePage.recent,
    StorePage.wish,
    StorePage.cart,
    StorePage.checkout,
    StorePage.orders,
  }.contains(page);

  @override
  Widget build(BuildContext context) => GetBuilder<StoreNavigationController>(
    builder: (_) => GetBuilder<StoreController>(
      builder: (_) => LocaleScope(
        language: language,
        child: Theme(
          data: dark ? ThemeData.dark(useMaterial3: true) : Theme.of(context),
          child: Scaffold(
            appBar: page == StorePage.auth
                ? null
                : AppBar(
                    backgroundColor: dark ? null : Colors.white,
                    surfaceTintColor: Colors.transparent,
                    elevation: 0,
                    toolbarHeight: 60,
                    titleSpacing: 0,
                    leading: page == StorePage.home
                        ? Builder(
                            builder: (context) => IconButton(
                              tooltip: '카테고리',
                              icon: const Icon(Icons.menu),
                              onPressed: () =>
                                  Scaffold.of(context).openDrawer(),
                            ),
                          )
                        : IconButton(
                            tooltip: '뒤로 가기',
                            icon: const Icon(Icons.arrow_back),
                            onPressed: back,
                          ),
                    title: page == StorePage.home
                        ? const Text(
                            'SHUPICK',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.5,
                            ),
                          )
                        : null,
                    actions: [
                      IconButton(
                        tooltip: '검색',
                        icon: const Icon(Icons.search),
                        onPressed: () => go(StorePage.search),
                      ),
                      Badge(
                        isLabelVisible: store.cartCount > 0,
                        label: LText('${store.cartCount}'),
                        child: IconButton(
                          tooltip: '장바구니',
                          icon: const Icon(Icons.shopping_bag_outlined),
                          onPressed: () => go(StorePage.cart),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
            drawer: page == StorePage.auth ? null : _drawer(),
            body: store.loading
                ? const Center(child: CircularProgressIndicator())
                : store.loadError != null
                ? EmptyState(
                    store.loadError!,
                    action: '다시 시도',
                    onAction: store.load,
                  )
                : largerProductText
                ? MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(1.3)),
                    child: _body(),
                  )
                : _body(),
            bottomNavigationBar: page == StorePage.auth
                ? null
                : BottomNavigationBar(
                    type: BottomNavigationBarType.fixed,
                    backgroundColor: dark ? null : Colors.white,
                    selectedItemColor: brandBlue,
                    unselectedItemColor: const Color(0xFF888888),
                    selectedFontSize: 12,
                    unselectedFontSize: 12,
                    iconSize: 25,
                    elevation: 4,
                    currentIndex: switch (page) {
                      StorePage.recent => 1,
                      StorePage.wish => 2,
                      StorePage.profile ||
                      StorePage.orders ||
                      StorePage.shipping ||
                      StorePage.coupons ||
                      StorePage.points ||
                      StorePage.inquiry ||
                      StorePage.settings => 3,
                      _ => 0,
                    },
                    onTap: (index) => go(
                      [
                        StorePage.home,
                        StorePage.recent,
                        StorePage.wish,
                        StorePage.profile,
                      ][index],
                    ),
                    items: const [
                      BottomNavigationBarItem(
                        icon: Icon(Icons.home_outlined),
                        label: '홈',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.history),
                        label: '최근 본 상품',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.favorite_border),
                        label: '찜목록',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.person_outline),
                        label: '마이페이지',
                      ),
                    ],
                  ),
          ),
        ),
      ),
    ),
  );

  Widget _body() => switch (page) {
    StorePage.home => HomeScreen(
      store: store,
      onOpen: openProduct,
      onCampaign: (name) {
        campaign = name;
        go(StorePage.campaign);
      },
    ),
    StorePage.catalog => CatalogScreen(
      key: ValueKey('$catalogGender-$catalogMiddle-$catalogSubcategory'),
      store: store,
      onOpen: openProduct,
      initialGender: catalogGender,
      initialMiddle: catalogMiddle,
      initialSubcategory: catalogSubcategory,
    ),
    StorePage.search => SearchScreen(store: store, onOpen: openProduct),
    StorePage.campaign => CampaignScreen(
      title: campaign,
      store: store,
      onOpen: openProduct,
    ),
    StorePage.detail => ProductDetailScreen(
      key: ValueKey(selected!.id),
      product: selected!,
      store: store,
      onCart: () => go(StorePage.cart),
      onBuy: startCheckout,
      onOpenProduct: openProduct,
      onInquiry: () {
        inquiryProduct = selected;
        go(StorePage.inquiry);
      },
      onMessage: message,
    ),
    StorePage.wish => ProductCollectionScreen(
      title: '찜한 상품',
      products: store.wished,
      store: store,
      onOpen: openProduct,
      canRemove: true,
    ),
    StorePage.recent => ProductCollectionScreen(
      title: '최근 본 상품',
      products: store.recent,
      store: store,
      onOpen: openProduct,
    ),
    StorePage.cart => CartScreen(
      store: store,
      onOpen: openProduct,
      onCheckout: (lines) => startCheckout(lines, fromCart: true),
      onMessage: message,
    ),
    StorePage.checkout => CheckoutScreen(
      store: store,
      lines: checkoutLines,
      fromCart: checkoutFromCart,
      onComplete: () {
        go(StorePage.orders);
      },
    ),
    StorePage.profile => ProfileScreen(
      store: store,
      onGo: (next) {
        if (next == StorePage.inquiry) inquiryProduct = null;
        go(next);
      },
      onLogout: () {
        store.signOut();
        navigation.resetTo(StorePage.profile);
      },
    ),
    StorePage.auth => AuthScreen(
      store: store,
      onBack: back,
      onDone: () => go(StorePage.profile),
      onMessage: message,
    ),
    StorePage.orders => OrdersScreen(
      store: store,
      onMessage: message,
      onShipping: (order) {
        selectedOrderNumber = order.number;
        go(StorePage.shipping);
      },
    ),
    StorePage.shipping => ShippingScreen(
      store: store,
      order: store.orders
          .where((o) => o.number == selectedOrderNumber)
          .firstOrNull,
      onOrders: () => go(StorePage.orders),
    ),
    StorePage.coupons => const CouponsScreen(),
    StorePage.points => const PointsScreen(),
    StorePage.inquiry => InquiryScreen(
      store: store,
      product: inquiryProduct,
      onMessage: message,
    ),
    StorePage.settings => SettingsScreen(
      dark: dark,
      language: language,
      push: push,
      onDarkChanged: (value) {
        setState(() => dark = value);
        _saveSetting(() => settings.saveDark(value));
      },
      onLanguageChanged: (value) {
        setState(() => language = value);
        _saveSetting(() => settings.saveLanguage(value));
      },
      onPushChanged: (value) {
        setState(() => push = value);
        _saveSetting(() => settings.savePush(value));
      },
    ),
  };

  Widget _drawer() => Drawer(
    width: 320,
    backgroundColor: dark ? null : Colors.white,
    child: SafeArea(
      child: ListView(
        children: [
          ListTile(
            title: const LText(
              '카테고리',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Row(
              children: [
                for (final gender in ['남성', '여성', '키즈'])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: OutlinedButton(
                        onPressed: () => setState(() {
                          drawerGender = gender;
                          drawerMiddle = null;
                        }),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: drawerGender == gender
                              ? const Color(0xFF455B77)
                              : Colors.white,
                          side: BorderSide(
                            color: drawerGender == gender
                                ? const Color(0xFF455B77)
                                : const Color(0xFFEAEAEA),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: LText(
                          gender,
                          style: TextStyle(
                            fontSize: 12,
                            color: drawerGender == gender
                                ? Colors.white
                                : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 6, 20, 12),
            child: LText(
              '신발 종류',
              style: TextStyle(color: Color(0xFF999999), fontSize: 12),
            ),
          ),
          for (final entry in MockProductRepository.categoryTree.entries) ...[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: LText(entry.key),
              trailing: Icon(
                drawerMiddle == entry.key ? Icons.remove : Icons.add,
              ),
              onTap: () => setState(
                () =>
                    drawerMiddle = drawerMiddle == entry.key ? null : entry.key,
              ),
            ),
            const Divider(height: 1, indent: 20, endIndent: 20),
            if (drawerMiddle == entry.key)
              for (final sub in ['전체', ...entry.value])
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 32, right: 16),
                  title: LText(sub),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).pop();
                    openCatalog(
                      gender: drawerGender,
                      middle: entry.key,
                      subcategory: sub,
                    );
                    setState(() => drawerMiddle = null);
                  },
                ),
          ],
        ],
      ),
    ),
  );
}
