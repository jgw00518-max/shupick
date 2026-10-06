import 'package:flutter/material.dart';

import '../../domain/customer_enrollment.dart';
import '../localization.dart';
import '../shared/phone_enrollment_fields.dart';

class MemberEnrollmentScreen extends StatefulWidget {
  const MemberEnrollmentScreen({
    super.key,
    required this.repository,
    this.verifier,
  });
  final EnrollmentAccountRepository repository;
  final PhoneVerifier? verifier;
  @override
  State<MemberEnrollmentScreen> createState() => _MemberEnrollmentScreenState();
}

class _MemberEnrollmentScreenState extends State<MemberEnrollmentScreen> {
  final _form = GlobalKey<FormState>();
  EnrollmentProfile? _profile;
  VerifiedPhone? _phone;
  DateTime? _birthDate;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  late final String? _ownerUid;

  bool get _sameAccount =>
      _ownerUid != null && widget.repository.enrollmentUserId == _ownerUid;

  @override
  void initState() {
    super.initState();
    _ownerUid = widget.repository.enrollmentUserId;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!_sameAccount) throw StateError('계정이 변경되었습니다. 화면을 다시 열어주세요.');
      final profile = await widget.repository.getEnrollmentProfile();
      if (!_sameAccount) throw StateError('계정이 변경되었습니다. 화면을 다시 열어주세요.');
      if (mounted) {
        setState(() {
          _profile = profile;
          _birthDate = profile.birthDate;
          _phone = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '회원 정보를 불러오지 못했습니다. 서버와 DB 설정을 확인해주세요.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (!_sameAccount) throw StateError('계정이 변경되었습니다. 화면을 다시 열어주세요.');
      await widget.repository.saveEnrollment(_phone, _birthDate);
      if (!mounted) return;
      if (!_sameAccount) {
        throw StateError('계정이 변경되었습니다. 화면을 다시 열어주세요.');
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: LText('휴대폰 인증·생일 정보가 저장되었습니다.')));
      Navigator.pop(context);
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '정보 저장에 실패했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: const LText('휴대폰 인증·생일 등록'),
        automaticallyImplyLeading: !_saving,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_profile == null) ...[
                  LText(_error ?? '회원 정보를 불러오지 못했습니다.'),
                  TextButton(onPressed: _load, child: const LText('다시 시도')),
                ] else
                  Form(
                    key: _form,
                    child: AbsorbPointer(
                      absorbing: _saving,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_profile!.phoneVerified) ...[
                            LText('등록된 인증 번호: ${_profile!.maskedPhone ?? ''}'),
                            const SizedBox(height: 12),
                          ],
                          PhoneEnrollmentFields(
                            keepExistingPhone: _profile!.phoneVerified,
                            verifier: widget.verifier,
                            onChanged: (value) => _phone = value,
                          ),
                          const SizedBox(height: 20),
                          BirthdayEnrollmentField(
                            value: _birthDate,
                            onChanged: (value) =>
                                setState(() => _birthDate = value),
                          ),
                          const SizedBox(height: 20),
                          if (_error != null) LText(_error!),
                          if (_saving) const LinearProgressIndicator(),
                          FilledButton(
                            onPressed: _saving ? null : _save,
                            child: const LText('정보 저장'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    ),
  );
}
