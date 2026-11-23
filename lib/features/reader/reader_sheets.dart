import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/reader_settings.dart';
import 'reader_controller.dart';

const double _sheetRadius = 22;

class ReaderTocSheet extends StatefulWidget {
  const ReaderTocSheet({
    super.key,
    required this.controller,
    required this.palette,
  });

  final ReaderController controller;
  final ReaderPalette palette;

  @override
  State<ReaderTocSheet> createState() => _ReaderTocSheetState();
}

class _ReaderTocSheetState extends State<ReaderTocSheet> {
  static const double _itemExtent = 56;

  late final ScrollController _scrollController;
  late final TextEditingController _searchController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: ((widget.controller.chapterIndex - 4) * _itemExtent)
          .clamp(0.0, double.infinity),
    );
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<int> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return List<int>.generate(widget.controller.chapters.length, (i) => i);
    }
    final result = <int>[];
    final chapters = widget.controller.chapters;
    for (var i = 0; i < chapters.length; i++) {
      if (chapters[i].title.toLowerCase().contains(query)) result.add(i);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final controller = widget.controller;
    final filtered = _filtered;
    final height = MediaQuery.sizeOf(context).height * 0.82;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: palette.chrome,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(_sheetRadius)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: height,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.muted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Text(
                      '目录',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '共 ${controller.chapters.length} 章',
                      style: TextStyle(fontSize: 12, color: palette.muted),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: palette.muted),
                      tooltip: '关闭',
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(fontSize: 14, color: palette.text),
                  cursorColor: palette.accent,
                  onChanged: (value) {
                    setState(() => _query = value);
                    if (_scrollController.hasClients) {
                      _scrollController.jumpTo(0);
                    }
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '搜索章节',
                    hintStyle: TextStyle(fontSize: 13.5, color: palette.muted),
                    prefixIcon: Icon(Icons.search_rounded, size: 19, color: palette.muted),
                    filled: true,
                    fillColor: palette.divider.withValues(alpha: 0.22),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: palette.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: palette.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: palette.accent, width: 1.3),
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: palette.divider),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          '没有找到相关章节',
                          style: TextStyle(fontSize: 13.5, color: palette.muted),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemExtent: _itemExtent,
                        itemCount: filtered.length,
                        padding: const EdgeInsets.only(bottom: 12),
                        itemBuilder: (context, position) {
                          final index = filtered[position];
                          return _TocItem(
                            controller: controller,
                            palette: palette,
                            chapterIndex: index,
                            onTap: () => Navigator.of(context).pop(index),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TocItem extends StatelessWidget {
  const _TocItem({
    required this.controller,
    required this.palette,
    required this.chapterIndex,
    required this.onTap,
  });

  final ReaderController controller;
  final ReaderPalette palette;
  final int chapterIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chapter = controller.chapters[chapterIndex];
    final current = chapterIndex == controller.chapterIndex;
    return Semantics(
      button: true,
      selected: current,
      label: '${chapter.title}，${_shortChars(chapter.length)}'
          '${current ? '，当前章节' : ''}',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: current ? palette.accent.withValues(alpha: 0.09) : null,
            border: Border(
              bottom: BorderSide(color: palette.divider.withValues(alpha: 0.5)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 22,
                decoration: BoxDecoration(
                  color: current ? palette.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  chapter.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                    color: current ? palette.accent : palette.text,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _shortChars(chapter.length),
                style: TextStyle(fontSize: 11, color: palette.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _shortChars(int chars) {
    if (chars >= 10000) {
      return '${(chars / 10000).toStringAsFixed(1)} 万字';
    }
    if (chars >= 1000) {
      return '${(chars / 1000).toStringAsFixed(1)} 千字';
    }
    return '$chars 字';
  }
}

class ReaderSettingsSheet extends StatefulWidget {
  const ReaderSettingsSheet({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final ReaderSettings settings;
  final ValueChanged<ReaderSettings> onChanged;

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  late ReaderSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  void _update(ReaderSettings settings) {
    setState(() => _settings = settings);
    widget.onChanged(settings);
  }

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(_settings.theme);
    final isDesktop = switch (defaultTargetPlatform) {
      TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux => true,
      _ => false,
    };

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: palette.chrome,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(_sheetRadius)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.muted.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      '阅读设置',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(foregroundColor: palette.accent),
                      child: const Text('完成'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _sectionLabel('主题', palette),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final option in ReaderPalette.all)
                      _ThemeSwatch(
                        palette: option,
                        selected: option.id == _settings.theme,
                        onTap: () => _update(_settings.copyWith(theme: option.id)),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                _sectionLabel('字体', palette),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final font in ReaderFontId.values)
                      _FontChip(
                        font: font,
                        selected: font == _settings.font,
                        palette: palette,
                        onTap: () => _update(_settings.copyWith(font: font)),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                _SliderRow(
                  label: '字号',
                  valueLabel: _settings.fontSize.toStringAsFixed(0),
                  palette: palette,
                  value: _settings.fontSize,
                  min: 14,
                  max: 32,
                  divisions: 18,
                  onChanged: (value) => _update(_settings.copyWith(fontSize: value)),
                ),
                const SizedBox(height: 8),
                _SliderRow(
                  label: '行距',
                  valueLabel: _settings.lineHeight.toStringAsFixed(1),
                  palette: palette,
                  value: _settings.lineHeight,
                  min: 1.4,
                  max: 2.2,
                  divisions: 8,
                  onChanged: (value) => _update(_settings.copyWith(lineHeight: value)),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  decoration: BoxDecoration(
                    color: palette.top,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.divider),
                  ),
                  child: Text(
                    '夜色渐深，风从窗缝里钻进来，书页轻轻翻动。',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ReaderTypography.body(_settings, palette),
                  ),
                ),
                if (isDesktop) ...[
                  const SizedBox(height: 16),
                  Text(
                    '← → 翻页  ·  空格 下一页  ·  M 菜单\n'
                    'T 目录  ·  S 排版  ·  N 夜间  ·  Esc 返回',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.7,
                      color: palette.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, ReaderPalette palette) => Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: palette.muted,
          letterSpacing: 1,
        ),
      );
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final ReaderPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${palette.label}主题',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [palette.top, palette.bottom],
                  ),
                  border: Border.all(
                    color: selected
                        ? palette.accent
                        : palette.muted.withValues(alpha: 0.25),
                    width: selected ? 2.4 : 1,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check_rounded, size: 19, color: palette.accent)
                    : null,
              ),
              const SizedBox(height: 6),
              Text(
                palette.label,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? palette.accent : palette.muted,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FontChip extends StatelessWidget {
  const _FontChip({
    required this.font,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final ReaderFontId font;
  final bool selected;
  final ReaderPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${font.label}字体',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? palette.accent.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? palette.accent : palette.divider,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Text(
            font.label,
            style: TextStyle(
              fontFamily: font.family,
              fontFamilyFallback: font.fallback,
              fontSize: 15,
              color: selected ? palette.accent : palette.text,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueLabel,
    required this.palette,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final ReaderPalette palette;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(fontSize: 13, color: palette.muted)),
            const Spacer(),
            Text(
              valueLabel,
              style: TextStyle(
                fontSize: 12,
                color: palette.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: palette.accent,
            inactiveTrackColor: palette.accent.withValues(alpha: 0.14),
            thumbColor: palette.accent,
            overlayColor: palette.accent.withValues(alpha: 0.12),
            trackHeight: 2.4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
