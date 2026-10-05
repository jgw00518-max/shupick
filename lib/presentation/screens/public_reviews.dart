import 'dart:convert';
import 'package:flutter/material.dart';
import '../../domain/models.dart';
import '../localization.dart';
import '../shared/app_theme.dart';
import '../shared/rating_stars.dart';

/// 서버 공개 리뷰의 구매 옵션과 사진을 표시합니다. 개인 리뷰 관리는 주문 내역에서 유지합니다.
class PublicReviews extends StatelessWidget {
  const PublicReviews({
    super.key,
    required this.data,
    required this.loading,
    required this.error,
    required this.onReload,
    required this.onMore,
    this.ownedReviews = const {},
    this.onEdit,
    this.onDelete,
  });
  final Map<String, dynamic>? data;
  final bool loading;
  final String? error;
  final VoidCallback onReload;
  final VoidCallback onMore;
  final Map<int, ProductReview> ownedReviews;
  final void Function(ProductReview)? onEdit;
  final void Function(ProductReview)? onDelete;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LText(
        '리뷰 ${data?['count'] ?? 0}',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.card),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LText('평균 평점', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  ((data?['average'] ?? 0) as num).toStringAsFixed(1),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                RatingStars(
                  rating: ((data?['average'] ?? 0) as num).toDouble(),
                  size: 24,
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      LText(
        '구매확정한 상품은 주문 내역에서 리뷰를 작성할 수 있습니다.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 12),
      if (error != null) ...[
        const LText('리뷰를 불러오지 못했습니다.'),
        TextButton(onPressed: onReload, child: const LText('다시 시도')),
      ],
      if (data != null && (data!['items'] as List).isEmpty && !loading)
        const LText('등록된 리뷰가 없습니다.'),
      for (final row in (data?['items'] as List? ?? []))
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.card),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    RatingStars(rating: (row['rating'] as num).toDouble()),
                    LText(
                      ownedReviews.containsKey(row['id']) ? '내 리뷰' : '구매 고객',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
                if (ownedReviews.containsKey(row['id']))
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: onEdit == null
                            ? null
                            : () => onEdit!(ownedReviews[row['id']]!),
                        child: const LText('수정'),
                      ),
                      TextButton(
                        onPressed: onDelete == null
                            ? null
                            : () => onDelete!(ownedReviews[row['id']]!),
                        child: const LText('삭제'),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                LText(
                  '구매 옵션: ${row['color']} / ${row['size']}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                LText(
                  '사이즈 ${row['fitSize']} · 발볼 ${row['fitWidth']} · 착화감 ${row['fitComfort']}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  row['content'] as String,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                if ((row['photos'] as List).isNotEmpty)
                  SizedBox(
                    height: 84,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final photo in row['photos'] as List)
                          GestureDetector(
                            onTap: () => showDialog<void>(
                              context: context,
                              builder: (dialogContext) => Dialog(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext),
                                      icon: const Icon(Icons.close),
                                    ),
                                    Flexible(
                                      child: InteractiveViewer(
                                        child: Image.memory(
                                          base64Decode(photo),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Image.memory(
                                base64Decode(photo as String),
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
      if (loading) const CircularProgressIndicator(),
      if (!loading && data?['hasMore'] == true)
        TextButton(onPressed: onMore, child: const LText('리뷰 더 보기')),
    ],
  );
}
