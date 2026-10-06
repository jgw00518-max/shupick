/// MySQL TIME 문자열을 고객 화면에서 시·분만 표시합니다.
String branchTime(Object? value) {
  if (value == null) return '—';
  final parts = value.toString().split(':');
  return parts.length >= 2
      ? '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}'
      : value.toString();
}
