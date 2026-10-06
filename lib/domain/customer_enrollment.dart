/// SMS proves possession of a phone number, not a verified legal identity.
String normalizeKoreanMobile(String value) {
  final number = value.trim().replaceAll(RegExp(r'[\s-]'), '');
  if (RegExp(r'^010\d{8}$').hasMatch(number)) {
    return '+82${number.substring(1)}';
  }
  if (RegExp(r'^\+8210\d{8}$').hasMatch(number)) return number;
  throw StateError('010으로 시작하는 휴대폰 번호 11자리를 입력해주세요.');
}

class VerifiedPhone {
  VerifiedPhone({required this.number, required this.idToken})
    : verifiedAt = DateTime.now();
  final String number;
  final String idToken;
  final DateTime verifiedAt;
  bool get expired =>
      DateTime.now().difference(verifiedAt) >= const Duration(minutes: 5);
  @override
  String toString() => 'VerifiedPhone(redacted)';
}

abstract interface class PhoneVerifier {
  Future<void> sendCode(
    String phone, {
    required void Function(VerifiedPhone) onAutomaticVerification,
  });
  Future<VerifiedPhone> verifyCode(String code);
  Future<void> close();
}

class EnrollmentProfile {
  const EnrollmentProfile({
    required this.phoneVerified,
    this.maskedPhone,
    this.birthDate,
  });
  final bool phoneVerified;
  final String? maskedPhone;
  final DateTime? birthDate;
}

/// Optional capability; mock repositories retain their existing behavior.
abstract interface class EnrollmentAccountRepository {
  String? get enrollmentUserId;
  Future<void> signUpWithEnrollment(
    String email,
    String password,
    VerifiedPhone phone,
    DateTime? birthDate,
  );
  Future<EnrollmentProfile> getEnrollmentProfile();
  Future<void> saveEnrollment(VerifiedPhone? phone, DateTime? birthDate);
}
