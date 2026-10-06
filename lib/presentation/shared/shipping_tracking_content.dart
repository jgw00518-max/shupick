import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../localization.dart';
import 'branch_hours.dart';

String trackingStatusLabel(String status) => switch (status) {
  'PENDING_PAYMENT' => '결제 대기',
  'PAID' => '결제 완료',
  'PREPARING' => '상품 준비',
  'SHIPPING' => '대리점 이동 중',
  'READY_FOR_PICKUP' => '픽업 가능',
  'COMPLETED' => '수령 완료',
  'CANCELED' => '취소 완료',
  'REFUNDED' => '환불 완료',
  _ => status,
};

/// Renders the server tracking snapshot without performing network requests.
class ShippingTrackingContent extends StatelessWidget {
  const ShippingTrackingContent({
    super.key,
    required this.data,
    this.purchaseConfirmed = false,
  });
  final Map<String, dynamic> data;
  final bool purchaseConfirmed;

  String value(String key) => data[key]?.toString() ?? '';
  String date(Object? value) {
    if (value == null) return '';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${parsed.year}.${two(parsed.month)}.${two(parsed.day)}  ${two(parsed.hour)}:${two(parsed.minute)}';
  }

  String time(Object? value) => branchTime(value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = value('order_status');
    const stages = [
      'PAID',
      'PREPARING',
      'SHIPPING',
      'READY_FOR_PICKUP',
      'COMPLETED',
    ];
    final stage = stages.indexOf(status);
    final ready = status == 'READY_FOR_PICKUP';
    final inactive = {'CANCELED', 'REFUNDED'}.contains(status);
    final accent = inactive ? scheme.onSurfaceVariant : scheme.primary;
    final message = switch (status) {
      'PENDING_PAYMENT' => '결제가 완료되면 상품 준비가 시작됩니다.',
      'PAID' => '결제가 완료되었습니다. 상품 준비를 기다려주세요.',
      'PREPARING' => '주문하신 상품을 준비하고 있습니다.',
      'SHIPPING' => '수령 대리점으로 배송 중입니다.',
      'READY_FOR_PICKUP' => '상품이 도착했습니다. 픽업 기한 내에 방문해주세요.',
      'COMPLETED' => '상품 수령이 완료되었습니다.',
      'CANCELED' => '취소된 주문입니다.',
      'REFUNDED' => '환불된 주문입니다.',
      _ => '주문의 진행 상태를 확인해주세요.',
    };
    final hours = data['businessHours'] as List? ?? [];
    final history = (data['history'] as List? ?? []).reversed.toList();

    Widget panel(List<Widget> children) => Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
    Widget heading(String text, IconData icon) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, size: 22, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(child: LText(text, style: theme.textTheme.titleMedium)),
        ],
      ),
    );
    Widget info(String label, String text, {bool emphasis = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LText(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          LText(
            text,
            style: emphasis
                ? theme.textTheme.titleSmall?.copyWith(color: scheme.primary)
                : theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: .2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                ready
                    ? Icons.storefront_outlined
                    : status == 'COMPLETED'
                    ? Icons.check_circle_outline
                    : inactive
                    ? Icons.info_outline
                    : Icons.local_shipping_outlined,
                size: 34,
                color: accent,
              ),
              const SizedBox(height: 12),
              LText(
                trackingStatusLabel(status),
                style: theme.textTheme.headlineSmall?.copyWith(color: accent),
              ),
              const SizedBox(height: 8),
              LText(message, style: theme.textTheme.bodyMedium),
              if (ready && data['pickup_deadline_at'] != null) ...[
                const SizedBox(height: 16),
                info('픽업 기한', date(data['pickup_deadline_at']), emphasis: true),
              ],
            ],
          ),
        ),
        if (!inactive)
          panel([
            heading('배송 진행 상황', Icons.route_outlined),
            for (var i = 0; i < stages.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == stages.length - 1 ? 0 : 16,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i <= stage
                            ? scheme.primary
                            : scheme.surfaceContainerHighest,
                      ),
                      child: Icon(
                        i < stage
                            ? Icons.check
                            : i == stage
                            ? Icons.more_horiz
                            : Icons.circle_outlined,
                        size: 18,
                        color: i <= stage
                            ? scheme.onPrimary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: LText(
                        trackingStatusLabel(stages[i]),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: i <= stage
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                          fontWeight: i == stage
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (i == stage)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: LText(
                          '현재',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ]),
        if (ready && !purchaseConfirmed && value('order_number').isNotEmpty)
          panel([
            heading('픽업 코드', Icons.qr_code_2),
            LText(
              '수령 시 아래 코드를 직원에게 보여주세요.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                value('order_number'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                  letterSpacing: .5,
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: value('order_number')),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: LText('픽업 코드를 복사했습니다.')),
                  );
                }
              },
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const LText('코드 복사'),
            ),
          ]),
        panel([
          heading('수령 대리점', Icons.storefront_outlined),
          LText(
            value('branch_name').isEmpty ? '대리점 정보 확인 중' : value('branch_name'),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          if (value('address').isNotEmpty) info('주소', value('address')),
          if (value('phone').isNotEmpty) info('전화번호', value('phone')),
          if (hours.isNotEmpty) ...[
            const Divider(height: 24),
            LText('영업시간', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            for (final hour in hours)
              if (hour['day_of_week'] is int &&
                  hour['day_of_week'] >= 1 &&
                  hour['day_of_week'] <= 7)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      SizedBox(
                        width: 54,
                        child: LText(
                          '${const ['월', '화', '수', '목', '금', '토', '일'][hour['day_of_week'] - 1]}요일',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      LText(
                        hour['is_closed'] == 1 || hour['is_closed'] == true
                            ? '휴무'
                            : '${time(hour['opens_at'])} - ${time(hour['closes_at'])}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
          ],
        ]),
        panel([
          heading('배송 정보', Icons.receipt_long_outlined),
          if (value('order_number').isNotEmpty)
            info('주문 번호', value('order_number')),
          if (value('tracking_number').isNotEmpty)
            info('운송장 번호', value('tracking_number')),
          if (data['shipped_at'] != null)
            info('배송 시작', date(data['shipped_at'])),
          if (data['arrived_at'] != null)
            info('대리점 도착', date(data['arrived_at'])),
          if (data['pickup_deadline_at'] != null &&
              !ready &&
              !inactive &&
              status != 'COMPLETED')
            info('픽업 기한', date(data['pickup_deadline_at']), emphasis: true),
          if (data['picked_up_at'] != null)
            info('수령 완료', date(data['picked_up_at'])),
        ]),
        if (history.isNotEmpty)
          panel([
            heading('상태 변경 이력', Icons.history),
            for (var i = 0; i < history.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == history.length - 1 ? 0 : 20,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Icon(
                        Icons.circle,
                        size: 10,
                        color: i == 0 ? scheme.primary : scheme.outlineVariant,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LText(
                            trackingStatusLabel(
                              history[i]['new_status']?.toString() ?? '',
                            ),
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          LText(
                            date(history[i]['changed_at']),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ]),
      ],
    );
  }
}
