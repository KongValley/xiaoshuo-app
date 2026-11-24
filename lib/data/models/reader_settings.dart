/// Reader appearance settings. These are shared by every book and persisted in
/// `<dataDir>/settings.json`.
class ReaderSettings {
  const ReaderSettings({
    this.fontSize = 19,
    this.lineHeight = 1.8,
    this.font = ReaderFontId.wenkai,
    this.theme = ReaderThemeId.paper,
    this.pageTurn = PageTurnMode.cover,
    this.margin = ReaderMarginLevel.standard,
    this.pageLayout = ReaderPageLayout.auto,
  });

  final double fontSize;
  final double lineHeight;
  final ReaderFontId font;
  final ReaderThemeId theme;
  final PageTurnMode pageTurn;
  final ReaderMarginLevel margin;
  final ReaderPageLayout pageLayout;

  ReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    ReaderFontId? font,
    ReaderThemeId? theme,
    PageTurnMode? pageTurn,
    ReaderMarginLevel? margin,
    ReaderPageLayout? pageLayout,
  }) =>
      ReaderSettings(
        fontSize: (fontSize ?? this.fontSize).clamp(14.0, 32.0),
        lineHeight: (lineHeight ?? this.lineHeight).clamp(1.3, 2.4),
        font: font ?? this.font,
        theme: theme ?? this.theme,
        pageTurn: pageTurn ?? this.pageTurn,
        margin: margin ?? this.margin,
        pageLayout: pageLayout ?? this.pageLayout,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'font': font.name,
        'theme': theme.name,
        'pageTurn': pageTurn.name,
        'margin': margin.name,
        'pageLayout': pageLayout.name,
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
      pageTurn: PageTurnMode.values.firstWhere(
        (value) => value.name == json['pageTurn'],
        orElse: () => PageTurnMode.cover,
      ),
      margin: ReaderMarginLevel.values.firstWhere(
        (value) => value.name == json['margin'],
        orElse: () => ReaderMarginLevel.standard,
      ),
      pageLayout: ReaderPageLayout.values.firstWhere(
        (value) => value.name == json['pageLayout'],
        orElse: () => ReaderPageLayout.auto,
      ),
    );
  }
}

enum ReaderFontId {
  wenkai('文楷', '温润手写', 'Modu WenKai', [
    'Modu Song',
    'serif',
  ]),
  song('宋体', '典雅出版', 'Modu Song', [
    'Modu WenKai',
    'serif',
  ]),
  hei('黑体', '现代清晰', 'Modu Hei', [
    'Modu WenKai',
    'sans-serif',
  ]);

  const ReaderFontId(this.label, this.subtitle, this.family, this.fallback);

  final String label;
  final String subtitle;
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

enum PageTurnMode {
  cover('叠翻', '纸页揭开'),
  slide('平移', '轻柔横滑'),
  fade('淡入', '静谧过渡'),
  none('无动画', '即刻翻页');

  const PageTurnMode(this.label, this.description);
  final String label;
  final String description;
}

enum ReaderMarginLevel {
  compact('宽幅'),
  standard('适中'),
  relaxed('舒展');

  const ReaderMarginLevel(this.label);
  final String label;
}

enum ReaderPageLayout {
  auto('自动', '窄单·宽双'),
  single('单页', '居中纸页'),
  doublePage('双页', '对开书卷');

  const ReaderPageLayout(this.label, this.description);
  final String label;
  final String description;
}
