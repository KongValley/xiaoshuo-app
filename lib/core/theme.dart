import 'package:flutter/material.dart';

import '../data/models/reader_settings.dart';

/// App-level theme (bookshelf, import, dialogs).
class AppTheme {
  AppTheme._();

  static const Color seed = Color(0xFF7C5836);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    ).copyWith(
      primary: const Color(0xFF775535),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFF0E1C9),
      onPrimaryContainer: const Color(0xFF3B2A17),
      secondary: const Color(0xFF8D7050),
      surface: const Color(0xFFFFFDF8),
      onSurface: const Color(0xFF2A241C),
      outline: const Color(0xFFE2D5BF),
      outlineVariant: const Color(0xFFEFE5D3),
    );

    return _base(
      scheme: scheme,
      scaffold: const Color(0xFFF8F3E9),
      surfaceExt: const AppSurface(
        canvasTop: Color(0xFFFBF7EE),
        canvasBottom: Color(0xFFF4EDDF),
        hairline: Color(0xFFE6DAC5),
        muted: Color(0xFF8C7F6B),
        card: Color(0xFFFFFCF5),
        tint: Color(0xFFF1E6D1),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFFD9B487),
      onPrimary: const Color(0xFF33240F),
      primaryContainer: const Color(0xFF4A3820),
      onPrimaryContainer: const Color(0xFFF2DFC4),
      secondary: const Color(0xFFC5A57E),
      surface: const Color(0xFF1E1A15),
      onSurface: const Color(0xFFEDE4D5),
      outline: const Color(0xFF3A332A),
      outlineVariant: const Color(0xFF2C2720),
    );

    return _base(
      scheme: scheme,
      scaffold: const Color(0xFF14120E),
      surfaceExt: const AppSurface(
        canvasTop: Color(0xFF191611),
        canvasBottom: Color(0xFF12100C),
        hairline: Color(0xFF332D24),
        muted: Color(0xFF9A8D79),
        card: Color(0xFF211C16),
        tint: Color(0xFF2A231A),
      ),
    );
  }

  static ThemeData _base({
    required ColorScheme scheme,
    required Color scaffold,
    required AppSurface surfaceExt,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
    );

    final textTheme = base.textTheme
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface)
        .copyWith(
          displaySmall: base.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            height: 1.2,
          ),
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 20),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          highlightColor: scheme.primary.withValues(alpha: 0.08),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: surfaceExt.hairline,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.onSurface,
        contentTextStyle: TextStyle(color: scheme.surface, fontSize: 13.5),
        actionTextColor: scheme.primaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        insetPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceExt.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: TextStyle(color: surfaceExt.muted, fontSize: 13.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: surfaceExt.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: surfaceExt.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        textStyle: TextStyle(
          fontSize: 12,
          color: scheme.surface,
          decoration: TextDecoration.none,
        ),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      ),
      extensions: <ThemeExtension<dynamic>>[surfaceExt],
    );
  }

  /// Literary serif used for the wordmark and book covers. It falls back to
  /// whatever serif CJK font the system provides.
  static TextStyle serif(
    double size, {
    FontWeight weight = FontWeight.w600,
    Color? color,
    double height = 1.3,
    double letterSpacing = 0.5,
  }) =>
      TextStyle(
        fontFamily: 'Modu WenKai',
        fontFamilyFallback: const [
          'Modu Song',
          'serif',
        ],
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );
}

@immutable
class AppSurface extends ThemeExtension<AppSurface> {
  const AppSurface({
    required this.canvasTop,
    required this.canvasBottom,
    required this.hairline,
    required this.muted,
    required this.card,
    required this.tint,
  });

  final Color canvasTop;
  final Color canvasBottom;
  final Color hairline;
  final Color muted;
  final Color card;
  final Color tint;

  @override
  AppSurface copyWith({
    Color? canvasTop,
    Color? canvasBottom,
    Color? hairline,
    Color? muted,
    Color? card,
    Color? tint,
  }) =>
      AppSurface(
        canvasTop: canvasTop ?? this.canvasTop,
        canvasBottom: canvasBottom ?? this.canvasBottom,
        hairline: hairline ?? this.hairline,
        muted: muted ?? this.muted,
        card: card ?? this.card,
        tint: tint ?? this.tint,
      );

  @override
  AppSurface lerp(ThemeExtension<AppSurface>? other, double t) {
    if (other is! AppSurface) return this;
    return AppSurface(
      canvasTop: Color.lerp(canvasTop, other.canvasTop, t)!,
      canvasBottom: Color.lerp(canvasBottom, other.canvasBottom, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      card: Color.lerp(card, other.card, t)!,
      tint: Color.lerp(tint, other.tint, t)!,
    );
  }
}

/// Reading surface palette. Kept separate from the app theme so the reader can
/// be warm paper while the shelf is dark (or vice versa).
class ReaderPalette {
  const ReaderPalette({
    required this.id,
    required this.label,
    required this.top,
    required this.bottom,
    required this.text,
    required this.muted,
    required this.accent,
    required this.chrome,
    required this.divider,
  });

  final ReaderThemeId id;
  final String label;
  final Color top;
  final Color bottom;
  final Color text;
  final Color muted;
  final Color accent;
  final Color chrome;
  final Color divider;

  bool get isDark => text.computeLuminance() > 0.5;

  static const ReaderPalette paper = ReaderPalette(
    id: ReaderThemeId.paper,
    label: '纸黄',
    top: Color(0xFFF8F1E2),
    bottom: Color(0xFFF1E7D3),
    text: Color(0xFF352E24),
    muted: Color(0xFF8A7E6A),
    accent: Color(0xFF8A5A34),
    chrome: Color(0xFFFBF6EB),
    divider: Color(0xFFE3D5BD),
  );

  static const ReaderPalette white = ReaderPalette(
    id: ReaderThemeId.white,
    label: '纯白',
    top: Color(0xFFFFFFFF),
    bottom: Color(0xFFF9F8F5),
    text: Color(0xFF23262A),
    muted: Color(0xFF8B9097),
    accent: Color(0xFF7A5B3A),
    chrome: Color(0xFFFFFFFF),
    divider: Color(0xFFE8E5DF),
  );

  static const ReaderPalette green = ReaderPalette(
    id: ReaderThemeId.green,
    label: '护眼',
    top: Color(0xFFE9F1E3),
    bottom: Color(0xFFDCE8D5),
    text: Color(0xFF2C372B),
    muted: Color(0xFF72826D),
    accent: Color(0xFF53734B),
    chrome: Color(0xFFF0F6EB),
    divider: Color(0xFFC9D9BE),
  );

  static const ReaderPalette night = ReaderPalette(
    id: ReaderThemeId.night,
    label: '夜间',
    top: Color(0xFF16181D),
    bottom: Color(0xFF0E1013),
    text: Color(0xFFAEB4BF),
    muted: Color(0xFF6E7683),
    accent: Color(0xFFC2A26A),
    chrome: Color(0xFF1B1E24),
    divider: Color(0xFF2A2E36),
  );

  static const ReaderPalette ink = ReaderPalette(
    id: ReaderThemeId.ink,
    label: '墨黑',
    top: Color(0xFF050505),
    bottom: Color(0xFF000000),
    text: Color(0xFF9AA0A6),
    muted: Color(0xFF5E636A),
    accent: Color(0xFFB99A63),
    chrome: Color(0xFF0B0B0B),
    divider: Color(0xFF1F1F1F),
  );

  static const List<ReaderPalette> all = [paper, white, green, night, ink];

  static ReaderPalette of(ReaderThemeId id) =>
      all.firstWhere((palette) => palette.id == id, orElse: () => paper);
}

/// Typography helpers shared by the paginator and the reader widget. Both must
/// use exactly the same styles for page boundaries to match what is painted.
class ReaderTypography {
  ReaderTypography._();

  static TextStyle body(ReaderSettings settings, ReaderPalette palette) =>
      TextStyle(
        fontSize: settings.fontSize,
        height: settings.lineHeight,
        color: palette.text,
        fontFamily: settings.font.family,
        fontFamilyFallback: settings.font.fallback,
        letterSpacing: 0.2,
      );

  static TextStyle heading(ReaderSettings settings, ReaderPalette palette) =>
      TextStyle(
        fontSize: settings.fontSize + 8,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: palette.text,
        fontFamily: settings.font.family,
        fontFamilyFallback: settings.font.fallback,
        letterSpacing: 0.6,
      );

  static TextStyle meta(ReaderSettings settings, ReaderPalette palette) =>
      TextStyle(
        fontSize: (settings.fontSize - 6).clamp(11.0, 18.0),
        height: 1.3,
        color: palette.muted,
        fontFamily: settings.font.family,
        fontFamilyFallback: settings.font.fallback,
        letterSpacing: 0.8,
      );
}

class CoverPalette {
  const CoverPalette(this.start, this.end, this.ink);

  final Color start;
  final Color end;
  final Color ink;
}

const List<CoverPalette> coverPalettes = [
  CoverPalette(Color(0xFF42604F), Color(0xFF22352B), Color(0xFFE8D9B8)),
  CoverPalette(Color(0xFF7A4B3A), Color(0xFF45271F), Color(0xFFF0DCC4)),
  CoverPalette(Color(0xFF4A4C6E), Color(0xFF292A44), Color(0xFFE2D8C6)),
  CoverPalette(Color(0xFF8A6A3B), Color(0xFF4C3A1F), Color(0xFFF3E3C4)),
  CoverPalette(Color(0xFF5E3B4E), Color(0xFF33222B), Color(0xFFEED9D2)),
  CoverPalette(Color(0xFF33566A), Color(0xFF1D3240), Color(0xFFDCE7E4)),
];

CoverPalette coverPaletteFor(String seed) {
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return coverPalettes[hash % coverPalettes.length];
}
