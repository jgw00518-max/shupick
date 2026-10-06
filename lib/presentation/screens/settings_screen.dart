import 'package:flutter/material.dart';
import '../localization.dart';

import '../shared/store_widgets.dart';
import '../../domain/customer_enrollment.dart';
import 'member_enrollment_screen.dart';

/// 화면·언어·알림 목업 설정을 사용자에게 노출합니다.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.dark,
    required this.language,
    required this.push,
    required this.onDarkChanged,
    required this.onLanguageChanged,
    required this.onPushChanged,
    this.enrollmentRepository,
  });
  final bool dark;
  final String language;
  final bool push;
  final ValueChanged<bool> onDarkChanged;
  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<bool> onPushChanged;
  final EnrollmentAccountRepository? enrollmentRepository;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const SectionTitle('설정'),
      const LText('SHOEPICK을 내 방식으로 사용하세요.'),
      const SizedBox(height: 20),
      if (widget.enrollmentRepository != null) ...[
        const SectionTitle('회원 정보'),
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: const LText('휴대폰 인증·생일 등록'),
          subtitle: const LText('복구용 번호 인증과 선택 생일 정보 등록'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => MemberEnrollmentScreen(
                repository: widget.enrollmentRepository!,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
      const SectionTitle('화면'),
      SwitchListTile(
        title: const LText('다크 테마'),
        subtitle: const LText('어두운 화면으로 전환'),
        value: widget.dark,
        onChanged: widget.onDarkChanged,
      ),
      const SectionTitle('언어'),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: '한국어', label: LText('한국어')),
          ButtonSegment(value: 'English', label: LText('English')),
        ],
        selected: {widget.language},
        onSelectionChanged: (value) => widget.onLanguageChanged(value.first),
      ),
      const SizedBox(height: 20),
      const SectionTitle('알림'),
      SwitchListTile(
        title: const LText('푸시 알림'),
        subtitle: const LText('주문과 혜택 알림 받기'),
        value: widget.push,
        onChanged: widget.onPushChanged,
      ),
      const SwitchListTile(
        title: LText('재입고 알림'),
        subtitle: LText('찜한 상품 소식'),
        value: false,
        onChanged: null,
      ),
      const SwitchListTile(
        title: LText('이벤트 알림'),
        subtitle: LText('신상품과 쿠폰 소식'),
        value: false,
        onChanged: null,
      ),
    ],
  );
}
