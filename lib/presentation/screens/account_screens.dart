import 'package:flutter/material.dart';
import '../localization.dart';

import '../../app/store_controller.dart';
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
  Widget _membershipCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final membership = store.accountBenefits?['membership'] as Map?;
    final rawAmount = membership?['net_purchase_amount'];
    final amount = rawAmount is num
        ? rawAmount.toInt()
        : int.tryParse('$rawAmount');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.workspace_premium_outlined,
                  color: scheme.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LText(
                      '현재 등급',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    LText(
                      '${membership?['tier_name'] ?? '등급 산정 대기'}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: translateMockupText(
                  '회원 혜택 새로고침',
                  LocaleScope.languageOf(context),
                ),
                onPressed: store.benefitsLoading ? null : store.refreshBenefits,
                icon: const Icon(Icons.refresh, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: 18),
          LText(
            '등급 산정 구매확정 금액',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          LText(
            amount == null ? '—' : won(amount),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          LText(
            '등급은 매월 산정되며 당월 말일까지 유지됩니다.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (store.benefitsLoading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (store.benefitsError != null) ...[
            const SizedBox(height: 12),
            LText(
              store.benefitsError!,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
        ],
      ),
    );
  }

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
        SectionTitle('${store.userName ?? '사용자'} 님'),
        const SizedBox(height: 16),
        _membershipCard(context),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => onGo(StorePage.coupons),
                child: LText(
                  '쿠폰 ${(store.accountBenefits?['coupons'] as List?)?.length ?? 0}장',
                ),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: () => onGo(StorePage.points),
                child: LText(
                  '적립금 ${(store.accountBenefits?['wallet'] as Map?)?['balance'] ?? 0}P',
                ),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: null,
                child: LText('리뷰 ${store.reviews.length}개'),
              ),
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
          '배송, 반품 상태 확인',
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

/// Firebase 계정과 MySQL 고객 프로필에 연결된 회원가입 화면입니다.
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
  final name = TextEditingController();
  final phone = TextEditingController();
  int? birthYear, birthMonth, birthDay;
  int get daysInBirthMonth =>
      DateTime(birthYear ?? 2000, (birthMonth ?? 1) + 1, 0).day;
  String mode = 'login';
  bool busy = false;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    confirm.dispose();
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  void change(String value) {
    formKey.currentState?.reset();
    password.clear();
    confirm.clear();
    setState(() => mode = value);
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
        widget.onDone();
      } else if (mode == 'signupEmail') {
        await widget.store.signUp(
          email.text.trim(),
          password.text,
          name: name.text.trim(),
          phone: phone.text.replaceAll(RegExp(r'[^0-9]'), ''),
          birthDate: DateTime(birthYear!, birthMonth!, birthDay!),
        );
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
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (mode == 'login') {
              widget.onBack();
            } else if (mode == 'signupEmail') {
              change('signup');
            } else {
              change('login');
            }
          },
        ),
      ),
      const SizedBox(height: 24),
      const LText(
        'SHOEPICK',
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
      const SizedBox(height: 8),
      LText(switch (mode) {
        'signup' => '가입 방법 선택',
        'signupEmail' => '이메일로 가입',
        'reset' => '비밀번호 재설정',
        _ => '로그인',
      }, style: const TextStyle(fontSize: 24)),
      const SizedBox(height: 30),
      if (mode == 'signup') ...[
        for (final method in ['카카오', '네이버', 'Google'])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton(
              onPressed: () => widget.onMessage('$method 가입은 준비 중입니다.'),
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
              if (mode == 'signupEmail') ...[
                TextFormField(
                  controller: name,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(labelText: '이름'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '이름을 입력해주세요.'
                      : value.trim().length > 100
                      ? '이름은 100자 이내로 입력해주세요.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: const InputDecoration(
                    labelText: '전화번호',
                    hintText: '010-1234-5678',
                  ),
                  validator: (value) {
                    final digits = (value ?? '').replaceAll(
                      RegExp(r'[^0-9]'),
                      '',
                    );
                    return digits.length >= 9 &&
                            digits.length <= 15 &&
                            RegExp(r'^[+0-9()\s-]+$').hasMatch(value ?? '')
                        ? null
                        : '올바른 전화번호를 입력해주세요.';
                  },
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: LText(
                    '생년월일',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey('year-$birthYear'),
                  initialValue: birthYear,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '년'),
                  items: [
                    for (var year = DateTime.now().year; year >= 1900; year--)
                      DropdownMenuItem(value: year, child: LText('$year')),
                  ],
                  onChanged: busy
                      ? null
                      : (year) => setState(() {
                          birthYear = year;
                          if (birthDay != null &&
                              birthDay! > daysInBirthMonth) {
                            birthDay = null;
                          }
                        }),
                  validator: (value) => value == null ? '출생 연도를 선택해주세요.' : null,
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: ValueKey('month-$birthMonth'),
                        initialValue: birthMonth,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '월'),
                        items: [
                          for (var month = 1; month <= 12; month++)
                            DropdownMenuItem(
                              value: month,
                              child: LText('$month'),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (month) => setState(() {
                                birthMonth = month;
                                if (birthDay != null &&
                                    birthDay! > daysInBirthMonth) {
                                  birthDay = null;
                                }
                              }),
                        validator: (value) =>
                            value == null ? '월을 선택해주세요.' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: ValueKey('day-$birthYear-$birthMonth-$birthDay'),
                        initialValue: birthDay,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '일'),
                        items: [
                          for (var day = 1; day <= daysInBirthMonth; day++)
                            DropdownMenuItem(value: day, child: LText('$day')),
                        ],
                        onChanged: busy
                            ? null
                            : (day) => setState(() => birthDay = day),
                        validator: (value) {
                          if (value == null) return '일을 선택해주세요.';
                          if (birthYear != null &&
                              birthMonth != null &&
                              DateTime(
                                birthYear!,
                                birthMonth!,
                                value,
                              ).isAfter(DateTime.now())) {
                            return '미래 날짜는 선택할 수 없습니다.';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],

              TextFormField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: '이메일',
                  border: OutlineInputBorder(),
                ),
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
                  decoration: const InputDecoration(
                    labelText: '비밀번호',
                    border: OutlineInputBorder(),
                  ),
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
                  decoration: const InputDecoration(
                    labelText: '비밀번호 확인',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value == password.text ? null : '비밀번호가 일치하지 않습니다.',
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy ? null : submit,
                  child: LText(switch (mode) {
                    'signupEmail' => '가입하기',
                    'reset' => '재설정 안내',
                    _ => '로그인',
                  }),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 12),
      if (mode == 'login') ...[
        TextButton(
          onPressed: () => change('signup'),
          child: const LText('회원가입'),
        ),
        TextButton(
          onPressed: () => change('reset'),
          child: const LText('비밀번호를 잊으셨나요?'),
        ),
        const LText(
          '데모 계정: user@sole.kr / sole1234',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const Divider(height: 32),
        const LText('간편 로그인', textAlign: TextAlign.center),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const IconButton(
              onPressed: null,
              tooltip: '카카오 로그인 준비 중',
              icon: LText('K'),
            ),
            const IconButton(
              onPressed: null,
              tooltip: '네이버 로그인 준비 중',
              icon: LText('N'),
            ),
            IconButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);

                      try {
                        final ok = await widget.store.signInWithGoogle();

                        if (ok) {
                          widget.onDone();
                        } else {
                          widget.onMessage('Google 로그인에 실패했습니다.');
                        }
                      } finally {
                        if (mounted) {
                          setState(() => busy = false);
                        }
                      }
                    },
              tooltip: 'Google 로그인',
              icon: const LText('G'),
            ),
          ],
        ),
      ] else
        TextButton(
          onPressed: () => change('login'),
          child: const LText('로그인으로 돌아가기'),
        ),
    ],
  );
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
