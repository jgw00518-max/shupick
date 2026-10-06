import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/repositories.dart';

/// A compact brand-style marker for the account's current sign-in method.
///
/// This is intentionally separate from the customer's display name and UID.
class LoginProviderBadge extends StatelessWidget {
  const LoginProviderBadge({super.key, required this.provider, this.size = 24})
    : _signInButton = false;

  /// The sign-in screen supplies the button's tooltip and accessible label.
  const LoginProviderBadge.signInButton({
    super.key,
    required this.provider,
    this.size = 32,
  }) : _signInButton = true;

  final AccountLoginProvider? provider;
  final double size;
  final bool _signInButton;

  @override
  Widget build(BuildContext context) {
    final (label, background, foreground, letter) = switch (provider) {
      AccountLoginProvider.kakao => (
        '카카오 로그인',
        const Color(0xFFFEE500),
        const Color(0xFF191919),
        'k',
      ),
      AccountLoginProvider.naver => (
        '네이버 로그인',
        const Color(0xFF03C75A),
        Colors.white,
        'N',
      ),
      AccountLoginProvider.google => (
        '구글 로그인',
        Colors.white,
        Colors.transparent,
        '',
      ),
      AccountLoginProvider.email ||
      null => ('', Colors.transparent, Colors.transparent, ''),
    };
    if (label.isEmpty) return const SizedBox.shrink();

    final mark = ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(size / 6),
          ),
          child: provider == AccountLoginProvider.google
              ? const CustomPaint(painter: _GoogleMarkPainter())
              : provider == AccountLoginProvider.kakao && _signInButton
              ? const CustomPaint(painter: _KakaoMarkPainter())
              : Center(
                  child: Text(
                    letter,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: foreground,
                      fontSize: size * .75,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
        ),
      ),
    );
    // IconButton owns semantics/tooltip on the sign-in screen. Avoid two
    // identical tooltip targets or duplicate screen-reader announcements.
    if (_signInButton) return mark;
    return Semantics(
      label: label,
      image: true,
      child: Tooltip(message: label, excludeFromSemantics: true, child: mark),
    );
  }
}

/// Kakao's dark speech-bubble symbol on the badge's yellow background.
class _KakaoMarkPainter extends CustomPainter {
  const _KakaoMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()..color = const Color(0xFF191919);
    canvas.drawOval(const Rect.fromLTWH(4, 5, 16, 11.5), paint);
    final tail = Path()
      ..moveTo(7.5, 14.5)
      ..lineTo(6.5, 19)
      ..lineTo(12, 15.5)
      ..close();
    canvas.drawPath(tail, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _KakaoMarkPainter oldDelegate) => false;
}

/// Draws the familiar four-color G without network requests or extra assets.
class _GoogleMarkPainter extends CustomPainter {
  const _GoogleMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final ring = Rect.fromCircle(center: const Offset(12, 12), radius: 7);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    void arc(Color color, double start, double sweep) {
      paint.color = color;
      canvas.drawArc(
        ring,
        start * math.pi / 180,
        sweep * math.pi / 180,
        false,
        paint,
      );
    }

    arc(const Color(0xFFEA4335), 224.8, 90.4);
    arc(const Color(0xFFFBBC05), 134.8, 90.4);
    arc(const Color(0xFF34A853), 44.8, 90.4);
    arc(const Color(0xFF4285F4), 0, 45.2);
    paint.color = const Color(0xFF4285F4);
    canvas.drawLine(const Offset(12, 12), const Offset(19, 12), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GoogleMarkPainter oldDelegate) => false;
}
