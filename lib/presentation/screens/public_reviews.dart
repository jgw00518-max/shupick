import 'dart:convert';
import 'package:flutter/material.dart';
import '../../domain/models.dart';

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
      Text(
        '리뷰 ${data?['count'] ?? 0} · 평균 평점 ${((data?['average'] ?? 0) as num).toStringAsFixed(1)}',
      ),
      const Text('구매확정한 상품은 주문 내역에서 리뷰를 작성할 수 있습니다.'),
      if (error != null) ...[
        const Text('리뷰를 불러오지 못했습니다.'),
        TextButton(onPressed: onReload, child: const Text('다시 시도')),
      ],
      if (data != null && (data!['items'] as List).isEmpty && !loading)
        const Text('등록된 리뷰가 없습니다.'),
      for (final row in (data?['items'] as List? ?? []))
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${ownedReviews.containsKey(row['id']) ? '내 리뷰' : '구매 고객'} · ${row['rating']} / 5',
                ),
                if (ownedReviews.containsKey(row['id']))
                  Row(
                    children: [
                      TextButton(
                        onPressed: onEdit == null
                            ? null
                            : () => onEdit!(ownedReviews[row['id']]!),
                        child: const Text('수정'),
                      ),
                      TextButton(
                        onPressed: onDelete == null
                            ? null
                            : () => onDelete!(ownedReviews[row['id']]!),
                        child: const Text('삭제'),
                      ),
                    ],
                  ),
                Text('구매 옵션: ${row['color']} / ${row['size']}'),
                Text(
                  '사이즈 ${row['fitSize']} · 발볼 ${row['fitWidth']} · 착화감 ${row['fitComfort']}',
                ),
                Text(row['content'] as String),
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
        TextButton(onPressed: onMore, child: const Text('리뷰 더 보기')),
    ],
  );
}
