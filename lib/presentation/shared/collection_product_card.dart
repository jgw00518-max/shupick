import 'package:flutter/material.dart';
import '../../domain/models.dart';
import '../localization.dart';
import 'store_widgets.dart';

/// A readable collection card with independent product and removal actions.
class CollectionProductCard extends StatelessWidget {
  const CollectionProductCard({
    super.key,
    required this.product,
    required this.onOpen,
    this.onRemove,
  });
  final Product product;
  final VoidCallback onOpen;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final imageWidth = (constraints.maxWidth * .34).clamp(
                    84.0,
                    112.0,
                  );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: imageWidth,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: ProductImage(product, height: imageWidth),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LText(
                              product.category,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6),
                            LText(
                              product.name,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 8),
                            LText(
                              '${product.gender} · ${product.color}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Divider(height: 1, color: scheme.outlineVariant),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: LText(
                      won(product.price),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (onRemove != null)
                    IconButton(
                      onPressed: onRemove,
                      tooltip: translateMockupText(
                        '찜 해제',
                        LocaleScope.languageOf(context),
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: scheme.primary.withValues(alpha: .08),
                        foregroundColor: scheme.primary,
                        minimumSize: const Size(48, 48),
                      ),
                      icon: const Icon(Icons.favorite, size: 23),
                    )
                  else
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 22,
                      color: scheme.primary,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
