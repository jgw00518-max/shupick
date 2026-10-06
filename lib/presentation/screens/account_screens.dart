import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../localization.dart';

import '../../app/store_controller.dart';
import '../../domain/repositories.dart';
import '../../domain/customer_enrollment.dart';
import '../store_shell.dart';
import '../shared/login_provider_badge.dart';
import '../shared/firestore_access_check_card.dart';
import '../shared/store_widgets.dart';
import '../shared/phone_enrollment_fields.dart';

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
      key: const ValueKey('membership-benefits'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LText('회원 혜택', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
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
        Row(
          children: [
            Flexible(
              child: LText(
                '${store.profileDisplayName ?? '사용자'} 님',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (store.loginProvider != null &&
                store.loginProvider != AccountLoginProvider.email)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: LoginProviderBadge(provider: store.loginProvider),
              ),
          ],
        ),
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
                child: LText(
                  store.reviewsError != null ||
                          store.accountConnectionError != null
                      ? '리뷰 조회 실패'
                      : '리뷰 ${store.reviews.length}개',
                ),
              ),
            ),
          ],
        ),
        if (store.reviewsError != null) ...[
          LText(store.reviewsError!),
          TextButton(
            onPressed: store.refreshReviews,
            child: const LText('리뷰 다시 시도'),
          ),
        ],
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
      if (kDebugMode)
        FirestoreAccessCheckCard(
          key: ValueKey(store.isLoggedIn ? store.accountIdentityKey : null),
        ),
    ],
  );
}

/// 이메일·Google·카카오·네이버 인증의 진입 화면입니다.
class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.store,
    required this.onBack,
    required this.onDone,
    required this.onMessage,
    this.phoneVerifier,
  });
  final StoreController store;
  final VoidCallback onBack;
  final VoidCallback onDone;
  final void Function(String) onMessage;
  final PhoneVerifier? phoneVerifier;
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
  VerifiedPhone? _phoneProof;
  DateTime? _birthDate;
  bool busy = false;
  String loadingTitle = '로그인 중…';
  String loadingDescription = '인증과 회원 정보를 확인하고 있어요.';
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
    if (busy) return;
    _changeMode(value);
  }

  void _changeMode(String value, {bool resetForm = true}) {
    if (!mounted) return;
    if (resetForm) formKey.currentState?.reset();
    password.clear();
    confirm.clear();
    _phoneProof = null;
    _birthDate = null;
    setState(() => mode = value);
  }

  Future<void> submit() async {
    if (busy || !(formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      loadingTitle = switch (mode) {
        'signupEmail' => '회원가입 중…',
        'reset' => '요청 처리 중…',
        _ => '로그인 중…',
      };
      loadingDescription = mode == 'login'
          ? '인증과 회원 정보를 확인하고 있어요.'
          : '잠시만 기다려주세요.';
    });
    var completed = false;
    try {
      if (mode == 'login') {
        final ok = await widget.store.signIn(email.text.trim(), password.text);
        if (!mounted) return;
        if (!ok) {
          widget.onMessage('이메일 또는 비밀번호가 올바르지 않습니다.');
          return;
        }
        widget.onDone();
        completed = true;
      } else if (mode == 'signupEmail') {
        if (widget.store.accountRepository is EnrollmentAccountRepository) {
          final phone = _phoneProof;
          if (phone == null || phone.expired) {
            throw StateError('휴대폰 문자 인증을 완료해주세요.');
          }
          await widget.store.signUpWithEnrollment(
            email.text.trim(),
            password.text,
            phone,
            _birthDate,
            name: name.text.trim().isEmpty ? null : name.text.trim(),
          );
        } else {
          await widget.store.signUp(
            email.text.trim(),
            password.text,
            name: name.text.trim(),
            phone: phone.text.replaceAll(RegExp(r'[^0-9]'), ''),
            birthDate: DateTime(birthYear!, birthMonth!, birthDay!),
          );
        }
        if (!mounted) return;
        widget.onMessage('회원가입이 완료되었습니다. 입력한 계정으로 로그인해주세요.');
        // Preserve the email even if signup finishes before the loading frame
        // unmounts the form. Always clear both password controllers.
        _changeMode('login', resetForm: false);
      } else {
        widget.onMessage('비밀번호 재설정 안내를 이메일로 보냈습니다.');
      }
    } on StateError catch (error) {
      if (mounted) widget.onMessage(error.message);
    } catch (_) {
      if (mounted) {
        widget.onMessage(
          mode == 'signupEmail'
              ? '회원가입을 완료하지 못했습니다. 다시 시도해주세요.'
              : '로그인을 완료하지 못했습니다. 다시 시도해주세요.',
        );
      }
    } finally {
      if (mounted && !completed) setState(() => busy = false);
    }
  }

  Future<void> socialLogin(String provider) async {
    if (busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      loadingTitle = '로그인 중…';
      loadingDescription = '인증과 회원 정보를 확인하고 있어요.';
    });
    var completed = false;
    try {
      final success = await switch (provider) {
        '카카오' => widget.store.signInWithKakao(),
        '네이버' => widget.store.signInWithNaver(),
        _ => widget.store.signInWithGoogle(),
      };
      if (!mounted) return;
      if (success) {
        widget.onDone();
        completed = true;
      } else {
        widget.onMessage('$provider 로그인을 취소했거나 완료하지 못했습니다.');
      }
    } on StateError catch (error) {
      if (mounted) widget.onMessage(error.message);
    } catch (_) {
      if (mounted) widget.onMessage('$provider 로그인을 완료하지 못했습니다. 다시 시도해주세요.');
    } finally {
      // Keep the loading screen until navigation removes this widget. Clearing
      // busy on success could briefly rebuild the old login form.
      if (mounted && !completed) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: busy
        ? _AuthLoadingScreen(
            title: loadingTitle,
            description: loadingDescription,
          )
        : _buildForm(context),
  );

  InputDecoration _loginInputDecoration(
    BuildContext context, {
    required String hint,
    required IconData icon,
  }) {
    final colors = Theme.of(context).colorScheme;
    final underline = UnderlineInputBorder(
      borderSide: BorderSide(color: colors.outlineVariant),
    );
    return InputDecoration(
      hintText: translateMockupText(hint, LocaleScope.languageOf(context)),
      hintStyle: TextStyle(color: colors.onSurfaceVariant),
      prefixIcon: Icon(icon, color: colors.onSurface),
      contentPadding: const EdgeInsets.symmetric(vertical: 18),
      filled: false,
      border: underline,
      enabledBorder: underline,
      disabledBorder: underline,
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
      errorBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: colors.error),
      ),
      focusedErrorBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: colors.error, width: 2),
      ),
    );
  }

  Widget _buildForm(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (busy) return;
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
      const SizedBox(height: 80),
      const LText(
        'SHOEPICK',
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
      const SizedBox(height: 10),
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
              onPressed: busy ? null : () => socialLogin(method),
              child: LText('$method로 가입'),
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
              if (mode == 'signupEmail' &&
                  widget.store.accountRepository
                      is! EnrollmentAccountRepository) ...[
                TextFormField(
                  controller: name,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(
                    labelText: '이름',
                    border: OutlineInputBorder(),
                  ),
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
                    border: OutlineInputBorder(),
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
                decoration: mode == 'login'
                    ? _loginInputDecoration(
                        context,
                        hint: '이메일을 입력해주세요.',
                        icon: Icons.person_outline,
                      )
                    : const InputDecoration(
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
                  decoration: mode == 'login'
                      ? _loginInputDecoration(
                          context,
                          hint: '비밀번호를 입력해주세요.',
                          icon: Icons.lock_outline,
                        )
                      : const InputDecoration(
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
                if (widget.store.accountRepository
                    is EnrollmentAccountRepository) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: name,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                    decoration: const InputDecoration(
                      labelText: '이름 (선택)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => (value?.trim().length ?? 0) > 100
                        ? '이름은 100자 이내로 입력해주세요.'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  PhoneEnrollmentFields(
                    initialProof: _phoneProof,
                    verifier: widget.phoneVerifier,
                    onChanged: (value) => _phoneProof = value,
                  ),
                  const SizedBox(height: 20),
                  BirthdayEnrollmentField(
                    value: _birthDate,
                    onChanged: (value) => setState(() => _birthDate = value),
                  ),
                ],
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
        const Divider(height: 32),
        const LText('간편 로그인', textAlign: TextAlign.center),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: busy ? null : () => socialLogin('카카오'),
              tooltip: '카카오 로그인',
              iconSize: 32,
              icon: const LoginProviderBadge.signInButton(
                provider: AccountLoginProvider.kakao,
              ),
            ),
            IconButton(
              onPressed: busy ? null : () => socialLogin('네이버'),
              tooltip: '네이버 로그인',
              iconSize: 32,
              icon: const LoginProviderBadge.signInButton(
                provider: AccountLoginProvider.naver,
              ),
            ),
            IconButton(
              onPressed: busy ? null : () => socialLogin('Google'),
              tooltip: 'Google 로그인',
              iconSize: 32,
              icon: const LoginProviderBadge.signInButton(
                provider: AccountLoginProvider.google,
              ),
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

/// Remains visible when a provider window returns until login preparation ends.
class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LText(
              'SHUPICK',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 24),
            Semantics(
              liveRegion: true,
              child: LText(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            LText(description, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
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
