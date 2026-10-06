import 'package:flutter/material.dart';

import '../../app/store_controller.dart';
import '../../domain/models.dart';
import '../localization.dart';
import 'store_widgets.dart';

class ProductRecommendationSection extends StatefulWidget {
  const ProductRecommendationSection({
    super.key,
    required this.product,
    required this.store,
    required this.onOpenProduct,
  });

  final Product product;
  final StoreController store;
  final ValueChanged<Product> onOpenProduct;

  @override
  State<ProductRecommendationSection> createState() =>
      _ProductRecommendationSectionState();
}

class _ProductRecommendationSectionState
    extends State<ProductRecommendationSection> {
  late ProductRecommendations recommendations;
  int request = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    recommendations = widget.store.similarRecommendations(widget.product);
    _load();
  }

  @override
  void didUpdateWidget(ProductRecommendationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.id != widget.product.id ||
        oldWidget.store != widget.store) {
      recommendations = widget.store.similarRecommendations(widget.product);
      loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final token = ++request;
    final result = await widget.store.getRecommendations(widget.product);
    if (!mounted || token != request) return;
    setState(() {
      recommendations = result;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LText(
            recommendations.hasCustomerViews
                ? '이 상품을 본 고객이 많이 찾아본 상품'
                : '함께 둘러보기 좋은 상품',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          LText(
            recommendations.hasCustomerViews
                ? '함께 조회된 상품을 먼저 보여드려요.'
                : '종류와 가격이 비슷한 상품을 골랐어요.',
            style: TextStyle(fontSize: 14, color: muted),
          ),
          if (loading) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 2),
          ],
          const SizedBox(height: 14),
          if (recommendations.products.isEmpty)
            LText('다른 추천 상품을 준비하고 있어요.', style: TextStyle(color: muted))
          else
            SizedBox(
              height: 172 + MediaQuery.textScalerOf(context).scale(60),
              child: ListView.separated(
                key: ValueKey('recommendations-${widget.product.id}'),
                scrollDirection: Axis.horizontal,
                itemCount: recommendations.products.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, index) {
                  final product = recommendations.products[index];
                  return SizedBox(
                    width: 148,
                    child: Semantics(
                      button: true,
                      label: '${product.name} 상세 보기',
                      child: InkWell(
                        key: ValueKey('recommended-product-${product.id}'),
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => widget.onOpenProduct(product),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: ProductImage(product, height: 148),
                            ),
                            const SizedBox(height: 8),
                            LText(
                              product.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            LText(
                              won(product.price),
                              style: TextStyle(fontSize: 14, color: muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
