import 'package:flutter/material.dart';
import '../localization.dart';
import 'app_theme.dart';

/// Exact score is announced once; icons show full, half, and empty stars.
class RatingStars extends StatelessWidget {
  const RatingStars({super.key, required this.rating, this.size = 20});
  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    final score = rating.isFinite ? rating.clamp(0.0, 5.0).toDouble() : 0.0;
    final english = LocaleScope.languageOf(context) == 'English';
    return Semantics(
      label: english
          ? 'Rating ${score.toStringAsFixed(1)} out of 5'
          : '평점 5점 만점에 ${score.toStringAsFixed(1)}점',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 5; i++)
              Padding(
                padding: EdgeInsets.only(right: i == 4 ? 0 : 2),
                child: Icon(
                  score >= i + .75
                      ? Icons.star_rounded
                      : score >= i + .25
                      ? Icons.star_half_rounded
                      : Icons.star_outline_rounded,
                  size: size,
                  color: score >= i + .25
                      ? (Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFFE8B85E)
                            : AppColors.rating)
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
