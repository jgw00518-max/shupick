import 'package:flutter/material.dart';

import '../../data/firestore_access_probe.dart';

/// Mounted only in debug builds. Firebase is accessed only after a button tap.
class FirestoreAccessCheckCard extends StatefulWidget {
  const FirestoreAccessCheckCard({super.key, this.probeFactory});
  final FirestoreAccessProbe Function()? probeFactory;

  @override
  State<FirestoreAccessCheckCard> createState() =>
      _FirestoreAccessCheckCardState();
}

class _FirestoreAccessCheckCardState extends State<FirestoreAccessCheckCard> {
  bool _busy = false;
  FirestoreAccessReport? _report;
  bool _failed = false;

  Future<void> _check() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _report = null;
      _failed = false;
    });
    try {
      final probe = (widget.probeFactory ?? FirestoreAccessProbe.live)();
      final report = await probe.run();
      if (mounted) setState(() => _report = report);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _label(FirestoreAccessOutcome outcome) => switch (outcome) {
    FirestoreAccessOutcome.ownAllowed => '본인 문서 읽기 허용',
    FirestoreAccessOutcome.blocked => '읽기 차단 (permission-denied)',
    FirestoreAccessOutcome.unauthorizedAllowed => '보안 확인 필요: 타인/비회원 읽기 허용',
    FirestoreAccessOutcome.unverified => '판정 불가: 연결 또는 문서 상태 확인 필요',
  };

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Firestore 접근 검사 · 디버그 전용'),
            const SizedBox(height: 8),
            const Text('테스트 주문 2번의 주문·배송·픽업 상태를 서버에서 직접 읽습니다. 데이터는 변경하지 않습니다.'),
            const SizedBox(height: 8),
            const Text('주문 주인은 읽기 허용, 다른 계정과 비회원은 읽기 차단이어야 합니다.'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : _check,
              child: Text(_busy ? '접근 확인 중…' : 'Firestore 접근 검사'),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_failed)
              const Text('검사를 실행하지 못했습니다. Firebase 연결을 확인하고 다시 시도해 주세요.'),
            if (report != null && report.accountChanged)
              const Text('검사 중 계정이 변경되어 결과를 폐기했습니다. 다시 검사해 주세요.'),
            if (report != null && !report.accountChanged) ...[
              Text(report.signedIn ? '검사 인증: 로그인 계정' : '검사 인증: 비회원'),
              for (final result in report.results)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('${result.path}\n${_label(result.outcome)}'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
