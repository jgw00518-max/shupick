import 'package:flutter/material.dart';
import '../../domain/models.dart';
import '../localization.dart';
import 'store_widgets.dart';

/// A compact order summary with status-specific actions.
class OrderHistoryCard extends StatelessWidget {
  const OrderHistoryCard({
    super.key,
    required this.order,
    required this.onDetail,
    required this.onShipping,
    required this.onCode,
    required this.onConfirm,
    required this.onReturn,
    required this.onReview,
    required this.hasReview,
  });
  final StoreOrder order;
  final VoidCallback onDetail, onShipping, onCode, onConfirm, onReturn;
  final ValueChanged<CartItem> onReview;
  final bool Function(CartItem) hasReview;

  bool get inactive =>
      order.canceled || {'CANCELED', 'REFUNDED'}.contains(order.status);

  String get statusLabel => switch (order.status) {
    'PENDING_PAYMENT' => '결제 대기',
    'PAID' => '결제 완료',
    'PREPARING' => '상품 준비',
    'SHIPPING' => '배송 중',
    'READY_FOR_PICKUP' => '픽업 가능',
    'COMPLETED' => order.purchaseConfirmed ? '구매확정 완료' : '수령 완료',
    'CANCELED' => '취소 완료',
    'REFUNDED' => '환불 완료',
    _ => order.canceled ? '취소 완료' : order.status,
  };

  int get stage => switch (order.status) {
    'PAID' => 0,
    'PREPARING' => 1,
    'SHIPPING' => 2,
    'READY_FOR_PICKUP' => 3,
    'COMPLETED' => 4,
    _ => -1,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ready = order.status == 'READY_FOR_PICKUP';
    final done = order.status == 'COMPLETED';
    final dark = theme.brightness == Brightness.dark;
    final accent = inactive
        ? scheme.onSurfaceVariant
        : (ready || done)
        ? (dark ? const Color(0xFF9DDBC0) : const Color(0xFF287454))
        : scheme.primary;
    final date =
        '${order.date.year}.${order.date.month.toString().padLeft(2, '0')}.${order.date.day.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onDetail,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: LText(date, style: theme.textTheme.titleSmall),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: LText(
                          statusLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          order.number,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      LText(
                        '상세 보기',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: scheme.primary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < order.items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 20),
                  _item(context, order.items[i]),
                ],
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      LText('총 결제 금액', style: theme.textTheme.bodyMedium),
                      LText(
                        won(order.total),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 22,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.storefront_outlined,
                      color: scheme.onSurfaceVariant,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LText(
                        'SHOEPICK ${order.district}점 픽업',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                if (inactive) ...[
                  const SizedBox(height: 12),
                  LText(
                    '결제·환불 상세는 주문 상세에서 확인해주세요.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 20),
                  if (stage >= 0) _progress(context),
                  if (ready) ...[
                    const SizedBox(height: 16),
                    LText(
                      '매장 방문 시 픽업 코드를 보여주세요.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: accent,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 12,
                              ),
                            ),
                            onPressed: onShipping,
                            child: const LText(
                              '배송 조회',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ready
                              ? FilledButton(
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 12,
                                    ),
                                  ),
                                  onPressed: order.purchaseConfirmed
                                      ? null
                                      : onCode,
                                  child: const LText(
                                    '픽업 코드',
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              : OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 12,
                                    ),
                                  ),
                                  onPressed: order.purchaseConfirmed
                                      ? null
                                      : onCode,
                                  child: const LText(
                                    '픽업 코드',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  if (done && !order.purchaseConfirmed) ...[
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: onConfirm,
                      child: const LText('구매확정'),
                    ),
                    const SizedBox(height: 8),
                    LText(
                      '구매확정 후 리뷰를 작성하면 1,000P가 적립됩니다.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: onReturn,
                        child: const LText('반품 신청'),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, CartItem item) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 72,
                child: ProductImage(
                  item.product,
                  height: 80,
                  color: item.color,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.product.name,
                    style: theme.textTheme.titleSmall?.copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: 6),
                  LText(
                    '${item.color} · ${item.size}mm · ${item.quantity}개',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LText(won(item.total), style: theme.textTheme.titleSmall),
                ],
              ),
            ),
          ],
        ),
        if (!inactive &&
            order.status == 'COMPLETED' &&
            order.purchaseConfirmed) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: hasReview(item) ? null : () => onReview(item),
            child: LText(hasReview(item) ? '리뷰 작성 완료' : '리뷰 작성 (1,000P)'),
          ),
        ],
      ],
    );
  }

  Widget _progress(BuildContext context) {
    const labels = ['결제', '준비', '배송', '픽업', '완료'];
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Divider(
                        height: 24,
                        color: i == 0
                            ? Colors.transparent
                            : i <= stage
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                      ),
                    ),
                    Icon(
                      i <= stage
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 18,
                      color: i <= stage
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                    ),
                    Expanded(
                      child: Divider(
                        height: 24,
                        color: i == labels.length - 1
                            ? Colors.transparent
                            : i < stage
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                LText(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 14,
                    color: i <= stage
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: i == stage ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
