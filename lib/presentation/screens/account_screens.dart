import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../localization.dart';

import '../../app/store_controller.dart';
import '../../domain/models.dart';
import '../store_shell.dart';
import '../shared/store_widgets.dart';

/// 비회원은 홈을 둘러보고 마이페이지에서 로그인할 수 있습니다.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.store,
    required this.onGo,
    required this.onLogout,
  });
  final StoreController store;
  final void Function(StorePage) onGo;
  final VoidCallback onLogout;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      if (!store.isLoggedIn) ...[
        const SectionTitle('마이페이지'),
        const LText('비회원으로 상품을 둘러보고 있어요.'),
        const SizedBox(height: 20),
        const SectionTitle('로그인하고 쇼핑을 이어가세요'),
        const LText('주문 내역과 쿠폰, 적립금을 한곳에서 확인할 수 있어요.'),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => onGo(StorePage.auth),
          child: const LText('로그인 / 회원가입'),
        ),
      ] else ...[
        const SectionTitle('서준 님'),
        const LText('PLATINUM MEMBER · 다음 VIP까지 128,000원'),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                LText(
                  'SJ',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                ),
                LText('VIP 등급 78%'),
                LText('PLATINUM'),
              ],
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => onGo(StorePage.coupons),
                child: const LText('쿠폰 4장'),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: () => onGo(StorePage.points),
                child: const LText('적립금 32,500P'),
              ),
            ),
            const Expanded(
              child: TextButton(onPressed: null, child: LText('리뷰 12개')),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () async {
              final yes = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const LText('로그아웃'),
                  content: const LText('현재 계정에서 로그아웃하시겠어요?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const LText('취소'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const LText('로그아웃'),
                    ),
                  ],
                ),
              );
              if (yes == true) onLogout();
            },
            child: const LText('로그아웃'),
          ),
        ),
      ],
      const Divider(height: 40),
      for (final item in [
        (
          '주문 내역',
          StorePage.orders,
          Icons.receipt_long_outlined,
          '배송, 교환, 반품 상태 확인',
        ),
        ('문의 사항', StorePage.inquiry, Icons.help_outline, '문의 내역과 답변 확인'),
        (
          '쿠폰과 적립금',
          StorePage.coupons,
          Icons.confirmation_num_outlined,
          '사용 가능한 혜택 모아보기',
        ),
        ('설정', StorePage.settings, Icons.settings_outlined, '테마, 언어, 알림 설정'),
      ].where((item) => store.isLoggedIn || item.$2 == StorePage.settings))
        ListTile(
          leading: Icon(item.$3),
          title: LText(item.$1),
          subtitle: LText(item.$4),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onGo(item.$2),
        ),
    ],
  );
}

/// 이메일 인증만 동작하는 목업 화면입니다.
class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.store,
    required this.onBack,
    required this.onDone,
    required this.onMessage,
  });
  final StoreController store;
  final VoidCallback onBack;
  final VoidCallback onDone;
  final void Function(String) onMessage;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  final guestNumber = TextEditingController();
  final guestDistrict = TextEditingController();
  bool saveEmail = false;
  StoreOrder? guestOrder;
  String mode = 'login';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    final saved = preferences.getString('shupick_saved_login_email');
    if (saved != null && email.text.isEmpty) {
      setState(() {
        email.text = saved;
        saveEmail = true;
      });
    }
  }

  Future<void> _saveEmail(bool enabled) async {
    setState(() => saveEmail = enabled);
    final preferences = await SharedPreferences.getInstance();
    if (enabled) {
      await preferences.setString(
        'shupick_saved_login_email',
        email.text.trim(),
      );
    } else {
      await preferences.remove('shupick_saved_login_email');
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    confirm.dispose();
    guestNumber.dispose();
    guestDistrict.dispose();
    super.dispose();
  }

  void change(String value) {
    formKey.currentState?.reset();
    password.clear();
    confirm.clear();
    setState(() {
      mode = value;
      guestOrder = null;
    });
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      if (mode == 'login') {
        final ok = await widget.store.signIn(email.text.trim(), password.text);
        if (!ok) {
          widget.onMessage('이메일 또는 비밀번호가 올바르지 않습니다.');
          return;
        }
        await _saveEmail(saveEmail);
        if (mounted) widget.onDone();
      } else if (mode == 'guest') {
        final orders = await widget.store.orderRepository.getOrders();
        StoreOrder? match;
        for (final order in orders) {
          if (order.number == guestNumber.text.trim() &&
              order.district == guestDistrict.text.trim()) {
            match = order;
            break;
          }
        }
        if (!mounted) return;
        setState(() => guestOrder = match);
        if (match == null) widget.onMessage('주문번호와 배송 지역을 확인해주세요.');
      } else if (mode == 'signupEmail') {
        await widget.store.signUp(email.text.trim(), password.text);
        widget.onMessage('회원가입이 완료되었습니다. 입력한 계정으로 로그인해주세요.');
        change('login');
      } else {
        widget.onMessage('비밀번호 재설정 안내를 이메일로 보냈습니다.');
      }
    } on StateError catch (error) {
      widget.onMessage(error.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    InputDecoration fieldDecoration(String label) => InputDecoration(
      labelText: label,
      filled: true,
      fillColor: colors.surfaceContainerHighest.withValues(alpha: .5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colors.primary),
      ),
    );
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Theme(
            data: theme.copyWith(
              filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  backgroundColor: brandBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  foregroundColor: colors.onSurface,
                  side: BorderSide(color: colors.outlineVariant),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: '뒤로',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () {
                      if (mode == 'login' || mode == 'guest') {
                        widget.onBack();
                      } else if (mode == 'signupEmail') {
                        change('signup');
                      } else {
                        change('login');
                      }
                    },
                  ),
                ),
                const SizedBox(height: 36),
                const LText(
                  'SHUPICK',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 20),
                LText(
                  switch (mode) {
                    'signup' => '가입 방법 선택',
                    'signupEmail' => '이메일로 가입',
                    'reset' => '비밀번호 재설정',
                    _ => '로그인',
                  },
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 28),
                if (mode == 'login' || mode == 'guest') ...[
                  Row(
                    children: [
                      for (final tab in [
                        ('login', '회원 로그인'),
                        ('guest', '비회원 주문조회'),
                      ])
                        Expanded(
                          child: InkWell(
                            onTap: busy ? null : () => change(tab.$1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 4,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: mode == tab.$1
                                        ? colors.onSurface
                                        : colors.outlineVariant,
                                    width: mode == tab.$1 ? 2 : 1,
                                  ),
                                ),
                              ),
                              child: LText(
                                tab.$2,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: mode == tab.$1
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
                if (mode == 'signup') ...[
                  for (final method in ['카카오', '네이버', 'Google'])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: OutlinedButton(
                        onPressed: () =>
                            widget.onMessage('$method 가입은 준비 중입니다.'),
                        child: LText('$method로 가입 · 준비 중'),
                      ),
                    ),
                  OutlinedButton(
                    onPressed: () => change('signupEmail'),
                    child: const LText('이메일로 가입'),
                  ),
                ] else
                  Form(
                    key: formKey,
                    child: Column(
                      children: [
                        if (mode == 'guest') ...[
                          TextFormField(
                            key: const ValueKey('guest-order-number'),
                            controller: guestNumber,
                            decoration: fieldDecoration('주문번호'),
                            onChanged: (_) => setState(() => guestOrder = null),
                            validator: (value) =>
                                (value?.trim().isEmpty ?? true)
                                ? '주문번호를 입력해주세요.'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const ValueKey('guest-order-district'),
                            controller: guestDistrict,
                            decoration: fieldDecoration('배송 지역 (예: 성동구)'),
                            onChanged: (_) => setState(() => guestOrder = null),
                            validator: (value) =>
                                (value?.trim().isEmpty ?? true)
                                ? '배송 지역을 입력해주세요.'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          const LText(
                            '데모 주문은 주문번호와 배송 지역으로 조회할 수 있습니다.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ] else ...[
                          TextFormField(
                            key: const ValueKey('member-email'),
                            controller: email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: fieldDecoration('이메일'),
                            validator: (value) =>
                                RegExp(
                                  r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                ).hasMatch(value?.trim() ?? '')
                                ? null
                                : '올바른 이메일 주소를 입력해주세요.',
                          ),
                          if (mode != 'reset') ...[
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: password,
                              obscureText: true,
                              decoration: fieldDecoration('비밀번호'),
                              validator: (value) =>
                                  value != null &&
                                      value.length >= 8 &&
                                      RegExp('[A-Za-z]').hasMatch(value) &&
                                      RegExp('[0-9]').hasMatch(value)
                                  ? null
                                  : '영문과 숫자를 포함해 8자 이상 입력해주세요.',
                            ),
                          ],
                          if (mode == 'signupEmail') ...[
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: confirm,
                              obscureText: true,
                              decoration: fieldDecoration('비밀번호 확인'),
                              validator: (value) => value == password.text
                                  ? null
                                  : '비밀번호가 일치하지 않습니다.',
                            ),
                          ],
                        ],
                        if (mode == 'login')
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Checkbox(
                                    value: saveEmail,
                                    onChanged: busy
                                        ? null
                                        : (value) => _saveEmail(value ?? false),
                                  ),
                                  const LText(
                                    '이메일 저장',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                              const Tooltip(
                                message: '자동 로그인은 준비 중입니다.',
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Checkbox(value: false, onChanged: null),
                                    Flexible(
                                      child: LText(
                                        '자동 로그인 · 준비 중',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: busy ? null : submit,
                            child: LText(switch (mode) {
                              'signupEmail' => '가입하기',
                              'reset' => '재설정 안내',
                              'guest' => '주문 조회',
                              _ => '로그인',
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                if (mode == 'guest' && guestOrder != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withValues(
                        alpha: .5,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LText(
                          '주문번호: ${guestOrder!.number}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        LText(guestOrder!.canceled ? '취소된 주문' : '주문 완료'),
                        for (final item in guestOrder!.items)
                          LText(
                            '${item.product.name} · ${item.size} · ${item.quantity}개',
                          ),
                        const SizedBox(height: 8),
                        LText(
                          won(guestOrder!.total),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                if (mode == 'login') ...[
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => change('signup'),
                        child: const LText('회원가입'),
                      ),
                      TextButton(
                        onPressed: () => change('reset'),
                        child: const LText('비밀번호를 잊으셨나요?'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const LText(
                    '데모 계정: user@sole.kr / sole1234',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(child: Divider(color: colors.outlineVariant)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: LText(
                          '간편 로그인',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ),
                      Expanded(child: Divider(color: colors.outlineVariant)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final method in ['네이버', '카카오', 'Google'])
                          Expanded(
                            child: Tooltip(
                              message: '$method 로그인은 준비 중입니다.',
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: 72,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 2,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: colors.outlineVariant,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 56,
                                      height: 56,
                                      alignment: Alignment.center,
                                      child: Image.asset(
                                        switch (method) {
                                          '네이버' => 'assets/auth/naver.png',
                                          '카카오' => 'assets/auth/kakao.png',
                                          _ => 'assets/auth/google.png',
                                        },
                                        width: switch (method) {
                                          '네이버' => 56,
                                          '카카오' => 40,
                                          _ => 28,
                                        },
                                        fit: BoxFit.contain,
                                        semanticLabel: '$method 로그인 로고',
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    LText(
                                      method,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const LText(
                    '간편 로그인 서비스는 준비 중입니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ] else
                  TextButton(
                    onPressed: () => change('login'),
                    child: const LText('로그인으로 돌아가기'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class InfoScreen extends StatelessWidget {
  const InfoScreen({
    super.key,
    required this.title,
    required this.description,
    this.action,
    this.onAction,
  });
  final String title;
  final String description;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) =>
      EmptyState(description, action: action, onAction: onAction);
}
