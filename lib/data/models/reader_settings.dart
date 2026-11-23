/// Reader appearance settings. These are shared by every book and persisted in
/// `<dataDir>/settings.json`.
class ReaderSettings {
  const ReaderSettings({
    this.fontSize = 19,
    this.lineHeight = 1.8,
    this.font = ReaderFontId.wenkai,
    this.theme = ReaderThemeId.paper,
  });

  final double fontSize;
  final double lineHeight;
  final ReaderFontId font;
  final ReaderThemeId theme;

  ReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    ReaderFontId? font,
    ReaderThemeId? theme,
  }) =>
      ReaderSettings(
        fontSize: (fontSize ?? this.fontSize).clamp(14.0, 32.0),
        lineHeight: (lineHeight ?? this.lineHeight).clamp(1.3, 2.4),
        font: font ?? this.font,
        theme: theme ?? this.theme,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'font': font.name,
        'theme': theme.name,
      };

  factory ReaderSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ReaderSettings();
    return ReaderSettings(
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 19,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.8,
      font: ReaderFontId.values.firstWhere(
        (value) => value.name == json['font'],
        orElse: () => ReaderFontId.wenkai,
      ),
      theme: ReaderThemeId.values.firstWhere(
        (value) => value.name == json['theme'],
        orElse: () => ReaderThemeId.paper,
      ),
    );
  }
}

enum ReaderFontId {
  wenkai('文楷', 'Modu WenKai', [
    'Modu Song',
    'serif',
  ]),
  song('宋体', 'Modu Song', [
    'Modu WenKai',
    'serif',
  ]),
  hei('黑体', 'Modu Hei', [
    'Modu WenKai',
    'sans-serif',
  ]);

  const ReaderFontId(this.label, this.family, this.fallback);

  final String label;
  final String family;
  final List<String> fallback;
}

enum ReaderThemeId {
  paper('纸黄'),
  white('纯白'),
  green('护眼'),
  night('夜间'),
  ink('墨黑');

  const ReaderThemeId(this.label);
  final String label;
}
