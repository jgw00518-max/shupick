import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../localization.dart';
import 'package:flutter/services.dart';

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

  String _status(String value) => switch (value) {
    'PENDING_PAYMENT' => '결제 대기',
    'PAID' => '결제 완료',
    'PREPARING' => '상품 준비',
    'SHIPPING' => '대리점 이동 중',
    'READY_FOR_PICKUP' => '픽업 가능',
    'COMPLETED' => '수령 완료',
    'CANCELED' => '취소 완료',
    'REFUNDED' => '환불 완료',
    _ => value,
  };

  @override
  Widget build(BuildContext context) {
    if (widget.order == null) return const EmptyState('조회할 주문이 없습니다.');
    final data = tracking;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SectionTitle('픽업 배송 조회'),
        TextButton(
          onPressed: loading ? null : _load,
          child: const LText('새로고침'),
        ),
        if (loading) const LinearProgressIndicator(),
        if (error != null) LText(error!),
        if (realtimeError != null)
          const LText('실시간 연결을 확인해주세요. 새로고침으로 조회할 수 있습니다.'),
        if (data != null) ...[
          LText(
            _status(data['order_status'] as String),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          LText('주문 번호 ${data['order_number']}'),
          Card(
            child: ListTile(
              title: LText('${data['branch_name']}'),
              subtitle: LText('${data['address']}\n${data['phone']}'),
            ),
          ),
          for (final hour in data['businessHours'] as List)
            LText(
              '${const ['월', '화', '수', '목', '금', '토', '일'][(hour['day_of_week'] as int) - 1]}요일 · ${hour['is_closed'] == 1 || hour['is_closed'] == true ? '휴무' : '${hour['opens_at']} ~ ${hour['closes_at']}'}',
            ),
          if (data['tracking_number'] != null)
            LText('운송장 번호 ${data['tracking_number']}'),
          if (data['arrived_at'] != null) LText('대리점 도착 ${data['arrived_at']}'),
          if (data['pickup_deadline_at'] != null)
            LText('픽업 기한 ${data['pickup_deadline_at']}'),
          if (data['order_status'] == 'READY_FOR_PICKUP') ...[
            const LText('수령 시 아래 결제 코드를 직원에게 보여주세요.'),
            SelectableText(data['order_number'] as String),
            TextButton(
              onPressed: () => Clipboard.setData(
                ClipboardData(text: data['order_number'] as String),
              ),
              child: const LText('코드 복사'),
            ),
          ],
          if (data['picked_up_at'] != null)
            LText('수령 완료 ${data['picked_up_at']}'),
          const SectionTitle('상태 변경 이력'),
          for (final entry in data['history'] as List)
            ListTile(
              title: LText(_status(entry['new_status'] as String)),
              subtitle: LText('${entry['changed_at']}'),
            ),
        ],
        OutlinedButton(
          onPressed: widget.onOrders,
          child: const LText('주문 내역으로 돌아가기'),
        ),
      ],
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
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
