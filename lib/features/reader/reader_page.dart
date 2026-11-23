import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/library_repository.dart';
import '../../data/models/book.dart';
import '../../data/models/reader_settings.dart';
import '../../data/settings_repository.dart';
import 'paginator.dart';
import 'reader_controller.dart';
import 'reader_sheets.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.book,
    required this.library,
    required this.settingsRepo,
  });

  final Book book;
  final LibraryRepository library;
  final SettingsRepository settingsRepo;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const Locale _locale = Locale('zh', 'CN');
  static const double _bandHeight = 34;
  static const double _verticalPadding = 22;

  ReaderController? _controller;
  Object? _loadError;
  bool _loading = true;

  late final AnimationController _turnAnimation;
  ReaderPageSnapshot? _outgoing;
  int _turnDirection = 1;
  bool _chromeVisible = false;
  bool _sheetOpen = false;
  bool _hintShown = false;
  String? _toast;
  Timer? _toastTimer;
  Timer? _wheelTimer;
  Timer? _saveTimer;
  Timer? _clockTimer;
  Timer? _hintTimer;
  ReaderPosition? _pendingPosition;
  DateTime _now = DateTime.now();
  double _dragDistance = 0;
  double _wheelAccumulator = 0;
  double? _scrub;
  ReaderThemeId _lastLightTheme = ReaderThemeId.paper;
  ReaderThemeId _lastDarkTheme = ReaderThemeId.night;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _turnAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 230),
    );
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _clockTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final text = await widget.library.loadBookText(widget.book);
      if (!mounted) return;
      if (text.chapters.isEmpty || text.content.isEmpty) {
        throw StateError('这本书没有可阅读的章节');
      }
      final controller = ReaderController(
        book: widget.book,
        content: text.content,
        chapters: text.chapters,
        settings: widget.settingsRepo.settings.reader,
        onProgress: _onProgress,
      );
      final initialPalette = ReaderPalette.of(controller.settings.theme);
      setState(() {
        _controller = controller;
        _loading = false;
        if (initialPalette.isDark) {
          _lastDarkTheme = controller.settings.theme;
        } else {
          _lastLightTheme = controller.settings.theme;
        }
      });
      widget.library.markOpened(widget.book);
      _hintTimer?.cancel();
      _hintTimer = Timer(const Duration(milliseconds: 900), () {
        if (!mounted || _hintShown || _sheetOpen || _chromeVisible) return;
        _hintShown = true;
        _showToast('轻点中间唤出菜单 · 左右翻页');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _saveNow();
      widget.library.flush();
      widget.settingsRepo.flush();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _clockTimer?.cancel();
    _hintTimer?.cancel();
    _toastTimer?.cancel();
    _wheelTimer?.cancel();
    _saveTimer?.cancel();
    _saveNow();
    widget.library.flush();
    _turnAnimation.dispose();
    _controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onProgress(ReaderPosition position) {
    _pendingPosition = position;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), _saveNow);
  }

  void _saveNow() {
    _saveTimer?.cancel();
    _saveTimer = null;
    final position = _pendingPosition;
    if (position == null) return;
    _pendingPosition = null;
    widget.library.saveProgress(
      widget.book.id,
      chapterIndex: position.chapterIndex,
      charOffset: position.charOffset,
      percent: position.percent,
      chapterTitle: position.chapterTitle,
    );
  }

  void _closeReader() {
    _saveNow();
    widget.library.flush();
    Navigator.of(context).pop();
  }

  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (_sheetOpen || _controller == null) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_chromeVisible) {
        setState(() => _chromeVisible = false);
      } else {
        _closeReader();
      }
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageUp) {
      _turn(-1);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.pageDown ||
        (key == LogicalKeyboardKey.space && !_chromeVisible)) {
      _turn(1);
      return true;
    }
    if (key == LogicalKeyboardKey.keyM) {
      _hideToast();
      setState(() => _chromeVisible = !_chromeVisible);
      return true;
    }
    if (key == LogicalKeyboardKey.keyT) {
      _openToc();
      return true;
    }
    if (key == LogicalKeyboardKey.keyS) {
      _openSettings();
      return true;
    }
    if (key == LogicalKeyboardKey.keyN) {
      _toggleNightTheme();
      return true;
    }
    return false;
  }

  void _turn(int direction) {
    final controller = _controller;
    if (controller == null || _sheetOpen || !controller.hasLayout) return;
    final before = controller.snapshot();
    final changed = controller.turnPage(direction);
    if (!changed) {
      _showToast(direction > 0 ? '已经是最后一页' : '已经是第一页');
      return;
    }
    _hideToast();
    _animatePageChange(before, direction);
  }

  void _animatePageChange(ReaderPageSnapshot? before, int direction) {
    if (before == null) {
      setState(() {});
      return;
    }
    _turnAnimation.stop();
    setState(() {
      _outgoing = before;
      _turnDirection = direction;
    });
    _turnAnimation.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() => _outgoing = null);
    });
  }

  void _runJump(VoidCallback action) {
    final controller = _controller;
    if (controller == null) return;
    final before = controller.snapshot();
    action();
    final after = controller.snapshot();
    if (before != null && after != null && !after.samePage(before)) {
      final direction = after.chapterIndex > before.chapterIndex ||
              (after.chapterIndex == before.chapterIndex &&
                  after.pageIndex > before.pageIndex)
          ? 1
          : -1;
      _animatePageChange(before, direction);
    } else {
      setState(() {});
    }
  }

  void _applySettings(ReaderSettings settings) {
    final controller = _controller;
    if (controller == null) return;
    final palette = ReaderPalette.of(settings.theme);
    setState(() {
      _outgoing = null;
      if (palette.isDark) {
        _lastDarkTheme = settings.theme;
      } else {
        _lastLightTheme = settings.theme;
      }
    });
    widget.settingsRepo.updateReader(settings);
    controller.applySettings(settings);
  }

  void _toggleNightTheme() {
    final controller = _controller;
    if (controller == null) return;
    final current = controller.settings;
    final palette = ReaderPalette.of(current.theme);
    final target = palette.isDark ? _lastLightTheme : _lastDarkTheme;
    _applySettings(current.copyWith(theme: target));
    _showToast(palette.isDark ? '已切换到日间模式' : '已切换到夜间模式');
  }

  Future<void> _openToc() async {
    final controller = _controller;
    if (controller == null) return;
    _hideToast();
    setState(() {
      _sheetOpen = true;
      _chromeVisible = false;
    });
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 760),
      barrierColor: Colors.black.withValues(alpha: 0.26),
      builder: (context) => ReaderTocSheet(
        controller: controller,
        palette: controller.palette,
      ),
    );
    if (!mounted) return;
    setState(() => _sheetOpen = false);
    if (selected != null && selected != controller.chapterIndex) {
      _runJump(() => controller.goToChapter(selected));
    }
  }

  Future<void> _openSettings() async {
    final controller = _controller;
    if (controller == null) return;
    _hideToast();
    setState(() {
      _sheetOpen = true;
      _chromeVisible = false;
    });
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 760),
      barrierColor: Colors.black.withValues(alpha: 0.16),
      builder: (context) => ReaderSettingsSheet(
        settings: controller.settings,
        onChanged: _applySettings,
      ),
    );
    if (!mounted) return;
    setState(() => _sheetOpen = false);
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toast = message);
    _toastTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() => _toast = null);
    });
  }

  void _hideToast() {
    _toastTimer?.cancel();
    if (_toast != null) setState(() => _toast = null);
  }

  void _onTapUp(TapUpDetails details) {
    final width = MediaQuery.sizeOf(context).width;
    final x = details.globalPosition.dx;
    if (x < width * 0.3) {
      _turn(-1);
    } else if (x > width * 0.7) {
      _turn(1);
    } else {
      _hideToast();
      setState(() => _chromeVisible = !_chromeVisible);
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final dy = event.scrollDelta.dy;
    if (dy.abs() < 0.01) return;
    if (_wheelAccumulator != 0 && dy.sign != _wheelAccumulator.sign) {
      _wheelAccumulator = 0;
    }
    _wheelAccumulator += dy;
    _wheelTimer?.cancel();
    _wheelTimer = Timer(const Duration(milliseconds: 240), () {
      _wheelAccumulator = 0;
    });
    if (_wheelAccumulator.abs() >= 42) {
      final direction = _wheelAccumulator > 0 ? 1 : -1;
      _wheelAccumulator = 0;
      _turn(direction);
    }
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final distance = _dragDistance;
    _dragDistance = 0;
    if (distance <= -36 || velocity <= -320) {
      _turn(1);
    } else if (distance >= 36 || velocity >= 320) {
      _turn(-1);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildLoading();
    final controller = _controller;
    if (controller == null) return _buildError();

    return MediaQuery.withNoTextScaling(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final palette = controller.palette;
          return PopScope(
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) _saveNow();
            },
            child: Scaffold(
              backgroundColor: palette.bottom,
              body: Stack(
                children: [
                  Positioned.fill(child: _ReaderBackground(palette: palette)),
                  Positioned.fill(
                    child: SafeArea(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final metrics = _metricsFor(constraints);
                          if (controller.layoutSize != metrics.textSize) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) controller.ensureLayout(metrics.textSize);
                            });
                          }
                          return _buildBody(controller, palette, metrics);
                        },
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: SafeArea(
                      child: Stack(
                        children: [
                          _buildTopChrome(controller, palette),
                          _buildBottomChrome(controller, palette),
                        ],
                      ),
                    ),
                  ),
                  if (_toast != null) _buildToast(palette),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  _ReaderMetrics _metricsFor(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final side = width < 640 ? 24.0 : 56.0;
    final textWidth = math.min(760.0, math.max(160.0, width - side * 2));
    final textHeight = math.max(
      120.0,
      height - _bandHeight * 2 - _verticalPadding * 2,
    );
    return _ReaderMetrics(
      textWidth: textWidth,
      textHeight: textHeight,
      textSize: Size(textWidth, textHeight),
    );
  }

  Widget _buildBody(
    ReaderController controller,
    ReaderPalette palette,
    _ReaderMetrics metrics,
  ) {
    final page = _buildPageArea(controller, palette, metrics);
    return Column(
      children: [
        SizedBox(
          height: _bandHeight,
          child: _BandRow(
            width: metrics.textWidth,
            left: widget.book.title,
            right: Fmt.clock(_now),
            palette: palette,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: _verticalPadding),
            child: Listener(
              onPointerSignal: _onPointerSignal,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _onTapUp,
                onHorizontalDragStart: (_) => _dragDistance = 0,
                onHorizontalDragUpdate: (details) {
                  _dragDistance += details.delta.dx;
                },
                onHorizontalDragEnd: _onDragEnd,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: metrics.textWidth,
                    height: metrics.textHeight,
                    child: page,
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: _bandHeight,
          child: _BandRow(
            width: metrics.textWidth,
            left: controller.chapterHeaderTitle,
            right: controller.pageIndicator,
            palette: palette,
          ),
        ),
      ],
    );
  }

  Widget _buildPageArea(
    ReaderController controller,
    ReaderPalette palette,
    _ReaderMetrics metrics,
  ) {
    final currentSnapshot = controller.snapshot();
    if (currentSnapshot == null) {
      return Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: palette.accent.withValues(alpha: 0.5),
          ),
        ),
      );
    }
    final currentPage = _buildPage(currentSnapshot, controller, palette, metrics);
    final outgoing = _outgoing;
    if (outgoing == null) return currentPage;

    return AnimatedBuilder(
      animation: _turnAnimation,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_turnAnimation.value);
        final direction = _turnDirection;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: (1 - t).clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(-16.0 * direction * t, 0),
                    child: _buildPage(outgoing, controller, palette, metrics),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(22.0 * direction * (1 - t), 0),
                  child: currentPage,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPage(
    ReaderPageSnapshot snapshot,
    ReaderController controller,
    ReaderPalette palette,
    _ReaderMetrics metrics,
  ) {
    return SizedBox(
      width: metrics.textWidth,
      height: metrics.textHeight,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (snapshot.isFirstPage) ...[
                    Text(
                      snapshot.chapterTitle,
                      style: controller.headingStyle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      locale: _locale,
                    ),
                    const SizedBox(height: Paginator.titleMetaGap),
                    Text(
                      snapshot.meta,
                      style: controller.metaStyle,
                      locale: _locale,
                    ),
                    const SizedBox(height: Paginator.defaultHeadingGap),
                  ],
                  Text(
                    snapshot.body,
                    style: controller.bodyStyle,
                    locale: _locale,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopChrome(ReaderController controller, ReaderPalette palette) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedSlide(
        offset: _chromeVisible ? Offset.zero : const Offset(0, -1.1),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _chromeVisible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: IgnorePointer(
            ignoring: !_chromeVisible,
            child: Container(
              decoration: BoxDecoration(
                color: palette.chrome,
                border: Border(
                  bottom: BorderSide(color: palette.divider),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
              child: Center(
                child: SizedBox(
                  width: math.min(820, MediaQuery.sizeOf(context).width - 16),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _closeReader,
                        tooltip: '返回书架',
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          color: palette.text,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.book.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: palette.text,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              controller.chapterHeaderTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: palette.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _openToc,
                        tooltip: '目录',
                        icon: Icon(
                          Icons.format_list_bulleted_rounded,
                          color: palette.text,
                          size: 21,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomChrome(ReaderController controller, ReaderPalette palette) {
    final isDark = palette.isDark;
    final displayPercent = _scrub ?? controller.percent;
    var displayChapter = controller.chapterIndex;
    if (_scrub != null && controller.content.isNotEmpty) {
      final offset = (_scrub! * controller.content.length)
          .floor()
          .clamp(0, math.max(0, controller.content.length - 1))
          .toInt();
      displayChapter = controller.chapterIndexForOffset(offset);
    }
    final contentWidth =
        math.min(760.0, MediaQuery.sizeOf(context).width - 32);

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: AnimatedSlide(
        offset: _chromeVisible ? Offset.zero : const Offset(0, 1.1),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _chromeVisible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: IgnorePointer(
            ignoring: !_chromeVisible,
            child: Container(
              decoration: BoxDecoration(
                color: palette.chrome,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                border: Border(top: BorderSide(color: palette.divider)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 24,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Center(
                child: SizedBox(
                  width: contentWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: palette.muted.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            '第 ${displayChapter + 1} / ${controller.chapters.length} 章',
                            style: TextStyle(fontSize: 11, color: palette.muted),
                          ),
                          const Spacer(),
                          Text(
                            _scrub != null
                                ? '跳转 ${Fmt.percent(displayPercent)}'
                                : '已读 ${Fmt.percent(displayPercent)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: palette.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => _runJump(controller.previousChapter),
                            tooltip: '上一章',
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              Icons.skip_previous_rounded,
                              size: 19,
                              color: palette.muted,
                            ),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: palette.accent,
                                inactiveTrackColor:
                                    palette.accent.withValues(alpha: 0.16),
                                thumbColor: palette.accent,
                                overlayColor:
                                    palette.accent.withValues(alpha: 0.12),
                                trackHeight: 2.2,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 14,
                                ),
                              ),
                              child: Slider(
                                value: displayPercent.clamp(0.0, 1.0),
                                onChangeStart: (value) =>
                                    setState(() => _scrub = value),
                                onChanged: (value) =>
                                    setState(() => _scrub = value),
                                onChangeEnd: (value) {
                                  setState(() => _scrub = null);
                                  _runJump(
                                    () => controller.jumpToPercent(value),
                                  );
                                },
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _runJump(controller.nextChapter),
                            tooltip: '下一章',
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              Icons.skip_next_rounded,
                              size: 19,
                              color: palette.muted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          _ChromeAction(
                            icon: Icons.menu_book_rounded,
                            label: '目录',
                            palette: palette,
                            onTap: _openToc,
                          ),
                          _ChromeAction(
                            icon: isDark
                                ? Icons.light_mode_rounded
                                : Icons.dark_mode_rounded,
                            label: isDark ? '日间' : '夜间',
                            palette: palette,
                            onTap: _toggleNightTheme,
                          ),
                          _ChromeAction(
                            icon: Icons.text_fields_rounded,
                            label: '排版',
                            palette: palette,
                            onTap: _openSettings,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToast(ReaderPalette palette) {
    final bottom = MediaQuery.paddingOf(context).bottom + 48;
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            opacity: _toast == null ? 0 : 1,
            duration: const Duration(milliseconds: 160),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: palette.text.withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _toast ?? '',
                style: TextStyle(
                  fontSize: 12,
                  color: palette.chrome,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    final palette = ReaderPalette.of(widget.settingsRepo.settings.reader.theme);
    return Scaffold(
      backgroundColor: palette.bottom,
      body: Stack(
        children: [
          Positioned.fill(child: _ReaderBackground(palette: palette)),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.book.title,
                  style: ReaderTypography.heading(
                    widget.settingsRepo.settings.reader,
                    palette,
                  ).copyWith(fontSize: 24),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.accent,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '正在打开',
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.muted,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    final palette = ReaderPalette.paper;
    final message = _loadError?.toString() ?? '未知错误';
    return Scaffold(
      backgroundColor: palette.bottom,
      body: Stack(
        children: [
          Positioned.fill(child: _ReaderBackground(palette: palette)),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.menu_book_outlined,
                      size: 52,
                      color: palette.muted,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '无法打开这本书',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message.length > 160
                          ? message.substring(0, 160)
                          : message,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: palette.muted),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.tonal(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('返回书架'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReaderMetrics {
  const _ReaderMetrics({
    required this.textWidth,
    required this.textHeight,
    required this.textSize,
  });

  final double textWidth;
  final double textHeight;
  final Size textSize;
}

class _BandRow extends StatelessWidget {
  const _BandRow({
    required this.width,
    required this.left,
    required this.right,
    required this.palette,
  });

  final double width;
  final String left;
  final String right;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  left,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: palette.muted,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                right,
                style: TextStyle(
                  fontSize: 11,
                  color: palette.muted,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChromeAction extends StatelessWidget {
  const _ChromeAction({
    required this.icon,
    required this.label,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final ReaderPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        onTap: onTap,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 36,
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 19, color: palette.accent),
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  style: TextStyle(fontSize: 10.5, color: palette.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderBackground extends StatelessWidget {
  const _ReaderBackground({required this.palette});

  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.top, palette.bottom],
        ),
      ),
    );
  }
}
