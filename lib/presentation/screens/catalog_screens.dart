import 'package:flutter/material.dart';
import '../localization.dart';

import '../../app/store_controller.dart';
import '../../data/mock_repositories.dart';
import '../../domain/models.dart';
import '../shared/store_widgets.dart';

const campaignData = <String, ({String subtitle, List<int> ids})>{
  '이번 주 특가': (subtitle: '가볍게 시작하는 쇼핑', ids: [5, 6, 14, 19]),
  '매일 신는 좋은 신발': (subtitle: '일상에 자연스럽게 어울리는 선택', ids: [1, 9, 10, 16]),
  '계절의 신발': (subtitle: '지금 걷기 좋은 스타일', ids: [3, 12, 15, 21]),
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
                        onPressed: () => onCampaign('매일 신는 좋은 신발'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
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
          padding: const EdgeInsets.fromLTRB(18, 16, 10, 0),
          child: Row(
            children: [
              for (final product in _campaignProducts(
                store,
                entry.value.ids,
                limit: 2,
              ))
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ProductCard(
                      product: product,
                      store: store,
                      onOpen: () => onOpen(product),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ],
  );
}

String _campaignImage(StoreController store, int id) {
  for (final product in store.products) {
    if (product.id == id) return product.imageUrl;
  }
  return store.products.isEmpty ? mockHeroImage : store.products.first.imageUrl;
}

/// 목업 기획전 ID가 실제 DB에 없으면 현재 상품 중 일부를 안전하게 대체 표시합니다.
List<Product> _campaignProducts(
  StoreController store,
  List<int> ids, {
  required int limit,
}) {
  final byId = {for (final product in store.products) product.id: product};
  final matched = ids.map((id) => byId[id]).whereType<Product>().take(limit);
  if (matched.isNotEmpty) return matched.toList();
  return store.products.take(limit).toList();
}

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
                ...widget.store.categoryTree[widget.initialMiddle] ??
                    const <String>[],
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
    builder: (context, constraints) => GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: constraints.maxWidth > 700 ? 4 : 2,
        childAspectRatio: showDetails ? .50 : .64,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: products.length,
      itemBuilder: (_, index) => ProductCard(
        product: products[index],
        store: store,
        showDetails: showDetails,
        onOpen: () => onOpen(products[index]),
      ),
    ),
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
                        onPressed: store.shoppingReady
                            ? () => store.toggleWish(product)
                            : null,
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
  const SearchScreen({super.key, required this.store, required this.onOpen});
  final StoreController store;
  final void Function(Product) onOpen;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String query = '';
  String category = '전체';
  String? selectedGender;
  String? selectedBrand;

  @override
  Widget build(BuildContext context) {
    final results = widget.store.products
        .where(
          (item) =>
              (selectedGender == null || item.gender == selectedGender) &&
              (category == '전체' || item.middleCategory == category) &&
              (selectedBrand == null ||
                  (widget.store.brands[selectedBrand]?.contains(item.id) ??
                      false)) &&
              (item.name.toLowerCase().contains(query.toLowerCase()) ||
                  item.category.contains(query)),
        )
        .toList();
    final colorScheme = Theme.of(context).colorScheme;
    final content = Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SectionTitle('신발 찾기'),
        ),
        if (widget.store.brands.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<String>(
              initialValue: selectedBrand ?? '',
              decoration: const InputDecoration(labelText: '브랜드'),
              items: [
                const DropdownMenuItem(value: '', child: LText('전체 브랜드')),
                for (final brand in widget.store.brands.keys)
                  DropdownMenuItem(value: brand, child: LText(brand)),
              ],
              onChanged: (value) =>
                  setState(() => selectedBrand = value == '' ? null : value),
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: LText('스타일과 용도에 맞는 한 켤레를 골라보세요.'),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '상품명 또는 카테고리 검색',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => query = value),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final value in ['전체', ...widget.store.categoryTree.keys])
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
                  onOpen: widget.onOpen,
                ),
        ),
      ],
    );
    return Stack(
      children: [
        content,
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
