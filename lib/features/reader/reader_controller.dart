import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/book.dart';
import '../../data/models/chapter.dart';
import '../../data/models/reader_settings.dart';
import 'paginator.dart';

class ReaderPosition {
  const ReaderPosition({
    required this.chapterIndex,
    required this.charOffset,
    required this.percent,
    required this.chapterTitle,
  });

  final int chapterIndex;

  /// Absolute UTF-16 offset in the book content.
  final int charOffset;

  /// 0..1
  final double percent;
  final String chapterTitle;
}

/// Everything needed to paint one page, decoupled from the live controller so
/// the outgoing page can still be animated after a page turn.
class ReaderPageSnapshot {
  const ReaderPageSnapshot({
    required this.chapterIndex,
    required this.pageIndex,
    required this.chapterTitle,
    required this.meta,
    required this.body,
    required this.isFirstPage,
  });

  final int chapterIndex;
  final int pageIndex;
  final String chapterTitle;
  final String meta;
  final String body;
  final bool isFirstPage;

  bool samePage(ReaderPageSnapshot? other) =>
      other != null &&
      other.chapterIndex == chapterIndex &&
      other.pageIndex == pageIndex;
}

class ReaderController extends ChangeNotifier {
  ReaderController({
    required this.book,
    required this.content,
    required this.chapters,
    required ReaderSettings settings,
    required this.onProgress,
    // The private field cannot be an initializing formal because named
    // parameters may not start with an underscore.
    // ignore: prefer_initializing_formals
  })  : _settings = settings {
    _chapterIndex = book.progress.chapterIndex.clamp(
      0,
      math.max(0, chapters.length - 1),
    );
    final chapter = chapters.isEmpty ? null : chapters[_chapterIndex];
    final saved = book.progress.charOffset;
    _initialOffset = chapter == null
        ? 0
        : saved.clamp(chapter.start, math.max(chapter.start, chapter.end - 1));
  }

  final Book book;
  final String content;
  final List<Chapter> chapters;
  final ValueChanged<ReaderPosition> onProgress;

  ReaderSettings _settings;
  ReaderSettings get settings => _settings;
  ReaderPalette get palette => ReaderPalette.of(_settings.theme);
  TextStyle get bodyStyle => ReaderTypography.body(_settings, palette);
  TextStyle get headingStyle => ReaderTypography.heading(_settings, palette);
  TextStyle get metaStyle => ReaderTypography.meta(_settings, palette);

  int _chapterIndex = 0;
  int _pageIndex = 0;
  List<PageSlice> _pages = const [];
  Size _layout = Size.zero;
  String? _layoutKey;
  final Map<int, List<PageSlice>> _pageCache = {};
  bool _hasLaidOut = false;
  bool _disposed = false;
  late final int _initialOffset;
  Timer? _prewarmTimer;

  int get chapterIndex => _chapterIndex;
  int get pageIndex => _pageIndex;
  List<PageSlice> get pages => _pages;
  Size get layoutSize => _layout;
  bool get hasLayout => _hasLaidOut && _pages.isNotEmpty;

  /// Chapters whose pages are already laid out.
  @visibleForTesting
  Set<int> get cachedChapters => Set<int>.unmodifiable(_pageCache.keys);

  Chapter get chapter => chapters[_chapterIndex];

  String get chapterHeaderTitle => _headerTitleFor(_chapterIndex);

  String get chapterMeta => _metaFor(_chapterIndex);

  String _headerTitleFor(int index) {
    final title = chapters[index].title.trim();
    if (title.isEmpty || title == '全文') return book.title;
    return title;
  }

  String _metaFor(int index) => '共 ${Fmt.number(chapters[index].length)} 字';

  int get absoluteOffset {
    if (_pages.isEmpty) return _initialOffset;
    return chapter.start + _pages[_pageIndex].start;
  }

  int get offsetInChapter {
    if (_pages.isEmpty) return 0;
    return _pages[_pageIndex].start;
  }

  double get percent {
    if (content.isEmpty) return 0;
    if (_chapterIndex == chapters.length - 1 &&
        _pages.isNotEmpty &&
        _pageIndex == _pages.length - 1) {
      return 1;
    }
    return (absoluteOffset / content.length).clamp(0.0, 1.0);
  }

  int get remainingChars =>
      math.max(0, content.length - absoluteOffset);

  String get pageIndicator =>
      '${_pageIndex + 1} / ${_pages.isEmpty ? 1 : _pages.length}';

  bool get isFirstPageOfBook => _chapterIndex == 0 && _pageIndex == 0;

  bool get isLastPageOfBook =>
      _chapterIndex == chapters.length - 1 &&
      _pages.isNotEmpty &&
      _pageIndex == _pages.length - 1;

  ReaderPageSnapshot? snapshot() {
    if (_pages.isEmpty) return null;
    final page = _pages[_pageIndex];
    final start = chapter.start + page.start;
    final end = chapter.start + page.end;
    if (start < 0 || end > content.length || start >= end) return null;
    return ReaderPageSnapshot(
      chapterIndex: _chapterIndex,
      pageIndex: _pageIndex,
      chapterTitle: chapterHeaderTitle,
      meta: chapterMeta,
      body: content.substring(start, end),
      isFirstPage: _pageIndex == 0,
    );
  }

  /// Called after the reader computes its text-area size. Re-paginates only
  /// when the size or typography actually changed.
  void ensureLayout(Size size) {
    if (size.width < 48 || size.height < 48) return;
    final key = _keyFor(size);
    if (key == _layoutKey && _pages.isNotEmpty) return;
    final anchor = _hasLaidOut ? absoluteOffset : _initialOffset;
    _layout = size;
    _layoutKey = key;
    _cacheClear();
    _pages = _pagesForChapter(_chapterIndex);
    _pageIndex = _pageIndexForAnchor(anchor);
    _hasLaidOut = true;
    notifyListeners();
    _emitProgress();
  }

  void applySettings(ReaderSettings settings) {
    if (settings.fontSize == _settings.fontSize &&
        settings.lineHeight == _settings.lineHeight &&
        settings.font == _settings.font &&
        settings.theme == _settings.theme) {
      return;
    }
    final anchor = _hasLaidOut ? absoluteOffset : _initialOffset;
    _settings = settings;
    if (_hasLaidOut && _layout.width >= 48) {
      _layoutKey = _keyFor(_layout);
      _cacheClear();
      _pages = _pagesForChapter(_chapterIndex);
      _pageIndex = _pageIndexForAnchor(anchor);
    }
    notifyListeners();
    if (_hasLaidOut) prewarmWhenIdle();
  }

  /// Lays out the chapters next to the current one once the reader has been
  /// idle for a moment, so crossing a chapter boundary reuses cached pages
  /// instead of laying out a whole chapter in the middle of a page turn.
  ///
  /// Every call restarts the delay; the reader page calls it on each turn so
  /// the work never lands on top of a page-turn animation.
  void prewarmWhenIdle() {
    _prewarmTimer?.cancel();
    if (_disposed || !_hasLaidOut) return;
    _prewarmTimer = Timer(const Duration(milliseconds: 420), _prewarmStep);
  }

  void _prewarmStep() {
    _prewarmTimer = null;
    if (_disposed || !_hasLaidOut) return;
    final next = _chapterIndex + 1;
    final previous = _chapterIndex - 1;
    final int? target;
    if (next < chapters.length && !_pageCache.containsKey(next)) {
      target = next;
    } else if (previous >= 0 && !_pageCache.containsKey(previous)) {
      target = previous;
    } else {
      return;
    }
    _pagesForChapter(target);
    // Let a frame through before touching the chapter on the other side.
    _prewarmTimer = Timer(const Duration(milliseconds: 40), _prewarmStep);
  }

  @override
  void dispose() {
    _disposed = true;
    _prewarmTimer?.cancel();
    super.dispose();
  }

  /// Returns false when the book is already at the first/last page.
  bool turnPage(int direction) {
    if (_pages.isEmpty) return false;
    if (direction > 0) {
      if (_pageIndex < _pages.length - 1) {
        _pageIndex++;
      } else if (_chapterIndex < chapters.length - 1) {
        _chapterIndex++;
        _pages = _pagesForChapter(_chapterIndex);
        _pageIndex = 0;
      } else {
        return false;
      }
    } else {
      if (_pageIndex > 0) {
        _pageIndex--;
      } else if (_chapterIndex > 0) {
        _chapterIndex--;
        _pages = _pagesForChapter(_chapterIndex);
        _pageIndex = math.max(0, _pages.length - 1);
      } else {
        return false;
      }
    }
    notifyListeners();
    _emitProgress();
    return true;
  }

  bool nextChapter() {
    if (_chapterIndex >= chapters.length - 1) return false;
    _chapterIndex++;
    _pages = _pagesForChapter(_chapterIndex);
    _pageIndex = 0;
    notifyListeners();
    _emitProgress();
    return true;
  }

  bool previousChapter() {
    if (_chapterIndex <= 0) return false;
    _chapterIndex--;
    _pages = _pagesForChapter(_chapterIndex);
    _pageIndex = math.max(0, _pages.length - 1);
    notifyListeners();
    _emitProgress();
    return true;
  }

  void goToChapter(int index, {int? offsetInChapter}) {
    if (chapters.isEmpty) return;
    final previousIndex = _chapterIndex;
    final target = index.clamp(0, chapters.length - 1);
    final sameChapter = target == previousIndex;
    final anchor = offsetInChapter != null
        ? chapters[target].start + offsetInChapter
        : (sameChapter ? absoluteOffset : chapters[target].start);
    _chapterIndex = target;
    if (_layout.width >= 48) {
      _pages = _pagesForChapter(target);
      _pageIndex = offsetInChapter != null || sameChapter
          ? _pageIndexForAnchor(anchor)
          : 0;
    } else {
      _pageIndex = 0;
    }
    notifyListeners();
    _emitProgress();
  }

  void jumpToGlobalOffset(int targetOffset) {
    if (content.isEmpty || chapters.isEmpty) return;
    final offset =
        targetOffset.clamp(0, math.max(0, content.length - 1)).toInt();
    final targetChapter = chapterIndexForOffset(offset);
    _chapterIndex = targetChapter;
    if (_layout.width >= 48) {
      _pages = _pagesForChapter(targetChapter);
      _pageIndex = _pageIndexForAnchor(offset);
    }
    notifyListeners();
    _emitProgress();
  }

  void jumpToPercent(double fraction) {
    if (content.isEmpty) return;
    final target = (fraction.clamp(0.0, 1.0) * content.length)
        .floor()
        .clamp(0, math.max(0, content.length - 1))
        .toInt();
    jumpToGlobalOffset(target);
  }

  int chapterIndexForOffset(int offset) {
    if (chapters.isEmpty) return 0;
    var low = 0;
    var high = chapters.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (chapters[mid].start <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  ReaderPosition currentPosition() => ReaderPosition(
        chapterIndex: _chapterIndex,
        charOffset: absoluteOffset,
        percent: percent,
        chapterTitle: chapter.title,
      );

  void _emitProgress() {
    if (_pages.isEmpty) return;
    onProgress(currentPosition());
    prewarmWhenIdle();
  }

  String _keyFor(Size size) =>
      '${size.width.toStringAsFixed(2)}x${size.height.toStringAsFixed(2)}'
      '|${_settings.fontSize}|${_settings.lineHeight}|${_settings.font.name}';

  void _cacheClear() => _pageCache.clear();

  List<PageSlice> _pagesForChapter(int index) {
    final cached = _pageCache[index];
    if (cached != null) return cached;
    if (_layout.width < 48) return const [];
    final chapter = chapters[index];
    final body = content.substring(
      chapter.start.clamp(0, content.length).toInt(),
      chapter.end.clamp(0, content.length).toInt(),
    );
    final pages = Paginator.paginate(
      text: body,
      bodyStyle: bodyStyle,
      width: _layout.width,
      // Keep a couple of pixels of slack so painted glyphs never spill into
      // the footer band.
      height: math.max(40.0, _layout.height - 2),
      heading: _headerTitleFor(index),
      headingStyle: headingStyle,
      headingMeta: _metaFor(index),
      metaStyle: metaStyle,
    );
    if (_pageCache.length > 12) _pageCache.clear();
    _pageCache[index] = pages;
    return pages;
  }

  int _pageIndexForAnchor(int absoluteAnchor, {List<PageSlice>? forPages}) {
    final pages = forPages ?? _pages;
    if (pages.isEmpty) return 0;
    final chapter = chapters[_chapterIndex];
    final relative = (absoluteAnchor - chapter.start)
        .clamp(0, math.max(0, chapter.end - chapter.start - 1));
    var low = 0;
    var high = pages.length - 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (pages[mid].end <= relative) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}
