import 'package:flutter/material.dart';
import '../localization.dart';

import '../../app/store_controller.dart';
import '../../data/api_order_repository.dart';
import '../../domain/models.dart';
import '../shared/store_widgets.dart';
import '../shared/order_history_card.dart';
import '../shared/cart_item_options.dart';
import 'review_sheet.dart';

const pickupDistricts = [
  '강남구',
  '강동구',
  '강북구',
  '강서구',
  '관악구',
  '광진구',
  '구로구',
  '금천구',
  '노원구',
  '도봉구',
  '동대문구',
  '동작구',
  '마포구',
  '서대문구',
  '서초구',
  '성동구',
  '성북구',
  '송파구',
  '양천구',
  '영등포구',
  '용산구',
  '은평구',
  '종로구',
  '중구',
  '중랑구',
];

/// 선택 주문과 옵션 변경이 가능한 목업 장바구니입니다.
class CartScreen extends StatefulWidget {
  const CartScreen({
    super.key,
    required this.store,
    required this.onOpen,
    required this.onCheckout,
    required this.onMessage,
  });
  final StoreController store;
  final void Function(Product) onOpen;
  final void Function(List<CartItem>) onCheckout;
  final void Function(String) onMessage;
  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  late Set<String> selected;
  @override
  void initState() {
    super.initState();
    selected = widget.store.cart.map((item) => item.key).toSet();
  }

  List<CartItem> get selectedItems =>
      widget.store.cart.where((item) => selected.contains(item.key)).toList();
  int get selectedTotal =>
      selectedItems.fold(0, (sum, item) => sum + item.total);

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: LText(title),
          content: LText(message),
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
      ) ??
      false;

  void _updateOption(CartItem item, {String? size, String? color}) {
    final nextKey =
        '${item.product.id}-${size ?? item.size}-${color ?? item.color}';
    widget.store.updateCartOption(item, size: size, color: color);
    if (selected.remove(item.key)) selected.add(nextKey);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.store.cart;
    selected.removeWhere((key) => !items.any((item) => item.key == key));
    if (items.isEmpty) {
      return const EmptyState('장바구니가 비어 있어요\n마음에 드는 신발을 발견하면 이곳에 담아두세요.');
    }
    final all = selected.length == items.length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            children: [
              Row(
                children: [
                  Checkbox(
                    value: all,
                    onChanged: (_) => setState(() {
                      if (all) {
                        selected.clear();
                      } else {
                        selected = items.map((item) => item.key).toSet();
                      }
                    }),
                  ),
                  LText('전체 선택 (${selected.length})'),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () async {
                            if (!await _confirm(
                              '선택 상품 삭제',
                              '선택한 상품을 장바구니에서 삭제할까요?',
                            )) {
                              return;
                            }
                            widget.store.removeCartKeys(Set.of(selected));
                            setState(selected.clear);
                          },
                    child: const LText('선택 삭제'),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (!await _confirm('장바구니 비우기', '장바구니의 모든 상품을 삭제할까요?')) {
                        return;
                      }
                      widget.store.removeCartKeys(
                        items.map((item) => item.key).toSet(),
                      );
                      setState(selected.clear);
                    },
                    child: const LText('전체 삭제'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final item in items)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: selected.contains(item.key),
                          onChanged: (_) => setState(() {
                            if (!selected.remove(item.key)) {
                              selected.add(item.key);
                            }
                          }),
                        ),
                        InkWell(
                          onTap: () => widget.onOpen(item.product),
                          child: SizedBox(
                            width: 74,
                            child: ProductImage(
                              item.product,
                              height: 82,
                              color: item.color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LText(
                                item.product.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              LText(won(item.product.price)),
                              CartItemOptions(
                                key: ValueKey(item.product.id),
                                item: item,
                                store: widget.store,
                                onChanged: (option) => _updateOption(
                                  item,
                                  size: option.size,
                                  color: option.color,
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: item.quantity <= 1
                                        ? null
                                        : () => widget.store.changeQuantity(
                                            item,
                                            item.quantity - 1,
                                          ),
                                    icon: const Icon(Icons.remove),
                                  ),
                                  LText('${item.quantity}'),
                                  IconButton(
                                    onPressed: item.quantity >= 99
                                        ? null
                                        : () => widget.store.changeQuantity(
                                            item,
                                            item.quantity + 1,
                                          ),
                                    icon: const Icon(Icons.add),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    onPressed: () {
                                      widget.store.removeCartKeys({item.key});
                                      selected.remove(item.key);
                                      widget.onMessage('장바구니에서 상품을 삭제했어요.');
                                    },
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const LText('선택 상품'),
                    const Spacer(),
                    LText(
                      '${selectedItems.fold(0, (sum, item) => sum + item.quantity)}개',
                    ),
                  ],
                ),
                Row(
                  children: [
                    const LText('상품 금액'),
                    const Spacer(),
                    LText(won(selectedTotal)),
                  ],
                ),
                const Row(children: [LText('배송비'), Spacer(), LText('무료')]),
                const Divider(),
                Row(
                  children: [
                    const LText('결제 예정'),
                    const Spacer(),
                    LText(
                      won(selectedTotal),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: LText(
                    '쿠폰·적립금은 결제 단계에서 사용하세요.',
                    style: TextStyle(fontSize: 15, color: Color(0xFF5F6975)),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => widget.onCheckout(selectedItems),
                    child: LText(
                      selected.isEmpty
                          ? '주문할 상품을 선택하세요'
                          : '${won(selectedTotal)} 주문하기',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 목업과 동일한 픽업·결제·완료 단계를 제공합니다.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.store,
    required this.lines,
    required this.fromCart,
    required this.onComplete,
  });
  final StoreController store;
  final List<CartItem> lines;
  final bool fromCart;
  final VoidCallback onComplete;
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  int step = 1;
  String district = '성동구';
  String payment = '카드';
  String coupon = '';
  List<CheckoutCoupon> coupons = [];
  int pointBalance = 0;
  bool benefitsLoading = true;
  String? benefitsError;
  int points = 0;
  bool agreed = false;
  bool submitting = false;
  bool branchesLoading = true;
  String? branchError;
  List<PickupBranch> branches = [];
  StoreOrder? created;
  final pointsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBranches();
    _loadBenefits();
  }

  Future<void> _loadBenefits() async {
    setState(() {
      benefitsLoading = true;
      benefitsError = null;
    });
    try {
      final loadedCoupons = await widget.store.getCoupons();
      final balance = await widget.store.getPointBalance();
      if (mounted) {
        setState(() {
          coupons = loadedCoupons;
          pointBalance = balance;
        });
      }
    } catch (_) {
      if (mounted) setState(() => benefitsError = '쿠폰·포인트 조회에 실패했습니다.');
    } finally {
      if (mounted) setState(() => benefitsLoading = false);
    }
  }

  Future<void> _loadBranches() async {
    try {
      final loaded = await widget.store.getPickupBranches();
      if (!mounted) return;
      setState(() {
        branches = loaded;
        branchError = loaded.isEmpty ? '현재 선택 가능한 픽업 대리점이 없습니다.' : null;
        if (loaded.isNotEmpty &&
            !loaded.any((branch) => branch.districtName == district)) {
          district = loaded.first.districtName;
        }
      });
    } catch (_) {
      if (mounted) setState(() => branchError = '픽업 대리점을 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => branchesLoading = false);
    }
  }

  @override
  void dispose() {
    pointsController.dispose();
    super.dispose();
  }

  int get subtotal => widget.lines.fold(0, (sum, item) => sum + item.total);
  bool get sneakers =>
      widget.lines.any((item) => item.product.category == '운동화');
  int get discount =>
      coupons
          .where((item) => item.id.toString() == coupon)
          .firstOrNull
          ?.discount(subtotal) ??
      0;
  int get validPoints =>
      points.clamp(0, pointBalance.clamp(0, subtotal - discount));
  int get total => (subtotal - discount - validPoints).clamp(0, subtotal);

  Future<void> _pay() async {
    if (!agreed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: LText('결제 전 필수 동의 항목을 확인해주세요.')));
      return;
    }
    setState(() => submitting = true);
    try {
      final order = await widget.store.placeOrder(
        district,
        lines: widget.lines,
        paidTotal: total,
        couponDiscount: discount,
        pointsUsed: validPoints,
        paymentMethod: payment,
        customerCouponId: int.tryParse(coupon),
        fromCart: widget.fromCart,
      );
      if (mounted) {
        setState(() {
          created = order;
          step = 3;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: LText('주문을 완료하지 못했습니다: $error')));
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (step == 3) return _success();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const SectionTitle('주문하기'),
        const LText('주문 상품과 픽업 대리점을 확인해주세요.'),
        const SizedBox(height: 14),
        LText(
          '1 픽업    ──    2 결제    ──    3 완료',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 18),
        SectionTitle(
          '주문 상품 ${widget.lines.fold(0, (sum, item) => sum + item.quantity)}개',
        ),
        const SizedBox(height: 14),
        for (final item in widget.lines)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 76,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ProductImage(
                      item.product,
                      height: 82,
                      color: item.color,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LText(
                        item.product.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LText(
                        '${item.color} · ${item.size}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          LText(
                            '${item.quantity}개',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          LText(
                            won(item.total),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        const Divider(height: 30),
        if (step == 1) ...[
          const SectionTitle('픽업 대리점'),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: district,
            decoration: const InputDecoration(
              labelText: '서울시 자치구',
              border: OutlineInputBorder(),
            ),
            items:
                (branches.isEmpty
                        ? [district]
                        : branches.map((item) => item.districtName).toSet())
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: LText(value)),
                    )
                    .toList(),
            onChanged: branchesLoading || branchError != null
                ? null
                : (value) => setState(() => district = value!),
          ),
          if (branchesLoading) const LinearProgressIndicator(),
          if (branchError != null)
            Row(
              children: [
                Expanded(child: LText(branchError!)),
                TextButton(
                  onPressed: _loadBranches,
                  child: const LText('다시 시도'),
                ),
              ],
            ),
          const SizedBox(height: 12),
          PickupStoreInfo(
            district: district,
            branch: branches
                .where((branch) => branch.districtName == district)
                .firstOrNull,
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed:
                branchesLoading || branchError != null || branches.isEmpty
                ? null
                : () => setState(() => step = 2),
            child: const LText('결제 수단 선택'),
          ),
        ] else ...[
          ListTile(
            title: LText(
              branches
                      .where((branch) => branch.districtName == district)
                      .firstOrNull
                      ?.name ??
                  '대리점 정보 미등록',
            ),
            subtitle: const LText('픽업 대리점'),
            trailing: TextButton(
              onPressed: () => setState(() => step = 1),
              child: const LText('수정'),
            ),
          ),
          PickupStoreInfo(
            district: district,
            compact: true,
            branch: branches
                .where((branch) => branch.districtName == district)
                .firstOrNull,
          ),
          const SizedBox(height: 16),
          const SectionTitle('결제 수단'),
          for (final method in ['카드', '카카오페이', '네이버페이'])
            ListTile(
              title: LText(method),
              trailing: Icon(
                payment == method
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              onTap: () => setState(() => payment = method),
            ),
          const SizedBox(height: 10),
          const LText('쿠폰 선택'),
          if (benefitsLoading) const LinearProgressIndicator(),
          if (benefitsError != null)
            TextButton(
              onPressed: _loadBenefits,
              child: LText('$benefitsError 다시 시도'),
            ),
          DropdownButtonFormField<String>(
            initialValue: coupon,
            items: [
              const DropdownMenuItem(value: '', child: LText('사용 안 함')),
              for (final item in coupons.where(
                (item) => subtotal >= item.minimum,
              ))
                DropdownMenuItem(
                  value: item.id.toString(),
                  child: LText(item.name),
                ),
            ],
            onChanged: benefitsLoading || benefitsError != null
                ? null
                : (value) => setState(() => coupon = value ?? ''),
          ),
          const SizedBox(height: 12),
          LText('적립금 사용 · 보유 ${won(pointBalance)}'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: pointsController,
                  enabled: !benefitsLoading && benefitsError == null,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: '0'),
                  onChanged: (value) => setState(
                    () => points =
                        int.tryParse(value.replaceAll(RegExp(r'\D'), '')) ?? 0,
                  ),
                ),
              ),
              TextButton(
                onPressed: benefitsLoading || benefitsError != null
                    ? null
                    : () => setState(() {
                        points = pointBalance.clamp(0, subtotal - discount);
                        pointsController.text = points.toString();
                      }),
                child: const LText('전액 사용'),
              ),
            ],
          ),
          const Divider(height: 30),
          _amount('상품 금액', subtotal),
          if (discount > 0) _amount('쿠폰 할인', -discount),
          if (validPoints > 0) _amount('적립금 사용', -validPoints),
          _amount('최종 결제', total, bold: true),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: agreed,
            onChanged: (value) => setState(() => agreed = value ?? false),
            title: const LText('필수 · 개인정보 수집 및 구매 조건에 동의합니다.'),
          ),
          FilledButton(
            onPressed: submitting ? null : _pay,
            child: LText(submitting ? '처리 중...' : '$payment로 ${won(total)} 결제'),
          ),
        ],
      ],
    );
  }

  Widget _amount(String label, int value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        LText(label),
        const Spacer(),
        LText(
          value < 0 ? '-${won(-value)}' : won(value),
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    ),
  );

  Widget _success() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Icon(Icons.check_circle, size: 60, color: brandBlue),
      const Center(child: SectionTitle('주문이 완료되었습니다')),
      const Center(child: LText('감사합니다')),
      const SizedBox(height: 20),
      Center(child: LText('주문번호 ${created!.number}')),
      Center(
        child: LText(
          '주문 상품 ${widget.lines.fold(0, (sum, item) => sum + item.quantity)}개 · 결제 금액 ${won(total)}',
        ),
      ),
      const SizedBox(height: 14),
      LText(
        '사용 적립금 -${validPoints}P\n남은 적립금 ${32500 - validPoints}P\n구매 적립 예정 +${(total * .02).floor()}P',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: widget.onComplete,
        child: const LText('주문 내역 보기'),
      ),
    ],
  );
}

/// 선택한 실제 대리점의 운영 정보만 표시하고 미등록 값은 추측하지 않습니다.
class PickupStoreInfo extends StatelessWidget {
  const PickupStoreInfo({
    super.key,
    required this.district,
    this.branch,
    this.compact = false,
  });
  final String district;
  final PickupBranch? branch;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!compact)
              LText(
                branch?.name ?? '대리점 정보를 불러오는 중입니다.',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            LText(
              '주소 · ${branch?.address.isNotEmpty == true ? branch!.address : '미등록'}',
            ),
            LText(
              '대리점 연락처 · ${branch?.phone.isNotEmpty == true ? branch!.phone : '미등록'}',
            ),
            if (branch?.businessHours.isNotEmpty != true)
              const LText('운영시간 · 미등록'),
            for (final hour
                in branch?.businessHours ?? <Map<String, dynamic>>[])
              LText(
                '${const ['월', '화', '수', '목', '금', '토', '일'][(hour['dayOfWeek'] as int) - 1]}요일 · ${hour['isClosed'] == true
                    ? '휴무'
                    : hour['opensAt'] == null || hour['closesAt'] == null
                    ? '운영시간 미등록'
                    : '${hour['opensAt']}–${hour['closesAt']}'}',
              ),
          ],
        ),
      ),
    );
  }
}

/// 주문 상세·픽업 QR·리뷰·배송 조회를 연결합니다.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({
    super.key,
    required this.store,
    required this.onMessage,
    required this.onShipping,
  });
  final StoreController store;
  final void Function(String) onMessage;
  final void Function(StoreOrder) onShipping;

  Future<void> _returnHistory(BuildContext context) async {
    final repository = store.orderRepository;
    if (repository is! ApiOrderRepository) return;
    try {
      final entries = await repository.getReturns();
      for (final entry in entries) {
        if (entry['status'] != 'REJECTED' && entry['status'] != 'CANCELED') {
          entry['quote'] = await repository.getReturnQuote(
            (entry['id'] as num).toInt(),
          );
        }
      }
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const LText('반품·환불 내역'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (entries.isEmpty) const LText('반품 신청 내역이 없습니다.'),
                for (final entry in entries)
                  ListTile(
                    title: LText(
                      '주문 ${entry['orderId']} · ${switch (entry['status']) {
                        'REQUESTED' => '검수 대기',
                        'APPROVED' => '승인',
                        'REJECTED' => '반려',
                        'COMPLETED' => '반품 처리 완료',
                        'REFUNDED' => '환불 완료',
                        _ => entry['status'],
                      }}',
                    ),
                    subtitle: LText(
                      '${entry['reason']}${entry['quote'] == null ? '' : '\n예상 환불액 ${won((entry['quote']['refundAmount'] as num).toInt())} · 배분 포인트 ${entry['quote']['allocatedPoints']}P\n만료된 포인트는 복원되지 않습니다.'}',
                    ),
                    trailing: LText(
                      won((entry['refundAmount'] as num).toInt()),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const LText('닫기'),
            ),
          ],
        ),
      );
    } catch (error) {
      onMessage('반품 내역 조회 실패: $error');
    }
  }

  Future<void> _return(BuildContext context, StoreOrder order) async {
    final quantities = <String, int>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const LText('상품 선택 반품 신청'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LText(
                  '수령 후 7일 이내, 미착용·훼손 없음·구성품과 포장 유지 조건의 단순변심 반품입니다. 검수 후 환불됩니다.',
                ),
                for (final item in order.items)
                  ListTile(
                    title: Text(item.product.name),
                    subtitle: Text('${item.color} / ${item.size}'),
                    trailing: DropdownButton<int>(
                      value: quantities[item.key] ?? 0,
                      items: List.generate(
                        item.quantity + 1,
                        (quantity) => DropdownMenuItem(
                          value: quantity,
                          child: Text(quantity == 0 ? '선택 안 함' : '$quantity개'),
                        ),
                      ),
                      onChanged: (quantity) => setDialogState(() {
                        if (quantity == null || quantity == 0) {
                          quantities.remove(item.key);
                        } else {
                          quantities[item.key] = quantity;
                        }
                      }),
                    ),
                  ),
                const LText('한 주문당 반품 신청은 한 번만 가능합니다. 신청할 상품을 모두 선택해주세요.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const LText('닫기'),
            ),
            FilledButton(
              onPressed: quantities.isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              child: const LText('신청'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final repository = store.orderRepository;
    if (repository is! ApiOrderRepository) {
      onMessage('서버 연결이 필요합니다.');
      return;
    }
    try {
      await repository.requestReturn(
        order,
        '고객 단순변심 선택 반품',
        quantities: quantities,
      );
      onMessage('반품 신청이 접수되었습니다. 대리점 검수를 기다려주세요.');
    } catch (error) {
      onMessage('반품 신청 실패: $error');
    }
  }

  void _detail(BuildContext context, StoreOrder order) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const LText('주문 상세'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LText(
              '${order.number} · ${order.date.year}.${order.date.month}.${order.date.day}',
            ),
            const Divider(),
            for (final item in order.items)
              ListTile(
                title: LText(item.product.name),
                subtitle: LText(
                  '${item.color} · ${item.size} · ${item.quantity}켤레',
                ),
                trailing: LText(won(item.total)),
              ),
            LText(
              '총 주문 수량 ${order.items.fold(0, (sum, item) => sum + item.quantity)}켤레',
            ),
            LText('최종 결제 금액 ${won(order.total)}'),
            LText('픽업 대리점 SHOEPICK ${order.district}점'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const LText('확인'),
        ),
      ],
    ),
  );

  void _qr(BuildContext context, StoreOrder order) => showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return AlertDialog(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: LText(
          '픽업 결제 코드',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        content: SingleChildScrollView(
          child: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LText(
                  '매장 픽업용',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .06),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: .2),
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SelectableText(
                    order.number,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .6,
                      height: 1.5,
                      color: scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                LText(
                  'SHOEPICK ${order.district}점 직원에게 보여주세요.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const LText('닫기', textAlign: TextAlign.center),
            ),
          ),
        ],
      );
    },
  );

  Future<void> _confirmPurchase(BuildContext context, StoreOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LText('구매확정'),
        content: const LText(
          '구매확정 후에는 반품·환불이 불가능합니다. 구매확정하면 리뷰를 작성할 수 있으며 최초 작성 시 1,000P가 적립됩니다. 구매확정 금액은 다음 회원등급 산정에 반영됩니다. 확정할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const LText('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const LText('확정'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await store.confirmPurchase(order);
      onMessage('구매확정이 완료되었습니다.');
    } catch (error) {
      onMessage('구매확정 실패: $error');
    }
  }

  void _writeReview(BuildContext context, StoreOrder order, CartItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReviewSheet(
        order: order,
        item: item,
        store: store,
        onSaved: () => onMessage('리뷰가 저장되었어요.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: store.refreshOrders,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          const SectionTitle('나의 주문'),
          const SizedBox(height: 8),
          LText(
            '주문과 배송 상태를 확인하세요.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              LText(
                '전체 주문 ${store.orders.length}건',
                style: theme.textTheme.titleSmall,
              ),
              TextButton(
                onPressed: () => _returnHistory(context),
                child: const LText('반품·환불 내역'),
              ),
              IconButton(
                tooltip: '새로고침',
                onPressed: store.ordersLoading ? null : store.refreshOrders,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (store.ordersLoading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
          ],
          if (store.ordersError != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LText(store.ordersError!),
                    TextButton(
                      onPressed: store.refreshOrders,
                      child: const LText('다시 시도'),
                    ),
                  ],
                ),
              ),
            ),
          if (!store.ordersLoading &&
              store.ordersError == null &&
              store.orders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: EmptyState('주문 내역이 없습니다. 로그인 후 주문을 확인해주세요.'),
            ),
          for (final order in store.orders)
            OrderHistoryCard(
              order: order,
              onDetail: () => _detail(context, order),
              onShipping: () => onShipping(order),
              onCode: () => _qr(context, order),
              onConfirm: () => _confirmPurchase(context, order),
              onReturn: () => _return(context, order),
              hasReview: (item) => store.hasReview(order, item),
              onReview: (item) => _writeReview(context, order, item),
            ),
        ],
      ),
    );
  }
}
