import 'package:flutter/material.dart';

import '../data/models/reader_settings.dart';

/// App-level theme (bookshelf, import, dialogs).
class AppTheme {
  AppTheme._();

  static const Color seed = Color(0xFF785233);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    ).copyWith(
      primary: const Color(0xFF734F30),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFEFDFC6),
      onPrimaryContainer: const Color(0xFF3A2715),
      secondary: const Color(0xFF8C6D4D),
      surface: const Color(0xFFFFFCF6),
      onSurface: const Color(0xFF262018),
      outline: const Color(0xFFE0D2BA),
      outlineVariant: const Color(0xFFEDE2CE),
      error: const Color(0xFFB73E2B),
    );

    return _base(
      scheme: scheme,
      scaffold: const Color(0xFFF7F2E7),
      surfaceExt: const AppSurface(
        canvasTop: Color(0xFFFAF5EA),
        canvasBottom: Color(0xFFF1E9D8),
        hairline: Color(0xFFE4D7C1),
        muted: Color(0xFF857763),
        card: Color(0xFFFFFCF7),
        tint: Color(0xFFEFE4CE),
        elevated: Color(0xFFFFFFFF),
        seal: Color(0xFFC1442D),
        sealSoft: Color(0x16C1442D),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFFD9B487),
      onPrimary: const Color(0xFF2E200D),
      primaryContainer: const Color(0xFF47351D),
      onPrimaryContainer: const Color(0xFFF3E0C5),
      secondary: const Color(0xFFC1A17A),
      surface: const Color(0xFF1D1914),
      onSurface: const Color(0xFFECE2D2),
      outline: const Color(0xFF393127),
      outlineVariant: const Color(0xFF2A241D),
      error: const Color(0xFFE06D58),
    );

    return _base(
      scheme: scheme,
      scaffold: const Color(0xFF14110D),
      surfaceExt: const AppSurface(
        canvasTop: Color(0xFF191510),
        canvasBottom: Color(0xFF100E0A),
        hairline: Color(0xFF312A21),
        muted: Color(0xFF9B8E7A),
        card: Color(0xFF201B15),
        tint: Color(0xFF2A231B),
        elevated: Color(0xFF27211A),
        seal: Color(0xFFD8644B),
        sealSoft: Color(0x22D8644B),
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
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 13.5,
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
          borderRadius: BorderRadius.circular(7),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      ),
      extensions: <ThemeExtension<dynamic>>[surfaceExt],
    );
  }

  /// Literary serif used for the wordmark and book covers.
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
    required this.elevated,
    required this.seal,
    required this.sealSoft,
  });

  final Color canvasTop;
  final Color canvasBottom;
  final Color hairline;
  final Color muted;
  final Color card;
  final Color tint;
  final Color elevated;
  final Color seal;
  final Color sealSoft;

  @override
  AppSurface copyWith({
    Color? canvasTop,
    Color? canvasBottom,
    Color? hairline,
    Color? muted,
    Color? card,
    Color? tint,
    Color? elevated,
    Color? seal,
    Color? sealSoft,
  }) =>
      AppSurface(
        canvasTop: canvasTop ?? this.canvasTop,
        canvasBottom: canvasBottom ?? this.canvasBottom,
        hairline: hairline ?? this.hairline,
        muted: muted ?? this.muted,
        card: card ?? this.card,
        tint: tint ?? this.tint,
        elevated: elevated ?? this.elevated,
        seal: seal ?? this.seal,
        sealSoft: sealSoft ?? this.sealSoft,
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
      elevated: Color.lerp(elevated, other.elevated, t)!,
      seal: Color.lerp(seal, other.seal, t)!,
      sealSoft: Color.lerp(sealSoft, other.sealSoft, t)!,
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
    top: Color(0xFFF7F0E0),
    bottom: Color(0xFFEEE3CD),
    text: Color(0xFF332B21),
    muted: Color(0xFF887A65),
    accent: Color(0xFF935531),
    chrome: Color(0xFFFAF4E7),
    divider: Color(0xFFE0D1B8),
  );

  static const ReaderPalette white = ReaderPalette(
    id: ReaderThemeId.white,
    label: '纯白',
    top: Color(0xFFFFFFFF),
    bottom: Color(0xFFF8F7F3),
    text: Color(0xFF22252A),
    muted: Color(0xFF878C94),
    accent: Color(0xFF7D5937),
    chrome: Color(0xFFFFFFFF),
    divider: Color(0xFFE7E3DC),
  );

  static const ReaderPalette green = ReaderPalette(
    id: ReaderThemeId.green,
    label: '护眼',
    top: Color(0xFFEAF2E4),
    bottom: Color(0xFFDCE8D4),
    text: Color(0xFF2A3629),
    muted: Color(0xFF6F806A),
    accent: Color(0xFF4D6F45),
    chrome: Color(0xFFF0F6EB),
    divider: Color(0xFFC8D9BD),
  );

  static const ReaderPalette night = ReaderPalette(
    id: ReaderThemeId.night,
    label: '夜间',
    top: Color(0xFF17191E),
    bottom: Color(0xFF101216),
    text: Color(0xFFB3B9C4),
    muted: Color(0xFF6F7785),
    accent: Color(0xFFC9A66B),
    chrome: Color(0xFF1C1F26),
    divider: Color(0xFF2C313B),
  );

  static const ReaderPalette ink = ReaderPalette(
    id: ReaderThemeId.ink,
    label: '墨黑',
    top: Color(0xFF060606),
    bottom: Color(0xFF000000),
    text: Color(0xFF9AA0A8),
    muted: Color(0xFF5D6269),
    accent: Color(0xFFC09E64),
    chrome: Color(0xFF0D0D0D),
    divider: Color(0xFF202020),
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
  const CoverPalette(this.start, this.end, this.ink, this.accent);

  final Color start;
  final Color end;
  final Color ink;
  final Color accent;
}

const List<CoverPalette> coverPalettes = [
  CoverPalette(Color(0xFF3E5B4B), Color(0xFF203228), Color(0xFFEEE0C3), Color(0xFFC96449)),
  CoverPalette(Color(0xFF774636), Color(0xFF42241C), Color(0xFFF2DFC7), Color(0xFFD89E68)),
  CoverPalette(Color(0xFF444869), Color(0xFF24273F), Color(0xFFE6DCCB), Color(0xFFC96850)),
  CoverPalette(Color(0xFF836237), Color(0xFF47351B), Color(0xFFF5E6C8), Color(0xFFC65A3D)),
  CoverPalette(Color(0xFF5A374A), Color(0xFF311E28), Color(0xFFF0DBD5), Color(0xFFD28B63)),
  CoverPalette(Color(0xFF2F5366), Color(0xFF1A2F3D), Color(0xFFE0ECE8), Color(0xFFCC684C)),
  CoverPalette(Color(0xFF4D423A), Color(0xFF29221E), Color(0xFFEFE3CF), Color(0xFFC4523A)),
];

CoverPalette coverPaletteFor(String seed) {
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return coverPalettes[hash % coverPalettes.length];
}
