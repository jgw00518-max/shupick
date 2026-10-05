import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xFF465B73);
  static const background = Color(0xFFF7F7F5);
  static const ink = Color(0xFF242B33);
  static const muted = Color(0xFF5F6975);
  static const line = Color(0xFFE3E6E9);
  static const rating = Color(0xFFC58A26);
}

abstract final class AppSpacing {
  static const page = 20.0;
  static const card = 16.0;
  static const section = 28.0;
  static const radius = 14.0;
}

/// All screens share bundled Korean/Latin typography, including dark mode.
abstract final class ShoepickTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: brightness,
        ).copyWith(
          primary: dark ? const Color(0xFFB8CBE0) : AppColors.primary,
          onPrimary: dark ? const Color(0xFF203246) : Colors.white,
          surface: dark ? const Color(0xFF1D232B) : Colors.white,
          onSurface: dark ? const Color(0xFFF0F2F5) : AppColors.ink,
          onSurfaceVariant: dark ? const Color(0xFFBAC2CC) : AppColors.muted,
          outlineVariant: dark ? const Color(0xFF39424E) : AppColors.line,
        );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'NotoSansKR',
      colorScheme: scheme,
    );
    final text = base.textTheme
        .copyWith(
          headlineSmall: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
          titleLarge: const TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
          titleMedium: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            height: 1.45,
          ),
          titleSmall: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.45,
          ),
          bodyLarge: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            height: 1.55,
          ),
          bodyMedium: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w500,
            height: 1.55,
          ),
          bodySmall: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            height: 1.5,
          ),
          labelLarge: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
          labelMedium: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
          labelSmall: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
        )
        .apply(
          fontFamily: 'NotoSansKR',
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radius),
    );
    final button = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      shape: WidgetStatePropertyAll(shape),
      textStyle: WidgetStatePropertyAll(text.labelLarge),
    );
    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: dark
          ? const Color(0xFF141A21)
          : AppColors.background,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleMedium,
        toolbarHeight: 60,
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 24),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 24,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: button),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: button.copyWith(
          backgroundColor: WidgetStatePropertyAll(scheme.primary),
          foregroundColor: WidgetStatePropertyAll(scheme.onPrimary),
          elevation: const WidgetStatePropertyAll(0),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(style: button),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: text.labelMedium,
          minimumSize: const Size(44, 44),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
        selectedLabelStyle: text.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: text.labelSmall,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall,
        iconColor: scheme.onSurfaceVariant,
      ),
    );
  }
}
