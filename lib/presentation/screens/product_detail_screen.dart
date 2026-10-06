import 'dart:convert';

import 'package:flutter/material.dart';
import '../localization.dart';

import '../../app/store_controller.dart';
import '../../domain/models.dart';
import '../shared/store_widgets.dart';
import '../shared/rating_stars.dart';
import '../shared/product_recommendation_section.dart';
import 'review_sheet.dart';
import '../../data/api_review_repository.dart';
import 'public_reviews.dart';

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
  Map<String, dynamic>? publicReviewData;
  bool reviewsLoading = false;
  String? reviewsError;
  Map<int, ProductReview> ownedPublicReviews = {};
  String? ownedReviewIdentity;

  /// 공개 목록과 집계는 동일 서버 응답을 사용하여 내 리뷰를 이중 계산하지 않습니다.
  Future<void> loadPublicReviews({bool more = false}) async {
    final repository = widget.store.reviewRepository;
    if (repository is! ApiReviewRepository || reviewsLoading) return;
    setState(() {
      reviewsLoading = true;
      reviewsError = null;
    });
    try {
      final previous = more
          ? (publicReviewData?['items'] as List? ?? [])
          : <dynamic>[];
      final result = await repository.getProductReviews(
        widget.product.id,
        offset: previous.length,
      );
      // 공개 응답은 익명으로 유지하고, 인증된 내 리뷰 ID와 로컬에서만 연결합니다.
      final identity = widget.store.accountIdentityKey;
      final owned = widget.store.isLoggedIn
          ? await repository.getReviews()
          : <ProductReview>[];
      if (!mounted) return;
      setState(() {
        ownedReviewIdentity = identity;
        ownedPublicReviews = {
          for (final review in owned)
            if (review.id != null) review.id!: review,
        };
        publicReviewData = {
          ...result,
          'items': [...previous, ...result['items'] as List],
        };
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          reviewsError = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          reviewsLoading = false;
        });
      }
    }
  }

  List<ProductOption> productOptions = [];
  bool productOptionsLoading = true;
  bool productOptionsFailed = false;
  int productOptionsRequest = 0;

  Future<void> loadProductOptions() async {
    final token = ++productOptionsRequest;
    setState(() {
      productOptionsLoading = true;
      productOptionsFailed = false;
    });
    try {
      final result = await widget.store.getProductOptions(widget.product.id);
      if (!mounted || token != productOptionsRequest) return;
      setState(() {
        productOptions = result;
        final colors = result.map((option) => option.color).toSet();
        if (colors.isNotEmpty && !colors.contains(color)) color = colors.first;
      });
    } catch (_) {
      if (mounted && token == productOptionsRequest) {
        setState(() => productOptionsFailed = true);
      }
    } finally {
      if (mounted && token == productOptionsRequest) {
        setState(() => productOptionsLoading = false);
      }
    }
  }

  @override
  void didUpdateWidget(ProductDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.id != widget.product.id) {
      color = widget.product.color;
      productOptions = [];
      loadProductOptions();
    }
  }

  Widget sizeAvailability() {
    if (productOptionsLoading) return const LinearProgressIndicator();
    if (productOptionsFailed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LText('상품 옵션을 불러오지 못했어요.'),
          TextButton.icon(
            onPressed: loadProductOptions,
            icon: const Icon(Icons.refresh),
            label: const LText('다시 시도'),
          ),
        ],
      );
    }
    final sizes =
        productOptions
            .where((option) => option.color == color)
            .map((option) => option.size)
            .toSet()
            .toList()
          ..sort(
            (a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0),
          );
    if (sizes.isEmpty) return const LText('현재 판매 가능한 옵션이 없습니다.');
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final size in sizes)
          Container(
            constraints: const BoxConstraints(minWidth: 64),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LText(size, style: Theme.of(context).textTheme.bodyMedium),
                if (!productOptions.any(
                  (option) =>
                      option.color == color &&
                      option.size == size &&
                      option.isAvailable,
                ))
                  LText(
                    '품절',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String get reviewSummary =>
      widget.store.reviewRepository is ApiReviewRepository
      ? reviewsError != null
            ? '리뷰 조회 실패'
            : publicReviewData == null
            ? '리뷰 불러오는 중'
            : '${(publicReviewData!['average'] as num).toStringAsFixed(1)} / 5 · 리뷰 ${publicReviewData!['count']}개'
      : '데모 리뷰 ${widget.product.reviewCount}개';
  @override
  void initState() {
    super.initState();
    color = widget.product.color;
    loadProductOptions();
    loadPublicReviews();
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
        data: MediaQuery.of(sheetContext),
        child: ProductOptionsSheet(
          product: widget.product,
          store: widget.store,
          initialColor: color,
          onCart: (lines) {
            if (!widget.store.shoppingReady) {
              widget.onMessage(
                widget.store.shoppingError ?? '계정과 장바구니 정보를 불러온 뒤 다시 시도해주세요.',
              );
              return;
            }
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
    final muted = isDark ? Colors.white70 : const Color(0xFF5F6975);
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
                      onPressed: widget.store.shoppingReady
                          ? () => widget.store.toggleWish(widget.product)
                          : null,
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
                            fontSize: 15,
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
                      style: TextStyle(fontSize: 16, color: muted),
                    ),
                    const SizedBox(height: 10),
                    LText(
                      widget.product.name,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LText(
                      won(widget.product.price),
                      style: const TextStyle(fontSize: 22),
                    ),
                    const SizedBox(height: 4),
                    LText(
                      reviewSummary,
                      style: TextStyle(fontSize: 16, color: muted),
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
                        for (final value
                            in (productOptions.isEmpty
                                ? widget.product.colors
                                : productOptions
                                      .map((option) => option.color)
                                      .toSet()))
                          _colorChoice(value, isDark),
                      ],
                    ),
                    const SizedBox(height: 22),
                    _optionHeading('사이즈', muted),
                    const SizedBox(height: 12),
                    sizeAvailability(),
                    const SizedBox(height: 12),
                    LText(
                      '장바구니 또는 구매하기를 누르면 옵션을 선택할 수 있어요.',
                      style: TextStyle(fontSize: 14, color: muted),
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
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          LText('수령 후 7일 반품', style: TextStyle(fontSize: 16)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ProductRecommendationSection(
                product: widget.product,
                store: widget.store,
                onOpenProduct: widget.onOpenProduct,
              ),
              const Divider(height: 1),
              Row(
                children: [
                  for (final value in ['상품 정보', '배송·반품 안내', '리뷰'])
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
                              fontSize: 16,
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
                  '배송·반품 안내' => _delivery(),
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
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      LText('구매 시 선택', style: TextStyle(fontSize: 14, color: muted)),
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
            LText(value, style: const TextStyle(fontSize: 15)),
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
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      const LText(
        '일상에 자연스럽게 어울리는 디자인과 편안한 착화감의 신발입니다. 상품 종류와 선택한 사이즈를 확인해주세요.',
        style: TextStyle(fontSize: 16, height: 1.6),
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
                    fontSize: 16,
                    color: Color(0xFF5F6975),
                  ),
                ),
              ),
              LText(detail.$2, style: const TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ],
      const Divider(height: 1),
      const SizedBox(height: 28),
      const LText(
        '상세 사진',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
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
                        fontSize: 14,
                        color: Color(0xFF5F6975),
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
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
      SizedBox(height: 14),
      LText(
        '결제 완료 후 본사에서 선택한 대리점으로 출고합니다. 대리점 도착 상태를 확인한 후 방문해주세요.',
        style: TextStyle(fontSize: 16, height: 1.6),
      ),
      SizedBox(height: 30),
      LText(
        '반품 안내',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
      SizedBox(height: 14),
      LText(
        '수령 후 7일 이내 미착용·상품 훼손 없음·구성품과 포장 유지 조건으로 반품을 신청할 수 있습니다. 상품 불량과 오배송은 별도로 검수합니다.',
        style: TextStyle(fontSize: 16, height: 1.6),
      ),
    ],
  );

  Widget _reviews(List<ProductReview> ownReviews) =>
      widget.store.reviewRepository is ApiReviewRepository
      ? PublicReviews(
          data: publicReviewData,
          loading: reviewsLoading,
          error: reviewsError,
          onReload: () => loadPublicReviews(),
          onMore: () => loadPublicReviews(more: true),
          ownedReviews:
              widget.store.isLoggedIn &&
                  ownedReviewIdentity == widget.store.accountIdentityKey
              ? ownedPublicReviews
              : const {},
          onEdit: _editReview,
          onDelete: _deleteReview,
        )
      : Column(
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
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      LText(
                        '실제 구매 후기 통계 · 예시 데이터',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                  const Divider(height: 30),
                  _fitMetric(
                    '사이즈',
                    '정사이즈 74%',
                    .74,
                    '작아요 18%',
                    '정사이즈 74%',
                    '커요 8%',
                  ),
                  const SizedBox(height: 18),
                  _fitMetric(
                    '발볼',
                    '적당함 78%',
                    .78,
                    '좁아요 12%',
                    '적당함 78%',
                    '넓어요 10%',
                  ),
                  const SizedBox(height: 18),
                  _fitMetric(
                    '착화감',
                    '편함 82%',
                    .82,
                    '보통 11%',
                    '편함 82%',
                    '불편함 7%',
                  ),
                  const SizedBox(height: 22),
                  const LText(
                    '사이즈 선택에 참고해주세요. 개인의 발 모양에 따라 착화감은 달라질 수 있어요.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
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
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const LText(
                  '리뷰는 주문 내역에서 작성할 수 있어요.',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Row(
              children: [
                LText(
                  '4.8',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                ),
                SizedBox(width: 5),
                RatingStars(rating: 4.8),
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
                      RatingStars(rating: review.rating.toDouble()),
                      const SizedBox(height: 8),
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
                                            child: Image.memory(
                                              base64Decode(photo),
                                            ),
                                          ),
                                          Positioned(
                                            right: 0,
                                            child: IconButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
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
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const RatingStars(rating: 5),
                    const SizedBox(height: 8),
                    LText(
                      entry.$2,
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 7),
                    LText(entry.$3, style: const TextStyle(fontSize: 16)),
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
          Expanded(child: LText(label, style: const TextStyle(fontSize: 15))),
          LText(
            result,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
          LText(low, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          const Spacer(),
          LText(middle, style: const TextStyle(fontSize: 14)),
          const Spacer(),
          LText(high, style: const TextStyle(fontSize: 14, color: Colors.grey)),
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
    if (mounted) await loadPublicReviews();
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
      try {
        await widget.store.deleteReview(review);
        widget.onMessage('리뷰가 삭제되었어요.');
        if (mounted) await loadPublicReviews();
      } catch (error) {
        widget.onMessage('리뷰 삭제 실패: $error');
      }
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
  List<ProductOption> options = [];
  bool optionsLoading = true;
  String? optionsError;
  String? error;

  String get color => selectedColor ?? widget.initialColor;
  String _restockKey(String size) => '${widget.product.id}:$color:$size';
  List<String> get availableColors => options.isEmpty
      ? widget.product.colors
      : options.map((option) => option.color).toSet().toList();
  List<ProductOption> get colorOptions =>
      options.where((option) => option.color == color).toList();

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  /// 옵션은 화면을 열 때마다 서버에서 조회해 오래된 재고 선택을 막습니다.
  Future<void> _loadOptions() async {
    if (mounted) {
      setState(() {
        optionsLoading = true;
        optionsError = null;
      });
    }
    try {
      final loaded = await widget.store.getProductOptions(widget.product.id);
      if (!mounted) return;
      setState(() {
        options = loaded;
        if (!availableColors.contains(color)) selectedColor = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => optionsError = '상품 옵션을 불러오지 못했어요.');
    } finally {
      if (mounted) setState(() => optionsLoading = false);
    }
  }

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
    if (!widget.store.shoppingReady) {
      setState(() {
        error = widget.store.shoppingError ?? '계정과 장바구니 정보를 불러온 뒤 다시 시도해주세요.';
      });
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
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      LText(
                        '옵션 선택',
                        style: TextStyle(
                          fontSize: 23,
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LText(
                        widget.product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      LText(
                        widget.product.category,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 6),
                      LText(
                        won(widget.product.price),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(
                  child: LText(
                    '색상',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                LText(
                  selectedColor == null ? '먼저 선택해주세요' : selectedColor!,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                for (final value in availableColors)
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
                        LText(value, style: const TextStyle(fontSize: 15)),
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
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                LText(
                  selectedColor == null ? '색상 선택 후 가능' : selectedColor!,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (optionsLoading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  )
                else if (optionsError != null)
                  TextButton(
                    onPressed: _loadOptions,
                    child: const LText('옵션 조회 실패 · 다시 시도'),
                  )
                else if (colorOptions.isEmpty)
                  const LText('선택한 색상의 판매 옵션이 없어요.')
                else
                  for (final option in colorOptions)
                    SizedBox(
                      width: (MediaQuery.sizeOf(context).width - 56) / 3,
                      child: OutlinedButton(
                        onPressed: selectedColor == null
                            ? null
                            : () async {
                                if (option.isAvailable) {
                                  addOption(option.size);
                                  return;
                                }
                                try {
                                  await widget.store.toggleRestock(
                                    _restockKey(option.size),
                                  );
                                } catch (_) {
                                  if (mounted) {
                                    widget.onMessage(
                                      '재입고 신청에 실패했습니다. 로그인과 연결 상태를 확인해주세요.',
                                    );
                                  }
                                  return;
                                }
                                widget.onMessage(
                                  widget.store.restockKeys.contains(
                                        _restockKey(option.size),
                                      )
                                      ? '재입고 알림 신청을 저장했어요.'
                                      : '재입고 알림 신청을 취소했어요.',
                                );
                                if (mounted) setState(() {});
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
                          option.isAvailable
                              ? '${option.size}\n재고 ${option.availableQuantity}'
                              : '${option.size}\n${widget.store.restockKeys.contains(_restockKey(option.size)) ? '알림 신청됨' : '재입고 알림'}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
              ],
            ),
            const SizedBox(height: 10),
            const LText(
              '선택한 색상에 따라 실제 사이즈별 재고가 표시됩니다.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(
                  child: LText(
                    '선택한 옵션',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                LText(
                  '${selected.length}개',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
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
                        style: TextStyle(fontSize: 14, color: Colors.grey),
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
