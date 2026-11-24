import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/brand_logo.dart';
import '../../core/formatters.dart';
import '../../core/responsive.dart';
import '../../core/seal_badges.dart';
import '../../core/theme.dart';
import '../../data/library_repository.dart';
import '../../data/models/book.dart';
import '../../data/models/reader_settings.dart';
import '../../data/models/reading_stats.dart';
import '../../data/settings_repository.dart';
import '../../data/stats_repository.dart';
import 'paginator.dart';
import 'reader_controller.dart';
import 'reader_sheets.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.book,
    required this.library,
    required this.settingsRepo,
    this.statsRepo,
  });

  final Book book;
  final LibraryRepository library;
  final SettingsRepository settingsRepo;
  final StatsRepository? statsRepo;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const Locale _locale = Locale('zh', 'CN');

  ReaderController? _controller;
  Object? _loadError;
  bool _loading = true;

  late final AnimationController _turnAnimation;
  late final AnimationController _dragReboundAnimation;
  ReaderSpreadSnapshot? _outgoing;
  int _turnDirection = 1;
  double _turnStartProgress = 0;

  double _dragOffset = 0;
  double _reboundStartOffset = 0;
  bool _isDragging = false;

  bool _chromeVisible = false;
  bool _sheetOpen = false;
  bool _hintShown = false;
  bool _appResumed = true;
  String? _toast;
  StampId? _unlockedBanner;
  Timer? _toastTimer;
  Timer? _stampBannerTimer;
  Timer? _wheelTimer;
  Timer? _saveTimer;
  Timer? _clockTimer;
  Timer? _sessionTimer;
  Timer? _hintTimer;
  ReaderPosition? _pendingPosition;
  ReaderPosition? _undoJumpPosition;
  DateTime _now = DateTime.now();
  double _wheelAccumulator = 0;
  double? _scrub;
  ReaderThemeId _lastLightTheme = ReaderThemeId.paper;
  ReaderThemeId _lastDarkTheme = ReaderThemeId.night;
  double _lastSpreadWidth = 680;
  bool _lastIsSpread = false;
  int _sessionSeconds = 0;
  int _lastMilestonePercent = 0;
  List<BookBookmark> _bookmarks = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _turnAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _dragReboundAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 190),
    )..addListener(() {
        if (!mounted) return;
        final t = Curves.easeOutCubic.transform(_dragReboundAnimation.value);
        setState(() {
          _dragOffset = _reboundStartOffset * (1.0 - t);
        });
      });
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _clockTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _sessionTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted || !_appResumed || _loading || _controller == null) return;
      _sessionSeconds += 10;
      final statsRepo = widget.statsRepo;
      if (statsRepo != null) {
        final newly = statsRepo.recordReadingSeconds(
          10,
          sessionSeconds: _sessionSeconds,
          isNightTheme: _controller!.palette.isDark,
        );
        _announceStamps(newly);
      }
      if (_chromeVisible) setState(() {});
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.library.loadBookText(widget.book),
        widget.library.loadBookmarks(widget.book.id),
      ]);
      final text = results[0] as BookText;
      final bookmarks = results[1] as List<BookBookmark>;
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
        _bookmarks = bookmarks;
        _loading = false;
        _lastMilestonePercent = ((widget.book.progress.percent * 100) ~/ 25) * 25;
        if (initialPalette.isDark) {
          _lastDarkTheme = controller.settings.theme;
        } else {
          _lastLightTheme = controller.settings.theme;
        }
      });
      widget.library.markOpened(widget.book);
      final openedStamps = widget.statsRepo?.recordBookOpened() ?? const [];
      _announceStamps(openedStamps);
      _hintTimer?.cancel();
      _hintTimer = Timer(const Duration(milliseconds: 900), () {
        if (!mounted || _hintShown || _sheetOpen || _chromeVisible) return;
        _hintShown = true;
        _showToast('轻点中间唤出菜单 · 左右点击或滑动翻页');
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
    _appResumed = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _saveNow();
      widget.library.flush();
      widget.settingsRepo.flush();
      widget.statsRepo?.flush();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _clockTimer?.cancel();
    _sessionTimer?.cancel();
    _hintTimer?.cancel();
    _toastTimer?.cancel();
    _stampBannerTimer?.cancel();
    _wheelTimer?.cancel();
    _saveTimer?.cancel();
    _saveNow();
    widget.library.flush();
    widget.statsRepo?.flush();
    _turnAnimation.dispose();
    _dragReboundAnimation.dispose();
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
    widget.statsRepo?.flush();
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
    if (key == LogicalKeyboardKey.keyB) {
      _toggleCurrentPageBookmark();
      return true;
    }
    if (key == LogicalKeyboardKey.keyH || key == LogicalKeyboardKey.slash) {
      _showShortcutsDialog();
      return true;
    }
    return false;
  }

  void _announceStamps(List<StampId> newlyUnlocked) {
    if (!mounted || newlyUnlocked.isEmpty) return;
    HapticFeedback.mediumImpact();
    _stampBannerTimer?.cancel();
    setState(() => _unlockedBanner = newlyUnlocked.last);
    _stampBannerTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _unlockedBanner = null);
    });
  }

  void _turn(int direction, {double startProgress = 0}) {
    final controller = _controller;
    if (controller == null || _sheetOpen || !controller.hasLayout) return;
    controller.prewarmWhenIdle();
    final spread = _lastIsSpread;
    final before = controller.spreadSnapshot(spread: spread);
    final changed = controller.turnPage(direction, spread: spread);
    if (!changed) {
      if (direction > 0) {
        _onBookCompleted();
      } else {
        _showToast('已经是第一页');
      }
      return;
    }
    _hideToast();
    _animatePageChange(before, direction, startProgress: startProgress);

    final statsRepo = widget.statsRepo;
    final after = controller.spreadSnapshot(spread: spread);
    if (statsRepo != null && after != null) {
      final pageStamps = statsRepo.recordPageTurn(
        charsOnPage: direction > 0 ? (before?.totalBodyChars ?? 0) : 0,
        isNightTheme: controller.palette.isDark,
        pageCount: before?.pageCount ?? 1,
      );
      _announceStamps(pageStamps);

      if (direction > 0 && before != null && after.chapterIndex > before.chapterIndex) {
        final chapStamps = statsRepo.recordChapterFinished();
        _announceStamps(chapStamps);
        if (chapStamps.isEmpty && pageStamps.isEmpty) {
          final pct = (controller.percentFor(spread: spread) * 100).floor();
          final milestone = (pct ~/ 25) * 25;
          if (milestone >= 25 && milestone < 100 && milestone > _lastMilestonePercent) {
            _lastMilestonePercent = milestone;
            _showToast('已读完《${before.left.chapterTitle}》 · 进度突破 $milestone%');
          } else {
            _showToast('读完《${before.left.chapterTitle}》');
          }
        }
      }
    }
  }

  Future<void> _onBookCompleted() async {
    final controller = _controller;
    if (controller == null || _sheetOpen) return;
    HapticFeedback.mediumImpact();
    final newly = widget.statsRepo?.recordBookFinished(widget.book.id) ?? const [];
    _announceStamps(newly);
    setState(() {
      _sheetOpen = true;
      _chromeVisible = false;
    });
    final finishedCount =
        math.max(1, widget.statsRepo?.stats.finishedBookIds.length ?? 1);
    final action = await showDialog<BookCompletionAction>(
      context: context,
      builder: (context) => BookCompletionDialog(
        book: widget.book,
        sessionSeconds: _sessionSeconds,
        finishedBooksCount: finishedCount,
        palette: controller.palette,
      ),
    );
    if (!mounted) return;
    setState(() => _sheetOpen = false);
    if (action == BookCompletionAction.backToShelf) {
      _closeReader();
    } else if (action == BookCompletionAction.restartBook) {
      _runJump(() => controller.goToChapter(0), recordUndo: false);
    }
  }

  BookBookmark? _bookmarkForCurrentPage(ReaderController controller) {
    final range = controller.visibleRangeFor(spread: _lastIsSpread);
    if (range == null) return null;
    for (final bm in _bookmarks) {
      if (bm.charOffset >= range.start && bm.charOffset < range.end) {
        return bm;
      }
    }
    return null;
  }

  Future<void> _toggleCurrentPageBookmark() async {
    final controller = _controller;
    if (controller == null) return;
    final range = controller.visibleRangeFor(spread: _lastIsSpread);
    if (range == null) return;
    HapticFeedback.selectionClick();
    final existing = _bookmarkForCurrentPage(controller);
    final updated = List<BookBookmark>.from(_bookmarks);
    if (existing != null) {
      updated.removeWhere((b) => b.id == existing.id);
      _showToast('已取下书签');
    } else {
      final cleanBody = range.excerptSource
          .replaceAll('\u3000', '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final excerpt =
          cleanBody.length > 42 ? '${cleanBody.substring(0, 42)}…' : cleanBody;
      updated.add(
        BookBookmark(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
          chapterIndex: range.chapterIndex,
          charOffset: range.start,
          chapterTitle: range.chapterTitle,
          excerpt: excerpt,
          createdAt: DateTime.now(),
        ),
      );
      updated.sort((a, b) => a.charOffset.compareTo(b.charOffset));
      _showToast('已夹存朱砂书签');
    }
    setState(() => _bookmarks = updated);
    await widget.library.saveBookmarks(widget.book.id, updated);
  }

  Future<void> _removeBookmarkById(String bookmarkId) async {
    final updated = _bookmarks.where((b) => b.id != bookmarkId).toList();
    setState(() => _bookmarks = updated);
    await widget.library.saveBookmarks(widget.book.id, updated);
  }

  void _animatePageChange(
    ReaderSpreadSnapshot? before,
    int direction, {
    double startProgress = 0,
  }) {
    final mode = _controller?.settings.pageTurn ?? PageTurnMode.cover;
    if (before == null || mode == PageTurnMode.none) {
      setState(() {
        _outgoing = null;
        _dragOffset = 0;
      });
      return;
    }
    _dragReboundAnimation.stop();
    _turnAnimation.stop();
    final clampedStart = startProgress.clamp(0.0, 0.92);
    setState(() {
      _outgoing = before;
      _turnDirection = direction;
      _turnStartProgress = clampedStart;
      _dragOffset = 0;
    });
    _turnAnimation.forward(from: clampedStart).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _outgoing = null;
        _turnStartProgress = 0;
      });
    });
  }

  void _runJump(VoidCallback action, {bool recordUndo = true}) {
    final controller = _controller;
    if (controller == null) return;
    controller.prewarmWhenIdle();
    final before = controller.spreadSnapshot(spread: _lastIsSpread);
    final prevPosition = controller.currentPosition();
    action();
    final after = controller.spreadSnapshot(spread: _lastIsSpread);
    if (before != null && after != null && !after.sameSpread(before)) {
      if (recordUndo &&
          (after.chapterIndex != before.chapterIndex ||
              (after.left.pageIndex - before.left.pageIndex).abs() > 1)) {
        _undoJumpPosition = prevPosition;
      }
      final direction = after.chapterIndex > before.chapterIndex ||
              (after.chapterIndex == before.chapterIndex &&
                  after.left.pageIndex > before.left.pageIndex)
          ? 1
          : -1;
      _animatePageChange(before, direction);
    } else {
      setState(() {});
    }
  }

  void _undoLastJump() {
    final controller = _controller;
    final undo = _undoJumpPosition;
    if (controller == null || undo == null) return;
    setState(() => _undoJumpPosition = null);
    _runJump(
      () => controller.jumpToGlobalOffset(undo.charOffset),
      recordUndo: false,
    );
    _showToast('已回到跳转前位置');
  }

  void _applySettings(ReaderSettings settings) {
    final controller = _controller;
    if (controller == null) return;
    final palette = ReaderPalette.of(settings.theme);
    setState(() {
      _outgoing = null;
      _dragOffset = 0;
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
    final selected = await showAdaptivePanel<ReaderTocSelection>(
      context: context,
      placement: AdaptivePanelPlacement.bottomOrEndDrawer,
      drawerWidth: 420,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (panelContext) => ReaderTocSheet(
        controller: controller,
        palette: controller.palette,
        bookmarks: _bookmarks,
        onRemoveBookmark: _removeBookmarkById,
        asSideDrawer: MediaQuery.sizeOf(panelContext).width >= 700,
      ),
    );
    if (!mounted) return;
    setState(() => _sheetOpen = false);
    if (selected != null) {
      if (selected.charOffset != null) {
        _runJump(() => controller.jumpToGlobalOffset(selected.charOffset!));
      } else if (selected.chapterIndex != controller.chapterIndex) {
        _runJump(() => controller.goToChapter(selected.chapterIndex));
      }
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
    await showAdaptivePanel<void>(
      context: context,
      placement: AdaptivePanelPlacement.bottomOrCenteredDialog,
      maxDialogWidth: 660,
      maxDialogHeight: 700,
      barrierColor: Colors.black.withValues(alpha: 0.20),
      builder: (panelContext) => ReaderSettingsSheet(
        settings: controller.settings,
        onChanged: _applySettings,
        asDialog: MediaQuery.sizeOf(panelContext).width >= 600,
      ),
    );
    if (!mounted) return;
    setState(() => _sheetOpen = false);
  }

  Future<void> _showShortcutsDialog() async {
    final controller = _controller;
    if (controller == null) return;
    final palette = controller.palette;
    setState(() => _sheetOpen = true);
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: palette.chrome,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: palette.divider),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '快捷键与手势',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 16),
                _ShortcutLine(
                  keys: const ['←', 'PageUp'],
                  desc: '上一页',
                  palette: palette,
                ),
                _ShortcutLine(
                  keys: const ['→', '空格', 'PageDown'],
                  desc: '下一页',
                  palette: palette,
                ),
                _ShortcutLine(
                  keys: const ['M'],
                  desc: '呼出 / 收起阅读菜单',
                  palette: palette,
                ),
                _ShortcutLine(
                  keys: const ['T'],
                  desc: '打开章节目录与书签',
                  palette: palette,
                ),
                _ShortcutLine(
                  keys: const ['B'],
                  desc: '夹存 / 取下本页书签',
                  palette: palette,
                ),
                _ShortcutLine(
                  keys: const ['S'],
                  desc: '打开排版工坊',
                  palette: palette,
                ),
                _ShortcutLine(
                  keys: const ['N'],
                  desc: '切换日间 / 夜间模式',
                  palette: palette,
                ),
                _ShortcutLine(
                  keys: const ['Esc'],
                  desc: '收起菜单或返回书架',
                  palette: palette,
                ),
                const SizedBox(height: 12),
                Text(
                  '触屏或触控板支持左右跟手滑动翻页；轻点右上角书签丝带可随时夹存本页。',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: palette.muted,
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: palette.accent),
                    child: const Text('知道了'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() => _sheetOpen = false);
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toast = message);
    _toastTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      setState(() => _toast = null);
    });
  }

  void _hideToast() {
    _toastTimer?.cancel();
    if (_toast != null) setState(() => _toast = null);
  }

  void _onTapUp(TapUpDetails details) {
    if (_chromeVisible) {
      setState(() => _chromeVisible = false);
      return;
    }
    final width = MediaQuery.sizeOf(context).width;
    final x = details.globalPosition.dx;
    if (x < width * 0.3) {
      _turn(-1);
    } else if (x > width * 0.7) {
      _turn(1);
    } else {
      _hideToast();
      setState(() => _chromeVisible = true);
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

  void _onDragStart(DragStartDetails details) {
    final controller = _controller;
    if (controller == null || !controller.hasLayout || _sheetOpen) return;
    _dragReboundAnimation.stop();
    _turnAnimation.stop();
    controller.prewarmWhenIdle();
    setState(() {
      _isDragging = true;
      _outgoing = null;
      _dragOffset = 0;
      if (_chromeVisible) _chromeVisible = false;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final controller = _controller;
    if (!_isDragging || controller == null || !controller.hasLayout) return;
    final nextOffset = _dragOffset + details.delta.dx;
    final atEdge = (nextOffset > 0 &&
            controller.isFirstPageOfBookFor(spread: _lastIsSpread)) ||
        (nextOffset < 0 &&
            controller.isLastPageOfBookFor(spread: _lastIsSpread));
    setState(() {
      _dragOffset = atEdge
          ? _dragOffset + details.delta.dx * 0.24
          : nextOffset.clamp(-_lastSpreadWidth, _lastSpreadWidth);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final controller = _controller;
    if (!_isDragging || controller == null) {
      _isDragging = false;
      return;
    }
    _isDragging = false;
    final velocity = details.primaryVelocity ?? 0;
    final offset = _dragOffset;
    final threshold = math.min(54.0, _lastSpreadWidth * 0.14);

    if (offset <= -threshold || (offset <= 0 && velocity <= -320)) {
      if (controller.isLastPageOfBookFor(spread: _lastIsSpread)) {
        _reboundDrag();
        _onBookCompleted();
      } else {
        final startProgress =
            (offset.abs() / math.max(1.0, _lastSpreadWidth)).clamp(0.0, 0.90);
        _turn(1, startProgress: startProgress);
      }
      return;
    }
    if (offset >= threshold || (offset >= 0 && velocity >= 320)) {
      if (controller.isFirstPageOfBookFor(spread: _lastIsSpread)) {
        _reboundDrag();
        _showToast('已经是第一页');
      } else {
        final startProgress =
            (offset.abs() / math.max(1.0, _lastSpreadWidth)).clamp(0.0, 0.90);
        _turn(-1, startProgress: startProgress);
      }
      return;
    }
    _reboundDrag();
  }

  void _reboundDrag() {
    if (_dragOffset.abs() < 0.5) {
      setState(() => _dragOffset = 0);
      return;
    }
    _reboundStartOffset = _dragOffset;
    _dragReboundAnimation.forward(from: 0);
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
          final bookmarked = _bookmarkForCurrentPage(controller) != null;
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
                          final metrics =
                              _metricsFor(constraints, controller.settings);
                          _lastSpreadWidth = metrics.spreadWidth;
                          _lastIsSpread = metrics.isSpread;
                          if (controller.layoutSize != metrics.columnSize) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                controller.ensureLayout(metrics.columnSize);
                              }
                            });
                          }
                          final ribbonRight = math.max(
                            4.0,
                            (constraints.maxWidth - metrics.spreadWidth) / 2 -
                                4,
                          );
                          return Stack(
                            children: [
                              _buildBody(controller, palette, metrics),
                              Positioned(
                                top: 0,
                                right: ribbonRight,
                                child: BookmarkRibbonMarker(
                                  bookmarked: bookmarked,
                                  accentColor: const Color(0xFFC4462E),
                                  onTap: _toggleCurrentPageBookmark,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  // Subtle edge-to-edge thin book progress indicator.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: SafeArea(
                        top: false,
                        child: SizedBox(
                          height: 2,
                          child: LinearProgressIndicator(
                            value: controller
                                .percentFor(spread: _lastIsSpread)
                                .clamp(0.0, 1.0),
                            backgroundColor:
                                palette.divider.withValues(alpha: 0.25),
                            color: palette.accent.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: SafeArea(
                      child: Stack(
                        children: [
                          _buildTopChrome(
                            controller,
                            palette,
                            bookmarked: bookmarked,
                          ),
                          _buildBottomChrome(controller, palette),
                        ],
                      ),
                    ),
                  ),
                  if (_unlockedBanner != null)
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 16,
                      left: 20,
                      right: 20,
                      child: IgnorePointer(
                        child: Center(
                          child: StampUnlockBanner(
                            stamp: _unlockedBanner!,
                            palette: palette,
                          ),
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

  _ReaderMetrics _metricsFor(
    BoxConstraints constraints,
    ReaderSettings settings,
  ) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final bandHeight = width < 600 ? 34.0 : 38.0;
    final verticalPad = height < 520 ? 10.0 : 20.0;
    final canFitSpread = width >= 680 && height >= 360;
    final isSpread = switch (settings.pageLayout) {
      ReaderPageLayout.single => false,
      ReaderPageLayout.doublePage => canFitSpread,
      ReaderPageLayout.auto => width >= 920 && width > height && height >= 460,
    };
    final textHeight = math.max(
      120.0,
      height - bandHeight * 2 - verticalPad * 2,
    );

    if (isSpread) {
      final outerMargin = switch (settings.margin) {
        ReaderMarginLevel.compact => 22.0,
        ReaderMarginLevel.standard => 38.0,
        ReaderMarginLevel.relaxed => 64.0,
      };
      final maxSpreadWidth = switch (settings.margin) {
        ReaderMarginLevel.compact => 1120.0,
        ReaderMarginLevel.standard => 1020.0,
        ReaderMarginLevel.relaxed => 900.0,
      };
      final gutter = width >= 1060 ? 52.0 : 40.0;
      final spreadWidth = math.min(
        maxSpreadWidth,
        math.max(360.0, width - outerMargin * 2),
      );
      final columnWidth = math.max(150.0, (spreadWidth - gutter) / 2);
      return _ReaderMetrics(
        columnWidth: columnWidth,
        textHeight: textHeight,
        spreadWidth: spreadWidth,
        gutterWidth: gutter,
        bandHeight: bandHeight,
        verticalPadding: verticalPad,
        isSpread: true,
      );
    }

    final sizeClass = AppAdaptive.fromSize(Size(width, height)).sizeClass;
    final side = switch (settings.margin) {
      ReaderMarginLevel.compact => switch (sizeClass) {
          AppSizeClass.compact => 16.0,
          AppSizeClass.medium => 34.0,
          AppSizeClass.expanded => 44.0,
        },
      ReaderMarginLevel.standard => switch (sizeClass) {
          AppSizeClass.compact => 22.0,
          AppSizeClass.medium => 52.0,
          AppSizeClass.expanded => 68.0,
        },
      ReaderMarginLevel.relaxed => switch (sizeClass) {
          AppSizeClass.compact => 30.0,
          AppSizeClass.medium => 76.0,
          AppSizeClass.expanded => 104.0,
        },
    };
    final maxSingleWidth = switch (settings.margin) {
      ReaderMarginLevel.compact => 820.0,
      ReaderMarginLevel.standard => 720.0,
      ReaderMarginLevel.relaxed => 620.0,
    };
    final columnWidth = math.min(
      maxSingleWidth,
      math.max(160.0, width - side * 2),
    );
    return _ReaderMetrics(
      columnWidth: columnWidth,
      textHeight: textHeight,
      spreadWidth: columnWidth,
      gutterWidth: 0,
      bandHeight: bandHeight,
      verticalPadding: verticalPad,
      isSpread: false,
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
          height: metrics.bandHeight,
          child: _BandRow(
            width: metrics.spreadWidth,
            left: widget.book.title,
            right:
                '${Fmt.percent(controller.percentFor(spread: metrics.isSpread))} · ${Fmt.clock(_now)}',
            palette: palette,
            rightPadding: 34,
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: metrics.verticalPadding),
            child: Listener(
              onPointerSignal: _onPointerSignal,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _onTapUp,
                onHorizontalDragStart: _onDragStart,
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                onHorizontalDragCancel: _reboundDrag,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: metrics.spreadWidth,
                    height: metrics.textHeight,
                    child: page,
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: metrics.bandHeight,
          child: _BandRow(
            width: metrics.spreadWidth,
            left: controller.chapterHeaderTitle,
            right: controller.pageIndicatorFor(spread: metrics.isSpread),
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
    final currentSpread = controller.spreadSnapshot(spread: metrics.isSpread);
    if (currentSpread == null) {
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
    final mode = controller.settings.pageTurn;

    if (_dragOffset.abs() > 0.2 && mode != PageTurnMode.none) {
      final dragDirection = _dragOffset < 0 ? 1 : -1;
      final neighbor = controller.peekSpread(
        dragDirection,
        spread: metrics.isSpread,
      );
      final progress = (_dragOffset.abs() / math.max(1.0, metrics.spreadWidth))
          .clamp(0.0, 1.0);
      final currentWidget = _buildSpreadWidget(
        currentSpread,
        controller,
        palette,
        metrics,
      );

      if (neighbor == null) {
        return Transform.translate(
          offset: Offset(_dragOffset, 0),
          child: currentWidget,
        );
      }

      final neighborWidget = _buildSpreadWidget(
        neighbor,
        controller,
        palette,
        metrics,
      );

      return _renderTransitionStack(
        mode: mode,
        direction: dragDirection,
        t: progress,
        width: metrics.spreadWidth,
        palette: palette,
        fromPage: currentWidget,
        toPage: neighborWidget,
      );
    }

    final currentPage = _buildSpreadWidget(
      currentSpread,
      controller,
      palette,
      metrics,
    );
    final outgoing = _outgoing;
    if (outgoing == null) return currentPage;

    return AnimatedBuilder(
      animation: _turnAnimation,
      builder: (context, _) {
        final raw = _turnAnimation.value;
        final span = 1.0 - _turnStartProgress;
        final local = span <= 0.001
            ? 1.0
            : ((raw - _turnStartProgress) / span).clamp(0.0, 1.0);
        final easedLocal = Curves.easeOutCubic.transform(local);
        final t = _turnStartProgress + easedLocal * span;

        return _renderTransitionStack(
          mode: mode,
          direction: _turnDirection,
          t: t,
          width: metrics.spreadWidth,
          palette: palette,
          fromPage: _buildSpreadWidget(outgoing, controller, palette, metrics),
          toPage: currentPage,
        );
      },
    );
  }

  Widget _renderTransitionStack({
    required PageTurnMode mode,
    required int direction,
    required double t,
    required double width,
    required ReaderPalette palette,
    required Widget fromPage,
    required Widget toPage,
  }) {
    switch (mode) {
      case PageTurnMode.none:
        return toPage;

      case PageTurnMode.fade:
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(opacity: (1.0 - t).clamp(0.0, 1.0), child: fromPage),
              ),
            ),
            Positioned.fill(
              child: Opacity(opacity: t.clamp(0.0, 1.0), child: toPage),
            ),
          ],
        );

      case PageTurnMode.slide:
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Transform.translate(
                  offset: Offset(-width * direction * t, 0),
                  child: fromPage,
                ),
              ),
            ),
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(width * direction * (1.0 - t), 0),
                child: toPage,
              ),
            ),
          ],
        );

      case PageTurnMode.cover:
        if (direction > 0) {
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: (0.85 + 0.15 * t).clamp(0.0, 1.0),
                  child: toPage,
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Transform.translate(
                    offset: Offset(-width * t, 0),
                    child: _PageSheetWrap(
                      palette: palette,
                      showEdgeShadow: true,
                      child: fromPage,
                    ),
                  ),
                ),
              ),
            ],
          );
        } else {
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: (1.0 - 0.15 * t).clamp(0.0, 1.0),
                    child: fromPage,
                  ),
                ),
              ),
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(-width * (1.0 - t), 0),
                  child: _PageSheetWrap(
                    palette: palette,
                    showEdgeShadow: true,
                    child: toPage,
                  ),
                ),
              ),
            ],
          );
        }
    }
  }

  Widget _buildSpreadWidget(
    ReaderSpreadSnapshot spread,
    ReaderController controller,
    ReaderPalette palette,
    _ReaderMetrics metrics,
  ) {
    if (!metrics.isSpread) {
      return _buildSinglePage(spread.left, controller, palette, metrics);
    }
    return SizedBox(
      width: metrics.spreadWidth,
      height: metrics.textHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSinglePage(spread.left, controller, palette, metrics),
          _SpineGutter(
            width: metrics.gutterWidth,
            height: metrics.textHeight,
            palette: palette,
          ),
          if (spread.right != null)
            _buildSinglePage(spread.right!, controller, palette, metrics)
          else
            _EmptyRightFolio(
              width: metrics.columnWidth,
              height: metrics.textHeight,
              palette: palette,
              hasNextChapter: spread.hasNextChapter,
            ),
        ],
      ),
    );
  }

  Widget _buildSinglePage(
    ReaderPageSnapshot snapshot,
    ReaderController controller,
    ReaderPalette palette,
    _ReaderMetrics metrics,
  ) {
    return SizedBox(
      width: metrics.columnWidth,
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
                    SizedBox(
                      height: Paginator.defaultHeadingGap,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 2,
                              decoration: BoxDecoration(
                                color: palette.accent.withValues(alpha: 0.72),
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: palette.accent.withValues(alpha: 0.48),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: 0.8,
                                color: palette.divider.withValues(alpha: 0.75),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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

  Widget _buildTopChrome(
    ReaderController controller,
    ReaderPalette palette, {
    required bool bookmarked,
  }) {
    final sessionLabel = _sessionSeconds >= 60
        ? ' · 已读 ${Fmt.readingDuration(_sessionSeconds)}'
        : '';

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedSlide(
        offset: _chromeVisible ? Offset.zero : const Offset(0, -1.12),
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
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
              child: Center(
                child: SizedBox(
                  width: math.min(
                    _lastIsSpread ? 980 : 820,
                    MediaQuery.sizeOf(context).width - 16,
                  ),
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
                              '${controller.chapterHeaderTitle}$sessionLabel',
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
                        onPressed: _toggleCurrentPageBookmark,
                        tooltip: bookmarked ? '取消书签' : '夹存书签',
                        icon: Icon(
                          bookmarked
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          color: bookmarked ? const Color(0xFFC4462E) : palette.text,
                          size: 21,
                        ),
                      ),
                      if (defaultTargetPlatform == TargetPlatform.windows ||
                          defaultTargetPlatform == TargetPlatform.macOS ||
                          defaultTargetPlatform == TargetPlatform.linux)
                        IconButton(
                          onPressed: _showShortcutsDialog,
                          tooltip: '快捷键与手势',
                          icon: Icon(
                            Icons.keyboard_alt_outlined,
                            color: palette.muted,
                            size: 20,
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
    final displayPercent =
        _scrub ?? controller.percentFor(spread: _lastIsSpread);
    var displayChapter = controller.chapterIndex;
    if (_scrub != null && controller.content.isNotEmpty) {
      final offset = (_scrub! * controller.content.length)
          .floor()
          .clamp(0, math.max(0, controller.content.length - 1))
          .toInt();
      displayChapter = controller.chapterIndexForOffset(offset);
    }
    final targetChapterTitle = controller.chapters[displayChapter].title;
    final targetRemainingChars =
        ((1.0 - displayPercent) * controller.content.length)
            .round()
            .clamp(0, controller.content.length);
    final windowWidth = MediaQuery.sizeOf(context).width;
    final isWide = windowWidth >= 680;
    final contentWidth = math.min(760.0, windowWidth - 32);

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: AnimatedSlide(
        offset: _chromeVisible ? Offset.zero : const Offset(0, 1.15),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _chromeVisible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: IgnorePointer(
            ignoring: !_chromeVisible,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_scrub != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      constraints: BoxConstraints(maxWidth: contentWidth),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: palette.chrome,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: palette.divider),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.14),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              targetChapterTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: palette.text,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${Fmt.percent(displayPercent)} · 还需${Fmt.remainingTime(targetRemainingChars)}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: palette.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: isWide
                      ? const EdgeInsets.fromLTRB(16, 0, 16, 12)
                      : EdgeInsets.zero,
                  child: Container(
                    width: isWide ? math.min(780.0, windowWidth - 32) : null,
                    decoration: BoxDecoration(
                      color: palette.chrome,
                      borderRadius: isWide
                          ? BorderRadius.circular(22)
                          : const BorderRadius.vertical(
                              top: Radius.circular(22),
                            ),
                      border: isWide
                          ? Border.all(color: palette.divider)
                          : Border(top: BorderSide(color: palette.divider)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 24,
                          offset: Offset(0, isWide ? 8 : -8),
                        ),
                      ],
                    ),
                    padding: EdgeInsets.fromLTRB(
                      16,
                      isWide ? 10 : 8,
                      16,
                      isWide ? 12 : 12,
                    ),
                    child: Center(
                      child: SizedBox(
                        width: contentWidth,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isWide)
                              Container(
                                width: 38,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: palette.muted.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                          if (_undoJumpPosition != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: palette.accent.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: palette.accent.withValues(alpha: 0.22),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.history_rounded,
                                    size: 14,
                                    color: palette.accent,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      '上次停在：${_undoJumpPosition!.chapterTitle}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: palette.text,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: _undoLastJump,
                                    borderRadius: BorderRadius.circular(10),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      child: Text(
                                        '回到原位',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: palette.accent,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Text(
                                '第 ${displayChapter + 1} / ${controller.chapters.length} 章',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: palette.muted,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _scrub != null
                                    ? '松手跳转 ${Fmt.percent(displayPercent)}'
                                    : '已读 ${Fmt.percent(displayPercent)} · 还需${Fmt.remainingTime(targetRemainingChars)}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: palette.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                onPressed: () =>
                                    _runJump(controller.previousChapter),
                                tooltip: '上一章',
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  Icons.skip_previous_rounded,
                                  size: 20,
                                  color: palette.muted,
                                ),
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: palette.accent,
                                    inactiveTrackColor: palette.accent
                                        .withValues(alpha: 0.16),
                                    thumbColor: palette.accent,
                                    overlayColor: palette.accent
                                        .withValues(alpha: 0.12),
                                    trackHeight: 2.5,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 6.5,
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
                                onPressed: () =>
                                    _runJump(controller.nextChapter),
                                tooltip: '下一章',
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  Icons.skip_next_rounded,
                                  size: 20,
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
                                icon: Icons.tune_rounded,
                                label: '排版',
                                palette: palette,
                                onTap: _openSettings,
                              ),
                              _ChromeAction(
                                icon: Icons.exit_to_app_rounded,
                                label: '书架',
                                palette: palette,
                                onTap: _closeReader,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                ),
              ],
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
                const ShijuanLogo(size: 52, variant: ShijuanLogoVariant.emblem),
                const SizedBox(height: 18),
                Text(
                  widget.book.title,
                  style: ReaderTypography.heading(
                    widget.settingsRepo.settings.reader,
                    palette,
                  ).copyWith(fontSize: 22),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.accent,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '正在展卷',
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.muted,
                    letterSpacing: 1.2,
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

class _PageSheetWrap extends StatelessWidget {
  const _PageSheetWrap({
    required this.palette,
    required this.showEdgeShadow,
    required this.child,
  });

  final ReaderPalette palette;
  final bool showEdgeShadow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.top, palette.bottom],
        ),
        boxShadow: showEdgeShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: palette.isDark ? 0.45 : 0.16),
                  blurRadius: 18,
                  offset: const Offset(6, 0),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

class _ReaderMetrics {
  const _ReaderMetrics({
    required this.columnWidth,
    required this.textHeight,
    required this.spreadWidth,
    required this.gutterWidth,
    required this.bandHeight,
    required this.verticalPadding,
    required this.isSpread,
  });

  final double columnWidth;
  final double textHeight;
  final double spreadWidth;
  final double gutterWidth;
  final double bandHeight;
  final double verticalPadding;
  final bool isSpread;

  Size get columnSize => Size(columnWidth, textHeight);
}

class _SpineGutter extends StatelessWidget {
  const _SpineGutter({
    required this.width,
    required this.height,
    required this.palette,
  });

  final double width;
  final double height;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    final shadowAlpha = palette.isDark ? 0.24 : 0.05;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: shadowAlpha),
                    Colors.black.withValues(alpha: shadowAlpha * 1.4),
                    Colors.black.withValues(alpha: shadowAlpha),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.36, 0.5, 0.64, 1.0],
                ),
              ),
            ),
          ),
          Container(
            width: 1,
            height: height * 0.92,
            color: palette.divider.withValues(alpha: 0.48),
          ),
        ],
      ),
    );
  }
}

class _EmptyRightFolio extends StatelessWidget {
  const _EmptyRightFolio({
    required this.width,
    required this.height,
    required this.palette,
    required this.hasNextChapter,
  });

  final double width;
  final double height;
  final ReaderPalette palette;
  final bool hasNextChapter;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Align(
        alignment: const Alignment(0, 0.72),
        child: Opacity(
          opacity: 0.45,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 0.8,
                color: palette.divider,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  hasNextChapter ? '本章毕 · 续转下章' : '全卷终',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.6,
                    color: palette.muted,
                  ),
                ),
              ),
              Container(
                width: 24,
                height: 0.8,
                color: palette.divider,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BandRow extends StatelessWidget {
  const _BandRow({
    required this.width,
    required this.left,
    required this.right,
    required this.palette,
    this.rightPadding = 2,
  });

  final double width;
  final String left;
  final String right;
  final ReaderPalette palette;
  final double rightPadding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: width,
        child: Padding(
          padding: EdgeInsets.only(left: 2, right: rightPadding),
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

class _ShortcutLine extends StatelessWidget {
  const _ShortcutLine({
    required this.keys,
    required this.desc,
    required this.palette,
  });

  final List<String> keys;
  final String desc;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final k in keys)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: palette.top,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: palette.divider),
                    ),
                    child: Text(
                      k,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            desc,
            style: TextStyle(fontSize: 12.5, color: palette.muted),
          ),
        ],
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
