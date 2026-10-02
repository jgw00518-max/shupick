import 'dart:convert';

import 'package:flutter/material.dart';
import '../localization.dart';

import '../../app/store_controller.dart';
import '../../domain/models.dart';
import '../shared/store_widgets.dart';
import 'review_sheet.dart';

/// 상품 정보·배송 정책·리뷰와 구매 옵션을 원본 흐름대로 분리합니다.
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.product,
    required this.store,
    required this.onCart,
    required this.onBuy,
    required this.onOpenProduct,
    required this.onInquiry,
    required this.onMessage,
  });
  final Product product;
  final StoreController store;
  final VoidCallback onCart;
  final void Function(List<CartItem>) onBuy;
  final void Function(Product) onOpenProduct;
  final VoidCallback onInquiry;
  final void Function(String) onMessage;
  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late String color;
  String tab = '상품 정보';
  @override
  void initState() {
    super.initState();
    color = widget.product.color;
  }

  List<Product> get recommendations {
    const next = <int, List<int>>{
      1: [5, 6, 16, 2],
      2: [7, 9, 3, 1],
      3: [12, 13, 2, 11],
      4: [14, 15, 16, 5],
      5: [1, 6, 17, 16],
    };
    final ids = next[widget.product.id];
    if (ids != null) {
      return ids
          .map((id) => widget.store.products.firstWhere((p) => p.id == id))
          .toList();
    }
    return widget.store.products
        .where(
          (p) =>
              p.id != widget.product.id &&
              p.category == widget.product.category,
        )
        .take(4)
        .toList();
  }

  Future<void> openOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? null
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => MediaQuery(
        data: MediaQuery.of(
          sheetContext,
        ).copyWith(textScaler: const TextScaler.linear(1.3)),
        child: ProductOptionsSheet(
          product: widget.product,
          store: widget.store,
          initialColor: color,
          onCart: (lines) {
            widget.store.addCartItems(lines);
            widget.onMessage('장바구니에 상품을 담았어요.');
          },
          onBuy: widget.onBuy,
          onMessage: widget.onMessage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ownReviews = widget.store.reviews
        .where((r) => r.itemKey.startsWith('${widget.product.id}-'))
        .toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.white70 : const Color(0xFF777777);
    final surface = isDark
        ? Theme.of(context).colorScheme.surface
        : Colors.white;
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              Stack(
                children: [
                  ProductImage(
                    widget.product,
                    height: MediaQuery.sizeOf(context).width * .85,
                    color: color,
                  ),
                  Positioned(
                    right: 18,
                    top: 18,
                    child: IconButton(
                      tooltip: '찜',
                      onPressed: () => widget.store.toggleWish(widget.product),
                      icon: Icon(
                        widget.store.wishedIds.contains(widget.product.id)
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: Colors.white,
                        shadows: const [
                          Shadow(color: Colors.black38, blurRadius: 5),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    bottom: 16,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        child: LText(
                          color,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 26, 18, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LText(
                      widget.product.category,
                      style: TextStyle(fontSize: 14, color: muted),
                    ),
                    const SizedBox(height: 10),
                    LText(
                      widget.product.name,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LText(
                      won(widget.product.price),
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(height: 4),
                    LText(
                      '★★★★★  4.8 · 리뷰 ${widget.product.reviewCount + ownReviews.length}개',
                      style: TextStyle(fontSize: 14, color: muted),
                    ),
                    const SizedBox(height: 24),
                    const Divider(height: 1),
                    const SizedBox(height: 22),
                    _optionHeading('색상', muted),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (final value in widget.product.colors)
                          _colorChoice(value, isDark),
                      ],
                    ),
                    const SizedBox(height: 22),
                    _optionHeading('사이즈', muted),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (final size in ['240', '250', '260', '270', '280'])
                          Expanded(
                            child: Container(
                              height: 48,
                              margin: const EdgeInsets.only(right: 5),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: surface,
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white24
                                      : const Color(0xFFE8E8E8),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                size,
                                style: TextStyle(fontSize: 14, color: muted),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LText(
                      '장바구니 또는 구매하기를 누르면 옵션을 선택할 수 있어요.',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white10
                            : const Color(0xFFF0F4F6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Expanded(
                            child: LText(
                              '무료 배송',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          LText('30일 무료 교환', style: TextStyle(fontSize: 14)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: LText(
                            '이 상품을 본 고객이 다음으로 본 상품',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(Icons.arrow_forward, size: 16),
                      ],
                    ),
                    const SizedBox(height: 5),
                    LText(
                      '예시 탐색 데이터 기반 추천',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    const SizedBox(height: 13),
                    SizedBox(
                      height: 157,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: recommendations.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final product = recommendations[index];
                          return SizedBox(
                            width: 104,
                            child: InkWell(
                              onTap: () => widget.onOpenProduct(product),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: ProductImage(product, height: 104),
                                  ),
                                  const SizedBox(height: 7),
                                  LText(
                                    product.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  LText(
                                    won(product.price),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Row(
                children: [
                  for (final value in ['상품 정보', '배송·교환 안내', '리뷰'])
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => tab = value),
                        child: Container(
                          height: 58,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: tab == value
                                    ? const Color(0xFF455B77)
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: LText(
                            value,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: tab == value
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                              color: tab == value ? null : muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 70),
                child: switch (tab) {
                  '배송·교환 안내' => _delivery(),
                  '리뷰' => _reviews(ownReviews),
                  _ => _information(),
                },
              ),
            ],
          ),
        ),
        Container(
          color: surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: openOptions,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF455B77),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const LText('구매하기'),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _optionHeading(String title, Color muted) => Row(
    children: [
      Expanded(
        child: LText(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      LText('구매 시 선택', style: TextStyle(fontSize: 12, color: muted)),
    ],
  );

  Widget _colorChoice(String value, bool isDark) {
    final selected = color == value;
    final swatch = switch (value) {
      '실버' => const Color(0xFFC5C7CA),
      '블랙' => const Color(0xFF303136),
      '베이지' => const Color(0xFFB5A994),
      '화이트' => Colors.white,
      '코발트' => const Color(0xFF315BBD),
      '브라운' => const Color(0xFF705B4B),
      _ => const Color(0xFFB8B8B8),
    };
    return InkWell(
      onTap: () => setState(() => color = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? null : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? const Color(0xFF455B77)
                : (isDark ? Colors.white24 : const Color(0xFFE8E8E8)),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: swatch,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black12),
              ),
            ),
            const SizedBox(width: 6),
            LText(value, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _information() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const LText(
        '상품 설명',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      const LText(
        '일상에 자연스럽게 어울리는 디자인과 편안한 착화감의 신발입니다. 상품 종류와 선택한 사이즈를 확인해주세요.',
        style: TextStyle(fontSize: 14, height: 1.6),
      ),
      const SizedBox(height: 22),
      for (final detail in [
        ('소재', '리사이클 메시, 합성가죽'),
        ('굽 높이', '35mm'),
        ('제조국', '대한민국'),
      ]) ...[
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            children: [
              SizedBox(
                width: 78,
                child: LText(
                  detail.$1,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF777777),
                  ),
                ),
              ),
              LText(detail.$2, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ],
      const Divider(height: 1),
      const SizedBox(height: 28),
      const LText(
        '상세 사진',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 14),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < 3; index++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index == 2 ? 0 : 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: ProductImage(
                        widget.product,
                        height: 145,
                        color: widget
                            .product
                            .colors[index % widget.product.colors.length],
                      ),
                    ),
                    const SizedBox(height: 7),
                    LText(
                      ['전체 실루엣', '소재와 마감', '착용 예시'][index],
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF777777),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 28),
      SizedBox(
        width: double.infinity,
        height: 46,
        child: OutlinedButton(
          onPressed: widget.onInquiry,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFFE8E8E8)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const LText(
            '이 상품 문의하기',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ],
  );

  Widget _delivery() => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LText(
        '배송 안내',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      SizedBox(height: 14),
      LText(
        '평일 오후 2시 이전 주문은 당일 출고됩니다. 기본 배송비는 무료입니다.',
        style: TextStyle(fontSize: 14, height: 1.6),
      ),
      SizedBox(height: 30),
      LText(
        '교환 안내',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      SizedBox(height: 14),
      LText(
        '수령 후 30일 이내 미착용 상품은 사이즈 교환이 가능합니다. 사용 흔적 또는 포장 훼손 시 제한될 수 있습니다.',
        style: TextStyle(fontSize: 14, height: 1.6),
      ),
    ],
  );

  Widget _reviews(List<ProductReview> ownReviews) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE8E8E8)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Expanded(
                  child: LText(
                    '사이즈 추천',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                LText(
                  '실제 구매 후기 통계 · 예시 데이터',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
            const Divider(height: 30),
            _fitMetric('사이즈', '정사이즈 74%', .74, '작아요 18%', '정사이즈 74%', '커요 8%'),
            const SizedBox(height: 18),
            _fitMetric('발볼', '적당함 78%', .78, '좁아요 12%', '적당함 78%', '넓어요 10%'),
            const SizedBox(height: 18),
            _fitMetric('착화감', '편함 82%', .82, '보통 11%', '편함 82%', '불편함 7%'),
            const SizedBox(height: 22),
            const LText(
              '사이즈 선택에 참고해주세요. 개인의 발 모양에 따라 착화감은 달라질 수 있어요.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      const SizedBox(height: 26),
      Row(
        children: [
          Expanded(
            child: LText(
              '리뷰 ${widget.product.reviewCount + ownReviews.length}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const LText(
            '리뷰는 주문 내역에서 작성할 수 있어요.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      const SizedBox(height: 14),
      const Row(
        children: [
          LText(
            '4.8',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          SizedBox(width: 5),
          LText(
            '★★★★★',
            style: TextStyle(fontSize: 15, color: Color(0xFF455B77)),
          ),
        ],
      ),
      const SizedBox(height: 18),
      for (final review in ownReviews)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: LText('내 리뷰')),
                    TextButton(
                      onPressed: () => _editReview(review),
                      child: const LText('수정'),
                    ),
                    TextButton(
                      onPressed: () => _deleteReview(review),
                      child: const LText('삭제'),
                    ),
                  ],
                ),
                LText(
                  '사이즈 · ${review.fitSize}   발볼 · ${review.fitWidth}   착화감 · ${review.fitComfort}',
                ),
                LText(review.content),
                if (review.photos.isNotEmpty)
                  SizedBox(
                    height: 84,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final photo in review.photos)
                          GestureDetector(
                            onTap: () => showDialog<void>(
                              context: context,
                              builder: (context) => Dialog(
                                child: Stack(
                                  children: [
                                    InteractiveViewer(
                                      child: Image.memory(base64Decode(photo)),
                                    ),
                                    Positioned(
                                      right: 0,
                                      child: IconButton(
                                        onPressed: () => Navigator.pop(context),
                                        icon: const Icon(Icons.close),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Image.memory(
                                base64Decode(photo),
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      for (final entry in [
        (
          '착화감이 가볍고 좋아요',
          '김** · 260 구매 · 2026.09.21',
          '정사이즈로 잘 맞고 오래 걸어도 발이 편했습니다.',
        ),
        (
          '색상이 화면 그대로예요',
          '이** · 250 구매 · 2026.09.18',
          '사진과 실제 색상이 비슷해서 코디하기 좋습니다.',
        ),
      ]) ...[
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LText(
                entry.$1,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              LText(
                entry.$2,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 7),
              LText(entry.$3, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ],
    ],
  );

  Widget _fitMetric(
    String label,
    String result,
    double value,
    String low,
    String middle,
    String high,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: LText(label, style: const TextStyle(fontSize: 13))),
          LText(
            result,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      const SizedBox(height: 10),
      LinearProgressIndicator(
        value: value,
        minHeight: 7,
        backgroundColor: const Color(0xFFE8E8E8),
        color: const Color(0xFF455B77),
        borderRadius: BorderRadius.circular(4),
      ),
      const SizedBox(height: 7),
      Row(
        children: [
          LText(low, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const Spacer(),
          LText(middle, style: const TextStyle(fontSize: 11)),
          const Spacer(),
          LText(high, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    ],
  );

  Future<void> _editReview(ProductReview review) async {
    final order = widget.store.orders
        .where((o) => o.number == review.orderNumber)
        .firstOrNull;
    final item = order?.items
        .where((item) => item.key == review.itemKey)
        .firstOrNull;
    if (order == null || item == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReviewSheet(
        order: order,
        item: item,
        store: widget.store,
        existing: review,
        onSaved: () => widget.onMessage('리뷰가 수정되었어요.'),
      ),
    );
  }

  Future<void> _deleteReview(ProductReview review) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LText('리뷰 삭제'),
        content: const LText('작성한 리뷰를 삭제하시겠어요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const LText('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const LText('삭제'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await widget.store.deleteReview(review);
      widget.onMessage('리뷰가 삭제되었어요.');
    }
  }
}

/// 한 상품에서 여러 색상·사이즈 조합을 장바구니 또는 바로 구매로 보냅니다.
class ProductOptionsSheet extends StatefulWidget {
  const ProductOptionsSheet({
    super.key,
    required this.product,
    required this.store,
    required this.initialColor,
    required this.onCart,
    required this.onBuy,
    required this.onMessage,
  });
  final Product product;
  final StoreController store;
  final String initialColor;
  final void Function(List<CartItem>) onCart;
  final void Function(List<CartItem>) onBuy;
  final void Function(String) onMessage;
  @override
  State<ProductOptionsSheet> createState() => _ProductOptionsSheetState();
}

class _ProductOptionsSheetState extends State<ProductOptionsSheet> {
  String? selectedColor;
  final List<CartItem> selected = [];
  String? error;

  String get color => selectedColor ?? widget.initialColor;
  String _restockKey(String size) => '${widget.product.id}:$color:$size';
  List<String> get restockable => color == '블랙'
      ? ['260']
      : color == '베이지'
      ? ['240']
      : ['250'];
  List<String> get unavailable => color == '베이지' ? ['270'] : ['280'];

  void addOption(String size) {
    final key = '${widget.product.id}-$size-$color';
    final index = selected.indexWhere((item) => item.key == key);
    setState(() {
      if (index >= 0) {
        selected[index] = selected[index].copyWith(
          quantity: selected[index].quantity + 1,
        );
      } else {
        selected.add(
          CartItem(product: widget.product, size: size, color: color),
        );
      }
      selectedColor = null;
      error = null;
    });
  }

  void submit(bool buy) {
    if (selected.isEmpty) {
      setState(() => error = '색상과 사이즈를 선택해 옵션을 추가해주세요.');
      return;
    }
    Navigator.pop(context);
    if (buy) {
      widget.onBuy(List.of(selected));
    } else {
      widget.onCart(List.of(selected));
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .80,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LText(
                        '여러 옵션을 한 번에 선택할 수 있어요',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      LText(
                        '옵션 선택',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '닫기',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 76,
                    child: ProductImage(
                      widget.product,
                      height: 76,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LText(
                      widget.product.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    LText(
                      widget.product.category,
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 6),
                    LText(
                      won(widget.product.price),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(
                  child: LText(
                    '색상',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                LText(
                  selectedColor == null ? '먼저 선택해주세요' : selectedColor!,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                for (final value in widget.product.colors)
                  OutlinedButton(
                    onPressed: () => setState(() {
                      selectedColor = value;
                      error = null;
                    }),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      side: BorderSide(
                        color: selectedColor == value
                            ? const Color(0xFF455B77)
                            : const Color(0xFFE8E8E8),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 12,
                          color: switch (value) {
                            '실버' => const Color(0xFFC5C7CA),
                            '블랙' => const Color(0xFF303136),
                            '베이지' => const Color(0xFFB5A994),
                            '코발트' => const Color(0xFF315BBD),
                            '브라운' => const Color(0xFF705B4B),
                            _ => const Color(0xFFDDDDDD),
                          },
                        ),
                        const SizedBox(width: 5),
                        LText(value, style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(
                  child: LText(
                    '사이즈',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                LText(
                  selectedColor == null ? '색상 선택 후 가능' : selectedColor!,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final size in ['240', '250', '260', '270', '280'])
                  SizedBox(
                    width: (MediaQuery.sizeOf(context).width - 56) / 3,
                    child: OutlinedButton(
                      onPressed:
                          selectedColor == null || unavailable.contains(size)
                          ? null
                          : () async {
                              if (restockable.contains(size)) {
                                await widget.store.toggleRestock(
                                  _restockKey(size),
                                );
                                widget.onMessage(
                                  widget.store.restockKeys.contains(
                                        _restockKey(size),
                                      )
                                      ? '재입고 알림 신청을 저장했어요.'
                                      : '재입고 알림 신청을 취소했어요.',
                                );
                                if (mounted) setState(() {});
                              } else {
                                addOption(size);
                              }
                            },
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 62),
                        side: const BorderSide(color: Color(0xFFE8E8E8)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: LText(
                        restockable.contains(size)
                            ? '$size\n재입고 알림'
                            : unavailable.contains(size)
                            ? '$size\n품절'
                            : size,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const LText(
              '선택한 색상에 따라 사이즈별 재고와 재입고 가능 여부가 달라집니다.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(
                  child: LText(
                    '선택한 옵션',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                LText(
                  '${selected.length}개',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: selected.isEmpty
                  ? Container(
                      alignment: Alignment.topCenter,
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE8E8E8)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const LText(
                        '색상과 사이즈를 선택하면 여기에 추가됩니다.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final item in selected)
                          ListTile(
                            title: LText('${item.color} · ${item.size}'),
                            subtitle: LText(won(item.total)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: item.quantity <= 1
                                      ? null
                                      : () => setState(() {
                                          final index = selected.indexOf(item);
                                          selected[index] = item.copyWith(
                                            quantity: item.quantity - 1,
                                          );
                                        }),
                                  icon: const Icon(Icons.remove),
                                ),
                                LText('${item.quantity}'),
                                IconButton(
                                  onPressed: () => setState(() {
                                    final index = selected.indexOf(item);
                                    selected[index] = item.copyWith(
                                      quantity: item.quantity + 1,
                                    );
                                  }),
                                  icon: const Icon(Icons.add),
                                ),
                                IconButton(
                                  onPressed: () =>
                                      setState(() => selected.remove(item)),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            if (error != null)
              LText(error!, style: const TextStyle(color: Colors.red)),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => submit(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black87,
                      side: const BorderSide(color: Color(0xFF555555)),
                    ),
                    child: const LText('장바구니'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => submit(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF455B77),
                    ),
                    child: const LText('바로 구매'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
