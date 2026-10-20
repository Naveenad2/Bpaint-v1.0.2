import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

/// A compact, high-density desktop theme. Tuned for 1366x768 laptops
/// (the most common Windows 10 POS screen) and for low-end GPUs:
/// no blur, no shadows heavier than 2dp, no animated backgrounds.
class AppTheme {
  static const Color brand = Color(0xFF1B5E9E);
  static const Color brandDark = Color(0xFF0E3F72);
  static const Color accent = Color(0xFFE8590C);
  static const Color success = Color(0xFF1B8A4B);
  static const Color warning = Color(0xFFB8860B);
  static const Color danger = Color(0xFFC62828);
  static const Color info = Color(0xFF0B7285);

  /// Palette options exposed in Settings.
  static const Map<String, Color> accents = {
    'Ocean Blue': Color(0xFF1B5E9E),
    'Emerald': Color(0xFF0F766E),
    'Indigo': Color(0xFF4338CA),
    'Crimson': Color(0xFFB91C1C),
    'Amber': Color(0xFFB45309),
    'Slate': Color(0xFF334155),
  };

  static ThemeData light(Color seed) => _build(Brightness.light, seed);
  static ThemeData dark(Color seed) => _build(Brightness.dark, seed);

  static ThemeData _build(Brightness b, Color seed) {
    final isDark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: b);
    final surface = isDark ? const Color(0xFF14181D) : const Color(0xFFF6F7F9);
    final card = isDark ? const Color(0xFF1B2027) : Colors.white;
    final border = isDark ? const Color(0xFF2A313A) : const Color(0xFFDFE3E8);

    final base = ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme.copyWith(surface: surface),
      scaffoldBackgroundColor: surface,
      canvasColor: surface,
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.compact,
      fontFamily: _uiFont,
    );

    return base.copyWith(
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface, size: 20),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: isDark ? const Color(0xFF232931) : Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: danger),
        ),
        labelStyle: const TextStyle(fontSize: 13),
        hintStyle: TextStyle(fontSize: 13, color: scheme.outline),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: border),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowHeight: 38,
        dataRowMinHeight: 34,
        dataRowMaxHeight: 40,
        horizontalMargin: 12,
        columnSpacing: 20,
        headingTextStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: scheme.onSurfaceVariant,
          letterSpacing: 0.3,
        ),
        dataTextStyle: const TextStyle(fontSize: 13),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF37404B) : const Color(0xFF2B3038),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        insetPadding: const EdgeInsets.all(16),
      ),
      // No global thumbVisibility: an always-visible thumb asserts unless
      // every Scrollbar has a controller with an attached position.
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(8),
        radius: const Radius.circular(4),
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        visualDensity: VisualDensity.compact,
      ),
      textTheme: _scaled(base.textTheme, 0.96),
    );
  }

  /// Shrinks the type ramp slightly for a denser desktop layout.
  ///
  /// `TextTheme.apply(fontSizeFactor:)` cannot be used here: Material 3 leaves
  /// some slots without an explicit `fontSize`, and `TextStyle.apply` asserts
  /// when asked to scale one of those. This scales only the slots that
  /// actually declare a size and passes the rest through untouched.
  static TextTheme _scaled(TextTheme t, double factor) {
    TextStyle? f(TextStyle? style) {
      final size = style?.fontSize;
      if (style == null || size == null) return style;
      return style.copyWith(fontSize: size * factor);
    }

    return TextTheme(
      displayLarge: f(t.displayLarge),
      displayMedium: f(t.displayMedium),
      displaySmall: f(t.displaySmall),
      headlineLarge: f(t.headlineLarge),
      headlineMedium: f(t.headlineMedium),
      headlineSmall: f(t.headlineSmall),
      titleLarge: f(t.titleLarge),
      titleMedium: f(t.titleMedium),
      titleSmall: f(t.titleSmall),
      bodyLarge: f(t.bodyLarge),
      bodyMedium: f(t.bodyMedium),
      bodySmall: f(t.bodySmall),
      labelLarge: f(t.labelLarge),
      labelMedium: f(t.labelMedium),
      labelSmall: f(t.labelSmall),
    );
  }

  /// Segoe UI on Windows, SF on macOS — both ship with the OS, so the
  /// bundle stays small and text rasterises fast.
  static String? get _uiFont {
    if (defaultTargetPlatform == TargetPlatform.windows) return 'Segoe UI';
    return null;
  }

  static Color borderOf(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? const Color(0xFF2A313A)
          : const Color(0xFFDFE3E8);

  static Color subtleOf(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? const Color(0xFF1F252C)
          : const Color(0xFFF0F2F5);
}

/// Monospaced tabular figures make money columns line up.
const TextStyle kMoneyStyle = TextStyle(
  fontFeatures: [FontFeature.tabularFigures()],
  fontWeight: FontWeight.w600,
);
