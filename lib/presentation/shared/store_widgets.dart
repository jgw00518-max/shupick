import 'package:flutter/material.dart';
import '../localization.dart';

import '../../app/store_controller.dart';
import '../../domain/models.dart';

const brandBlue = Color(0xFF244D82);
const canvas = Color(0xFFF7F6F3);

String won(int amount) {
  final value = amount.toString();
  return '${value.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}원';
}

/// 원격 이미지가 실패해도 상품 카드의 크기와 정보를 유지합니다.
class ProductImage extends StatelessWidget {
  const ProductImage(this.product, {super.key, this.height = 180, this.color});
  final Product product;
  final double height;
  final String? color;
  @override
  Widget build(BuildContext context) => Container(
    height: height,
    width: double.infinity,
    color: const Color(0xFFEFEEEB),
    child: Image.network(
      product.imageFor(color ?? product.color),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const Center(
        child: Icon(Icons.shopping_bag_outlined, size: 44, color: Colors.grey),
      ),
    ),
  );
}

/// 목록과 캠페인에서 공유하는 상품 카드입니다.
class ProductCard extends StatefulWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.store,
    required this.onOpen,
    this.showDetails = false,
  });
  final Product product;
  final StoreController store;
  final VoidCallback onOpen;
  final bool showDetails;

  /// Reserve the square image plus every text row, including expanded sizes.
  static double gridHeight(BuildContext context, double width, bool details) {
    final scaler = MediaQuery.textScalerOf(context);
    final textHeight = scaler.scale(13) * 1.4 + scaler.scale(16) * 1.4 * 2;
    final detailsHeight = details
        ? (scaler.scale(13) + scaler.scale(14) + scaler.scale(12)) * 1.4 + 15
        : 0.0;
    return (width + 19 + textHeight + detailsHeight).ceilToDouble();
  }

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  bool sizesOpen = false;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: widget.onOpen,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ProductImage(widget.product, height: double.infinity),
              ),
            ),
            Positioned(
              right: 6,
              top: 6,
              child: IconButton(
                tooltip: '찜',
                onPressed: () => widget.store.toggleWish(widget.product),
                icon: Icon(
                  widget.store.wishedIds.contains(widget.product.id)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: widget.store.wishedIds.contains(widget.product.id)
                      ? brandBlue
                      : Colors.white,
                  shadows: const [Shadow(color: Colors.black26, blurRadius: 4)],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LText(
          '${widget.product.gender}  ${widget.product.category}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF777777),
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 3),
        LText(
          widget.product.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        LText(
          won(widget.product.price),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            height: 1.4,
          ),
        ),
        if (widget.showDetails) ...[
          const SizedBox(height: 5),
          LText(
            '${widget.product.colors.take(3).join(' · ')} 외',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          InkWell(
            onTap: () => setState(() => sizesOpen = !sizesOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: LText(
                sizesOpen ? 'SIZE ▲' : 'SIZE ▼',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
            ),
          ),
          if (sizesOpen)
            const LText(
              '230  240  250  260  270  280',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
        ],
      ],
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: LText(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
      ),
      if (action != null)
        TextButton(
          onPressed: onAction,
          child: LText(
            action!,
            style: const TextStyle(color: Color(0xFF555555), fontSize: 14),
          ),
        ),
    ],
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key, this.action, this.onAction});
  final String message;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shopping_bag_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          LText(message, textAlign: TextAlign.center),
          if (action != null)
            TextButton(onPressed: onAction, child: LText(action!)),
        ],
      ),
    ),
  );
}
