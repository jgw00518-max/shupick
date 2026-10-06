import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../localization.dart';

import '../../app/store_controller.dart';
import '../../data/mock_repositories.dart';
import '../../domain/models.dart';
import '../shared/store_widgets.dart';

const searchCategories = ['전체', '운동화', '구두', '로퍼', '부츠', '샌들', '슬리퍼'];
const campaignData = <String, ({String subtitle, List<int> ids})>{
  '이번 주 특가': (subtitle: '가볍게 시작하는 쇼핑', ids: [5, 6, 14, 19]),
  '매일 신기 좋은 신발': (subtitle: '일상에 자연스럽게 어울리는 선택', ids: [1, 9, 10, 16]),
  '이달의 추천 신발': (subtitle: '요즘 날씨에 어울리는 스타일', ids: [3, 12, 15, 21]),
};

/// 원본 홈의 기획전 진입과 각 기획전 상품 묶음을 재현합니다.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.store,
    required this.onOpen,
    required this.onCampaign,
  });
  final StoreController store;
  final void Function(Product) onOpen;
  final void Function(String) onCampaign;

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 264,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  mockHeroImage,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: Color(0xFFE7E8E6)),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.bottomLeft,
                      colors: [Colors.transparent, Color(0x88000000)],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const LText(
                        'THE EVERYDAY EDIT',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const LText(
                        '오늘의 발걸음,\n나만의 스타일.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 17),
                      FilledButton(
                        onPressed: () => onCampaign('매일 신기 좋은 신발'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const LText('컬렉션 보기'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(18, 26, 18, 16),
        child: SectionTitle('기획전'),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in campaignData.entries)
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => onCampaign(entry.key),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 88,
                            height: 88,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                            ),
                            child: Image.network(
                              _campaignImage(store, entry.value.ids.first),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.image_outlined,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          LText(
                            entry.key,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      for (final entry in campaignData.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 28, 18, 4),
          child: SectionTitle(
            entry.key,
            action: '더 보기 ›',
            onAction: () => onCampaign(entry.key),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: LText(
            entry.value.subtitle,
            style: const TextStyle(color: Color(0xFF777777), fontSize: 14),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = ((constraints.maxWidth - 48) / 2)
                  .clamp(140.0, 220.0)
                  .toDouble();
              return SizedBox(
                height: ProductCard.gridHeight(context, cardWidth, false) + 4,
                child: ListView.builder(
                  key: ValueKey('campaign-products-${entry.key}'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  itemCount: entry.value.ids.length,
                  itemBuilder: (context, index) {
                    final product = store.products.firstWhere(
                      (p) => p.id == entry.value.ids[index],
                    );
                    return Padding(
                      padding: EdgeInsets.only(
                        right: index < entry.value.ids.length - 1 ? 12 : 0,
                      ),
                      child: SizedBox(
                        width: cardWidth,
                        child: ProductCard(
                          product: product,
                          store: store,
                          onOpen: () => onOpen(product),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
      _HomeNewArrivals(store: store, onOpen: onOpen),
      _BrandBestProducts(store: store, onOpen: onOpen),
    ],
  );
}

class _BrandBestProducts extends StatelessWidget {
  const _BrandBestProducts({required this.store, required this.onOpen});
  final StoreController store;
  final void Function(Product) onOpen;

  @override
  Widget build(BuildContext context) {
    final ranked = List<Product>.of(store.products)
      ..sort((a, b) {
        final sales = b.salesCount.compareTo(a.salesCount);
        return sales != 0 ? sales : a.id.compareTo(b.id);
      });
    final products = ranked.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 12, 18, 16),
          child: LText(
            '브랜드별 베스트 상품',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Chip(label: LText('전체'), shape: StadiumBorder()),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = ((constraints.maxWidth - 48) / 2)
                .clamp(140.0, 220.0)
                .toDouble();
            return SizedBox(
              height: ProductCard.gridHeight(context, width, false) + 4,
              child: ListView.builder(
                key: const ValueKey('brand-best-products'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: products.length,
                itemBuilder: (_, index) => Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: width,
                    child: Stack(
                      children: [
                        ProductCard(
                          product: products[index],
                          store: store,
                          onOpen: () => onOpen(products[index]),
                        ),
                        Positioned(
                          left: 0,
                          top: 0,
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: const BoxDecoration(
                                color: brandBlue,
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(12),
                                  bottomRight: Radius.circular(8),
                                ),
                              ),
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 28),
      ],
    );
  }
}

class _HomeNewArrivals extends StatefulWidget {
  const _HomeNewArrivals({required this.store, required this.onOpen});
  final StoreController store;
  final void Function(Product) onOpen;

  @override
  State<_HomeNewArrivals> createState() => _HomeNewArrivalsState();
}

class _HomeNewArrivalsState extends State<_HomeNewArrivals> {
  int page = 0;
  String category = '운동화';
  final pages = PageController();

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.store.products.isEmpty) return const SizedBox.shrink();
    final products = widget.store.products;
    final featured = [
      for (final id in [1, 3, 9, 12])
        products.firstWhere((p) => p.id == id, orElse: () => products.first),
    ];
    final selection = products
        .where((p) => p.category == category)
        .take(8)
        .toList();
    final scaler = MediaQuery.textScalerOf(context);
    final bannerHeight =
        60 + scaler.scale(20) * 2 * 1.3 + scaler.scale(13) * 2 * 1.4;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 40, 18, 24),
          child: LText(
            '새로운 상품 발매 소식',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          height: bannerHeight * 2 + 12,
          child: PageView.builder(
            key: const ValueKey('release-news-pages'),
            controller: pages,
            itemCount: 2,
            onPageChanged: (value) => setState(() => page = value),
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                children: [
                  for (var row = 0; row < 2; row++) ...[
                    if (row > 0) const SizedBox(height: 12),
                    SizedBox(
                      height: bannerHeight,
                      child: _releaseBanner(
                        featured[index * 2 + row],
                        row == 0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < 2; index++)
              IconButton(
                tooltip: '발매 소식 ${index + 1}페이지',
                onPressed: () => pages.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                ),
                icon: Icon(
                  Icons.circle,
                  size: 8,
                  color: page == index
                      ? colors.onSurface
                      : colors.outlineVariant,
                ),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 32, 18, 16),
          child: LText(
            '가을맞이 인기 신상 모음',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          height: scaler.scale(14) * 1.4 + 28,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            children: [
              for (final value in ['운동화', '구두', '부츠'])
                InkWell(
                  onTap: () => setState(() => category = value),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: category == value
                              ? brandBlue
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: LText(
                      '$value 신상',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: category == value
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = ((constraints.maxWidth - 48) / 2)
                .clamp(140.0, 220.0)
                .toDouble();
            return SizedBox(
              height: ProductCard.gridHeight(context, width, false) + 4,
              child: ListView.builder(
                key: ValueKey('autumn-products-$category'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: selection.length,
                itemBuilder: (_, index) => Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: width,
                    child: ProductCard(
                      product: selection[index],
                      store: widget.store,
                      onOpen: () => widget.onOpen(selection[index]),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _releaseBanner(Product product, bool running) => Material(
    color: running ? const Color(0xFF202A33) : const Color(0xFF73482F),
    borderRadius: BorderRadius.circular(8),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => widget.onOpen(product),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LText(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  LText(
                    running ? '가볍게 시작하는 새로운 발걸음' : '가을에 어울리는 컬러와 스타일',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: ProductImage(product, height: double.infinity),
          ),
        ],
      ),
    ),
  );
}

String _campaignImage(StoreController store, int id) =>
    store.products.firstWhere((product) => product.id == id).imageUrl;

/// 원본의 성별·중분류·하위 분류·다섯 가지 정렬을 적용합니다.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.store,
    required this.onOpen,
    this.initialGender,
    this.initialMiddle = '스니커즈',
    this.initialSubcategory = '전체',
  });
  final StoreController store;
  final void Function(Product) onOpen;
  final String? initialGender;
  final String initialMiddle;
  final String initialSubcategory;
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late String subcategory;
  String sort = '판매 많은 순';
  @override
  void initState() {
    super.initState();
    subcategory = widget.initialSubcategory;
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.store.products
        .where(
          (item) =>
              item.middleCategory == widget.initialMiddle &&
              (subcategory == '전체' || item.subcategory == subcategory) &&
              (widget.initialGender == null ||
                  item.gender == widget.initialGender ||
                  (item.gender == '공용' && widget.initialGender != '키즈')),
        )
        .toList();
    products.sort(
      (a, b) => switch (sort) {
        '낮은 가격순' => a.price.compareTo(b.price),
        '높은 가격순' => b.price.compareTo(a.price),
        '신상품순' => b.id.compareTo(a.id),
        '리뷰 많은 순' => b.reviewCount.compareTo(a.reviewCount),
        _ => b.salesCount.compareTo(a.salesCount),
      },
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: LText(
              '${widget.initialGender ?? '전체'} · $subcategory',
              style: const TextStyle(
                color: Color(0xFF777777),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            children: [
              for (final value in [
                '전체',
                ...MockProductRepository.categoryTree[widget.initialMiddle]!,
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton(
                    onPressed: () => setState(() => subcategory = value),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: subcategory == value
                          ? const Color(0xFF455B77)
                          : Colors.white,
                      side: BorderSide(
                        color: subcategory == value
                            ? const Color(0xFF455B77)
                            : const Color(0xFFEAEAEA),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: LText(
                      value,
                      style: TextStyle(
                        color: subcategory == value
                            ? Colors.white
                            : Colors.black87,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
          child: Row(
            children: [
              LText(
                '${products.length}개 상품',
                style: const TextStyle(color: Color(0xFF777777), fontSize: 14),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFEAEAEA)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButton<String>(
                  value: sort,
                  underline: const SizedBox(),
                  items: ['판매 많은 순', '리뷰 많은 순', '신상품순', '낮은 가격순', '높은 가격순']
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: LText(
                            value,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => sort = value!),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: products.isEmpty
              ? const EmptyState('조건에 맞는 상품이 없어요.')
              : ProductGrid(
                  products: products,
                  store: widget.store,
                  onOpen: widget.onOpen,
                  showDetails: true,
                ),
        ),
      ],
    );
  }
}

class ProductGrid extends StatelessWidget {
  const ProductGrid({
    super.key,
    required this.products,
    required this.store,
    required this.onOpen,
    this.showDetails = false,
  });
  final List<Product> products;
  final StoreController store;
  final void Function(Product) onOpen;
  final bool showDetails;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth > 700 ? 4 : 2;
      // Let each row fit its contents instead of imposing a fixed card height.
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: (products.length / columns).ceil(),
        itemBuilder: (_, row) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < columns; column++) ...[
                if (column > 0) const SizedBox(width: 12),
                Expanded(
                  child: row * columns + column < products.length
                      ? ProductCard(
                          product: products[row * columns + column],
                          store: store,
                          showDetails: showDetails,
                          onOpen: () =>
                              onOpen(products[row * columns + column]),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// 기획전은 대표 상품과 네 개의 연결 상품을 보여줍니다.
class CampaignScreen extends StatelessWidget {
  const CampaignScreen({
    super.key,
    required this.title,
    required this.store,
    required this.onOpen,
  });
  final String title;
  final StoreController store;
  final void Function(Product) onOpen;
  @override
  Widget build(BuildContext context) {
    final data = campaignData[title]!;
    final products = store.products
        .where((p) => data.ids.contains(p.id))
        .toList();
    products.sort(
      (a, b) => data.ids.indexOf(a.id).compareTo(data.ids.indexOf(b.id)),
    );
    return Column(
      children: [
        SizedBox(
          height: 180,
          width: double.infinity,
          child: Image.network(
            products.first.imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const LText(
                '기획전 상품',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              LText('${products.length}개 상품'),
            ],
          ),
        ),
        Expanded(
          child: ProductGrid(
            products: products,
            store: store,
            onOpen: onOpen,
            showDetails: true,
          ),
        ),
      ],
    );
  }
}

/// 최근 본 상품과 찜 목록은 원본처럼 행 목록으로 표시합니다.
class ProductCollectionScreen extends StatelessWidget {
  const ProductCollectionScreen({
    super.key,
    required this.title,
    required this.products,
    required this.store,
    required this.onOpen,
    this.canRemove = false,
  });
  final String title;
  final List<Product> products;
  final StoreController store;
  final void Function(Product) onOpen;
  final bool canRemove;
  @override
  Widget build(BuildContext context) => products.isEmpty
      ? EmptyState(title == '최근 본 상품' ? '최근 본 상품이 없어요' : '저장한 상품이 없어요')
      : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final product in products)
              Card(
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => onOpen(product),
                      child: SizedBox(
                        width: 94,
                        child: ProductImage(product, height: 94),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LText(product.category),
                          LText(
                            product.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          LText(won(product.price)),
                        ],
                      ),
                    ),
                    if (canRemove)
                      TextButton(
                        onPressed: () => store.toggleWish(product),
                        child: const LText('삭제'),
                      ),
                  ],
                ),
              ),
          ],
        );
}

/// 검색어와 상품 종류를 동시에 적용합니다.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.store,
    required this.onOpen,
    this.onBack,
  });
  final StoreController store;
  final void Function(Product) onOpen;
  final VoidCallback? onBack;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _popularSearches = [
    '나이키',
    '아디다스',
    '뉴발란스',
    '푸마',
    '반스',
    '누오보',
    '에이비씨 셀렉트',
    '휠라',
    '닥터마틴',
    '스케쳐스',
  ];
  static const _recommendedSearches = [
    '아디다스 이클립테인',
    '나이키 퀘스트 7',
    '아디다스 갤럭시',
    '뉴발란스 530',
    '러닝화',
  ];
  static const _historyKey = 'shupick_recent_searches';
  final _searchController = TextEditingController();
  final _preferences = SharedPreferences.getInstance();
  late final Future<void> _historyReady;
  List<String> _recentSearches = [];
  String query = '';
  String category = '전체';
  String? selectedGender;

  @override
  void initState() {
    super.initState();
    _historyReady = _loadHistory();
  }

  Future<void> _loadHistory() async {
    final preferences = await _preferences;
    if (!mounted) return;
    setState(() {
      _recentSearches = preferences.getStringList(_historyKey) ?? [];
    });
  }

  Future<void> _rememberSearch(String value) async {
    final term = value.trim();
    if (term.isEmpty) return;
    await _historyReady;
    if (!mounted) return;
    setState(() {
      _recentSearches = [
        term,
        ..._recentSearches.where((item) => item != term),
      ].take(10).toList();
    });
    final preferences = await _preferences;
    await preferences.setStringList(_historyKey, _recentSearches);
  }

  Future<void> _deleteSearch(String term) async {
    setState(() => _recentSearches.remove(term));
    final preferences = await _preferences;
    await preferences.setStringList(_historyKey, _recentSearches);
  }

  Widget _popularSearchRow(int index) => InkWell(
    onTap: () => _search(_popularSearches[index]),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${index + 1}.',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              _popularSearches[index],
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            index == 0 ? Icons.remove : Icons.arrow_drop_up,
            size: 18,
            color: index == 0 ? Colors.grey : const Color(0xFFCE5364),
          ),
        ],
      ),
    ),
  );

  void _search(String value) {
    _searchController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    setState(() => query = value);
    _rememberSearch(value);
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.store.products
        .where(
          (item) =>
              (selectedGender == null || item.gender == selectedGender) &&
              (category == '전체' || item.category == category) &&
              (item.name.toLowerCase().contains(query.toLowerCase()) ||
                  item.category.contains(query) ||
                  item.subcategory.contains(query)),
        )
        .toList();
    final colorScheme = Theme.of(context).colorScheme;
    final showSuggestions = query.trim().isEmpty;
    final content = Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
            child: Row(
              children: [
                IconButton(
                  tooltip: '뒤로',
                  onPressed:
                      widget.onBack ?? () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(
                        alpha: .5,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        tooltip: '검색',
                        onPressed: () => _search(_searchController.text),
                      ),
                      hintText: '상품명 또는 카테고리 검색',
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (value) => setState(() => query = value),
                    onSubmitted: _search,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        if (_recentSearches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LText('최근 검색어', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 4),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _recentSearches.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, index) => InputChip(
                      label: Text(_recentSearches[index]),
                      onPressed: () => _search(_recentSearches[index]),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      deleteButtonTooltipMessage: '검색어 삭제',
                      onDeleted: () => _deleteSearch(_recentSearches[index]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (showSuggestions)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              children: [
                const LText(
                  '인기 검색어',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var column = 0; column < 2; column++) ...[
                      if (column > 0) const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          children: [
                            for (var row = 0; row < 5; row++)
                              _popularSearchRow(column * 5 + row),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 28),
                const LText(
                  '추천 검색어',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 10,
                  children: [
                    for (final term in _recommendedSearches)
                      ActionChip(
                        label: Text(term),
                        shape: const StadiumBorder(),
                        backgroundColor: colorScheme.surface,
                        side: BorderSide(color: colorScheme.outlineVariant),
                        onPressed: () => _search(term),
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (!showSuggestions) ...[
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final value in searchCategories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextButton(
                      onPressed: () => setState(() => category = value),
                      child: LText(
                        value,
                        style: TextStyle(
                          color: category == value ? brandBlue : Colors.black54,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: LText('${results.length}개의 상품'),
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? const EmptyState('검색 결과가 없습니다.')
                : ProductGrid(
                    products: results,
                    store: widget.store,
                    onOpen: (product) async {
                      await _rememberSearch(query);
                      if (mounted) widget.onOpen(product);
                    },
                  ),
          ),
        ],
      ],
    );
    return Stack(
      children: [
        content,
        if (!showSuggestions)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Center(
              child: Material(
                color: colorScheme.surface,
                elevation: 12,
                shadowColor: Colors.black45,
                shape: StadiumBorder(
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final gender in const ['공용', '남성', '여성'])
                        InkWell(
                          borderRadius: BorderRadius.circular(28),
                          onTap: () => setState(
                            () => selectedGender = selectedGender == gender
                                ? null
                                : gender,
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: selectedGender == gender
                                  ? colorScheme.primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: LText(
                              gender,
                              style: TextStyle(
                                color: selectedGender == gender
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
