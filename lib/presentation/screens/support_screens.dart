import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../localization.dart';
import '../shared/shipping_tracking_content.dart';

import '../../app/store_controller.dart';
import '../../data/api_order_repository.dart';
import '../../domain/models.dart';
import '../shared/store_widgets.dart';

/// 선택된 주문을 기준으로 픽업·배송 상태를 표시합니다.
class ShippingScreen extends StatefulWidget {
  const ShippingScreen({
    super.key,
    required this.store,
    required this.order,
    required this.onOrders,
  });
  final StoreController store;
  final StoreOrder? order;
  final VoidCallback onOrders;
  @override
  State<ShippingScreen> createState() => _ShippingScreenState();
}

class _ShippingScreenState extends State<ShippingScreen> {
  Map<String, dynamic>? tracking;
  String? error;
  bool loading = true;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _statusSubscription;
  String? realtimeError;

  @override
  void initState() {
    super.initState();
    _load();
    final id = widget.order?.id;
    if (id != null && widget.store.orderRepository is ApiOrderRepository) {
      _statusSubscription = FirebaseFirestore.instance
          .collection('orderStatuses')
          .doc('$id')
          .snapshots()
          .listen(
            (snapshot) {
              if (snapshot.exists && mounted) {
                setState(() => realtimeError = null);
                _load();
                widget.store.refreshOrders();
              }
            },
            onError: (Object _) {
              if (mounted) setState(() => realtimeError = '실시간 연결 오류');
            },
          );
    }
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  /// 새로고침 시 MySQL의 상태와 실제 대리점 정보를 다시 읽습니다.
  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final repository = widget.store.orderRepository;
      final id = widget.order?.id;
      if (repository is! ApiOrderRepository || id == null) {
        throw StateError('조회할 서버 주문이 없습니다.');
      }
      final result = await repository.getTracking(id);
      if (mounted) setState(() => tracking = result);
    } catch (_) {
      if (mounted) setState(() => error = '배송 정보를 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.order == null) return const EmptyState('조회할 주문이 없습니다.');
    final data = tracking;
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              LText('픽업 배송 조회', style: theme.textTheme.headlineSmall),
              TextButton.icon(
                onPressed: loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 20),
                label: const LText('새로고침'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (loading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 20),
          ],
          if (error != null || realtimeError != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: LText(
                error ?? '실시간 연결을 확인해주세요. 새로고침으로 조회할 수 있습니다.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (data != null)
            ShippingTrackingContent(
              data: data,
              purchaseConfirmed: widget.order!.purchaseConfirmed,
            ),
          OutlinedButton.icon(
            onPressed: widget.onOrders,
            icon: const Icon(Icons.receipt_long_outlined, size: 20),
            label: const LText('주문 내역으로 돌아가기'),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// 서버에서 발급한 쿠폰 원장을 표시합니다.
class CouponsScreen extends StatelessWidget {
  const CouponsScreen({super.key, required this.store});
  final StoreController store;
  @override
  Widget build(BuildContext context) =>
      _BenefitsView(store: store, coupons: true);
}

/// 잔액·적립 건별 만료일·최근 포인트 원장을 표시합니다.
class PointsScreen extends StatelessWidget {
  const PointsScreen({super.key, required this.store});
  final StoreController store;
  @override
  Widget build(BuildContext context) =>
      _BenefitsView(store: store, coupons: false);
}

class _BenefitsView extends StatefulWidget {
  const _BenefitsView({required this.store, required this.coupons});
  final StoreController store;
  final bool coupons;
  @override
  State<_BenefitsView> createState() => _BenefitsViewState();
}

class _BenefitsViewState extends State<_BenefitsView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  Future<void> _reload() async {
    await widget.store.refreshBenefits();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final data = store.accountBenefits;
    final coupons = (data?['coupons'] as List?) ?? [];
    final wallet = data?['wallet'] as Map<String, dynamic>?;
    final lots = (wallet?['lots'] as List?) ?? [];
    final history = (data?['pointHistory'] as List?) ?? [];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SectionTitle(widget.coupons ? '쿠폰' : '적립금'),
        TextButton(
          onPressed: store.benefitsLoading ? null : _reload,
          child: const LText('새로고침'),
        ),
        if (store.benefitsLoading) const LinearProgressIndicator(),
        if (store.benefitsError != null) LText(store.benefitsError!),
        if (data == null &&
            !store.benefitsLoading &&
            store.benefitsError == null)
          const LText('로그인 후 회원 혜택을 확인해주세요.'),
        if (widget.coupons && data != null) ...[
          LText('사용 가능한 쿠폰 ${coupons.length}장'),
          if (coupons.isEmpty) const LText('사용 가능한 쿠폰이 없습니다.'),
          for (final coupon in coupons)
            Card(
              child: ListTile(
                title: LText('${coupon['name']}'),
                subtitle: LText(
                  '최소 주문 ${won(coupon['minimumOrderAmount'] as int)}\n사용 기한 ${coupon['expiresAt']} 이전',
                ),
                trailing: LText(
                  coupon['discountType'] == 'PERCENT'
                      ? '${coupon['discountValue']}%'
                      : won(coupon['discountValue'] as int),
                ),
              ),
            ),
        ],
        if (!widget.coupons && data != null) ...[
          LText(
            '사용 가능 적립금 ${wallet?['balance'] ?? 0}P',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const LText('포인트는 각 적립일을 기준으로 1년 후 만료됩니다.'),
          const SectionTitle('만료 예정 포인트'),
          if (lots.isEmpty) const LText('사용 가능한 적립 포인트가 없습니다.'),
          for (final lot in lots)
            ListTile(
              title: LText('${lot['remainingAmount']}P'),
              subtitle: LText('만료 ${lot['expiresAt']}'),
            ),
          const SectionTitle('최근 포인트 내역'),
          if (history.isEmpty) const LText('포인트 내역이 없습니다.'),
          for (final entry in history)
            ListTile(
              title: LText(
                '${entry['description'] ?? entry['transaction_type']}',
              ),
              subtitle: LText('${entry['created_at']}'),
              trailing: LText('${entry['point_amount']}P'),
            ),
        ],
      ],
    );
  }
}
