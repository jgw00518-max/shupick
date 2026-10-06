import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/firebase_phone_verifier.dart';
import '../../domain/customer_enrollment.dart';
import '../localization.dart';

class PhoneEnrollmentFields extends StatefulWidget {
  const PhoneEnrollmentFields({
    super.key,
    required this.onChanged,
    this.initialProof,
    this.keepExistingPhone = false,
    this.verifier,
  });
  final ValueChanged<VerifiedPhone?> onChanged;
  final VerifiedPhone? initialProof;
  final bool keepExistingPhone;
  final PhoneVerifier? verifier;

  @override
  State<PhoneEnrollmentFields> createState() => _PhoneEnrollmentFieldsState();
}

class _PhoneEnrollmentFieldsState extends State<PhoneEnrollmentFields> {
  late final PhoneVerifier _verifier =
      widget.verifier ?? FirebasePhoneVerifier();
  late final TextEditingController _phone = TextEditingController(
    text: widget.initialProof?.number,
  );
  final _code = TextEditingController();
  VerifiedPhone? _proof;
  bool _consent = false;
  bool _busy = false;
  bool _sent = false;
  String? _error;
  int _cooldown = 0;
  int _generation = 0;
  Timer? _resendTimer;
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    _proof = widget.initialProof?.expired == false ? widget.initialProof : null;
    _consent = _proof != null;
    if (_proof != null) _scheduleExpiry(_proof!);
  }

  void _scheduleExpiry(VerifiedPhone proof) {
    _expiryTimer?.cancel();
    final remaining = proof.verifiedAt
        .add(const Duration(minutes: 5))
        .difference(DateTime.now());
    _expiryTimer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (!mounted) return;
      setState(() {
        _proof = null;
        _sent = false;
        _error = '휴대폰 인증 후 5분이 지났습니다. 다시 인증해주세요.';
      });
      widget.onChanged(null);
    });
  }

  void _clearProof() {
    _generation++;
    _expiryTimer?.cancel();
    _proof = null;
    _sent = false;
    _code.clear();
    _error = null;
    widget.onChanged(null);
  }

  void _accept(VerifiedPhone proof, int generation) {
    if (!mounted || generation != _generation) return;
    if (proof.number != normalizeKoreanMobile(_phone.text)) return;
    setState(() {
      _proof = proof;
      _error = null;
      _code.clear();
    });
    _scheduleExpiry(proof);
    widget.onChanged(proof);
  }

  Future<void> _send() async {
    if (_busy || _cooldown > 0 || !_consent) return;
    try {
      normalizeKoreanMobile(_phone.text);
    } on StateError catch (error) {
      setState(() => _error = error.message);
      return;
    }
    _clearProof();
    final generation = _generation;
    setState(() {
      _busy = true;
      _cooldown = 60;
    });
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _cooldown--);
      if (_cooldown <= 0) timer.cancel();
    });
    try {
      await _verifier.sendCode(
        _phone.text,
        onAutomaticVerification: (proof) => _accept(proof, generation),
      );
      if (mounted && generation == _generation) setState(() => _sent = true);
    } on StateError catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '휴대폰 인증 설정과 네트워크 연결을 확인해주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _accept(await _verifier.verifyCode(_code.text), generation);
    } on StateError catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '인증번호 확인에 실패했습니다. 다시 시도해주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    _resendTimer?.cancel();
    _expiryTimer?.cancel();
    _phone.dispose();
    _code.dispose();
    unawaited(_verifier.close().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextFormField(
        controller: _phone,
        enabled: !_busy,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(
          labelText: widget.keepExistingPhone
              ? '변경할 휴대폰 번호 (기존 번호 유지 가능)'
              : '휴대폰 번호',
          hintText: '01012345678',
          prefixIcon: const Icon(Icons.phone_android),
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(_clearProof),
        validator: (value) {
          if (widget.keepExistingPhone && (value?.trim().isEmpty ?? true)) {
            return null;
          }
          try {
            normalizeKoreanMobile(value ?? '');
          } on StateError catch (error) {
            return error.message;
          }
          if (_proof == null || _proof!.expired || !_consent) {
            return '휴대폰 문자 인증을 완료해주세요.';
          }
          return null;
        },
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _consent,
        onChanged: _busy
            ? null
            : (value) => setState(() {
                _consent = value == true;
                if (!_consent) _clearProof();
              }),
        title: const LText(
          '휴대폰 인증을 위한 Google 전송·저장과 SHOEPICK의 인증된 복구용 번호 저장에 동의합니다.',
        ),
      ),
      OutlinedButton.icon(
        onPressed: !_busy && _consent && _cooldown == 0 ? _send : null,
        icon: const Icon(Icons.sms_outlined),
        label: LText(_cooldown > 0 ? '재요청까지 $_cooldown초' : '문자 인증번호 받기'),
      ),
      if (_sent && _proof == null) ...[
        const SizedBox(height: 8),
        TextField(
          controller: _code,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: const InputDecoration(
            labelText: '문자로 받은 인증번호 6자리',
            border: OutlineInputBorder(),
          ),
        ),
        TextButton(
          onPressed: _busy ? null : _verify,
          child: const LText('인증번호 확인'),
        ),
      ],
      if (_busy) const LinearProgressIndicator(),
      if (_proof != null) const LText('휴대폰 인증 완료 · 5분 안에 저장해주세요.'),
      if (_error != null)
        LText(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      const LText('문자 인증은 번호 소유 확인이며 실명·생년월일 인증은 아닙니다.'),
    ],
  );
}

class BirthdayEnrollmentField extends StatelessWidget {
  const BirthdayEnrollmentField({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const LText('생년월일 (선택)'),
      const LText(
        '생일 혜택을 위한 생년월일 저장에 동의하는 경우 선택해주세요. 생일쿠폰 발급은 팀 정책에 따라 별도로 연결됩니다.',
      ),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.cake_outlined),
            label: LText(
              value == null
                  ? '생년월일 선택'
                  : '${value!.year}.${value!.month.toString().padLeft(2, '0')}.${value!.day.toString().padLeft(2, '0')}',
            ),
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                firstDate: DateTime(1900),
                lastDate: DateTime(now.year, now.month, now.day),
                initialDate: value ?? DateTime(now.year - 20, 1, 1),
              );
              if (picked != null && context.mounted) onChanged(picked);
            },
          ),
          if (value != null)
            TextButton(
              onPressed: () => onChanged(null),
              child: const LText('생일 정보 삭제'),
            ),
        ],
      ),
    ],
  );
}
