import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/brand_logo.dart';
import '../../core/formatters.dart';
import '../../core/responsive.dart';
import '../../core/seal_badges.dart';
import '../../core/theme.dart';
import '../../data/library_repository.dart';
import '../../data/models/book.dart';
import '../../data/models/reading_stats.dart';
import '../../data/native_import.dart';
import '../../data/settings_repository.dart';
import '../../data/stats_repository.dart';
import '../import/file_browser_page.dart';
import '../reader/reader_page.dart';
import 'book_card.dart';
import 'journey_sheet.dart';

class BookshelfPage extends StatefulWidget {
  const BookshelfPage({
    super.key,
    required this.library,
    required this.settings,
    this.stats,
  });

  final LibraryRepository library;
  final SettingsRepository settings;
  final StatsRepository? stats;

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  late final StatsRepository _stats;
  bool _ownsStats = false;
  late final Listenable _listenable;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  bool _searchOpen = false;
  String _searchQuery = '';
  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};
  bool _importing = false;
  String _importStatus = '';
  double? _importProgress;

  @override
  void initState() {
    super.initState();
    if (widget.stats != null) {
      _stats = widget.stats!;
    } else {
      _ownsStats = true;
      _stats = StatsRepository(root: widget.library.booksDirectory.parent);
      unawaited(_stats.init());
    }
    _listenable = Listenable.merge([widget.library, widget.settings, _stats]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final recovery = widget.library.recovery;
      if (!recovery.hasRecovery) return;
      _showSnack(
        [
          if (recovery.usedBackupIndex) '书库索引曾损坏，已从备份恢复',
          if (recovery.recoveredBooks > 0)
            '找回了 ${recovery.recoveredBooks} 本未登记的书',
        ].join(' · '),
      );
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    if (_ownsStats) _stats.dispose();
    super.dispose();
  }

  List<Book> _sortedBooks() {
    final books = List<Book>.from(widget.library.books);
    switch (widget.settings.settings.bookSort) {
      case BookSort.recent:
        books.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
        break;
      case BookSort.imported:
        books.sort((a, b) => b.importedAt.compareTo(a.importedAt));
        break;
      case BookSort.title:
        books.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
    }
    return books;
  }

  List<Book> _filterBooks(List<Book> books) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return books;
    return [
      for (final book in books)
        if (book.title.toLowerCase().contains(query) ||
            book.displayAuthor.toLowerCase().contains(query) ||
            book.lastChapterTitle.toLowerCase().contains(query))
          book,
    ];
  }

  Book? _spotlightBook(List<Book> sortedBooks) {
    if (_searchQuery.trim().isNotEmpty) return null;
    final started = sortedBooks.where((b) => b.progress.isStarted).toList();
    if (started.isEmpty) return null;
    started.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    return started.first;
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchQuery = '';
        _searchController.clear();
      }
    });
    if (_searchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  void _cycleTheme() {
    final next = widget.settings.settings.themePreference.next();
    widget.settings.updateThemePreference(next);
    _showSnack('外观已切换：${next.label}');
  }

  void _toggleViewMode() {
    final current = widget.settings.settings.shelfView;
    final next = current == ShelfViewMode.grid
        ? ShelfViewMode.list
        : ShelfViewMode.grid;
    widget.settings.updateShelfView(next);
  }

  Future<void> _openImportBrowser() async {
    if (_importing) return;
    if (Platform.isAndroid) {
      try {
        final paths = await NativeImport.pickTxtFiles();
        if (!mounted || paths.isEmpty) return;
        await _importFiles(paths);
      } catch (error) {
        if (!mounted) return;
        _showSnack('无法打开系统文件选择器：$error');
      }
      return;
    }
    final paths = await Navigator.of(context).push<List<String>>(
      PageRouteBuilder<List<String>>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, animation, secondaryAnimation) =>
            FileBrowserPage(
          initialDirectory: widget.settings.settings.lastImportDir,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.025),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
    if (!mounted || paths == null || paths.isEmpty) return;
    await _importFiles(paths);
  }

  Future<void> _importFiles(List<String> paths) async {
    setState(() {
      _importing = true;
      _importProgress = 0;
      _importStatus = paths.length == 1
          ? '正在解析 ${p.basename(paths.first)}'
          : '准备解析 ${paths.length} 个文件';
    });

    try {
      final summary = await widget.library.importPaths(
        paths,
        onProgress: (completed, total, fileName) {
          if (!mounted) return;
          setState(() {
            _importProgress = total == 0 ? null : completed / total;
            _importStatus =
                fileName.isEmpty ? '正在写入书库…' : '正在解析 $fileName';
          });
        },
      );
      if (!mounted) return;
      widget.settings.updateImportDir(p.dirname(paths.last));
      setState(() => _importing = false);

      if (summary.added.length == 1 &&
          summary.failures.isEmpty &&
          summary.skipped.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 180));
        if (!mounted) return;
        await _openBook(summary.added.first);
        return;
      }

      final parts = <String>[];
      if (summary.added.isNotEmpty) parts.add('已导入 ${summary.added.length} 本');
      if (summary.skipped.isNotEmpty) {
        parts.add('${summary.skipped.length} 本已在书架');
      }
      if (summary.failures.isNotEmpty) {
        parts.add('${summary.failures.length} 个文件失败');
      }
      if (parts.isNotEmpty) _showSnack(parts.join(' · '));

      if (summary.failures.isNotEmpty) {
        unawaited(_showFailures(summary.failures));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _importing = false);
      _showSnack('导入失败：$error');
    } finally {
      if (Platform.isAndroid) {
        unawaited(NativeImport.clearImportCache());
      }
    }
  }

  void _toggleSelectionMode([bool? enabled]) {
    final next = enabled ?? !_selectionMode;
    if (next && mounted) {
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    }
    setState(() {
      _selectionMode = next;
      if (!_selectionMode) _selectedIds.clear();
    });
  }

  void _toggleSelectBook(String bookId) {
    setState(() {
      if (!_selectedIds.add(bookId)) _selectedIds.remove(bookId);
    });
  }

  void _toggleSelectAllBooks(List<Book> visibleBooks) {
    if (visibleBooks.isEmpty) return;
    final allSelected = visibleBooks.every((b) => _selectedIds.contains(b.id));
    setState(() {
      if (allSelected) {
        for (final b in visibleBooks) {
          _selectedIds.remove(b.id);
        }
      } else {
        for (final b in visibleBooks) {
          _selectedIds.add(b.id);
        }
      }
    });
  }

  Future<void> _confirmBatchReset(List<Book> allBooks) async {
    final targets = allBooks
        .where((b) => _selectedIds.contains(b.id) && b.progress.isStarted)
        .toList();
    if (targets.isEmpty) {
      _showSnack('所选书籍暂无需要重置的阅读进度');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('批量重置进度'),
          content: Text(
            '确定要清除已选 ${targets.length} 本书的阅读进度吗？',
            style: const TextStyle(fontSize: 13.5, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('重置'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await widget.library.resetBooksProgress(targets.map((b) => b.id));
    if (!mounted) return;
    _toggleSelectionMode(false);
    _showSnack('已重置 ${targets.length} 本书的阅读进度');
  }

  Future<void> _confirmBatchDelete(List<Book> allBooks) async {
    final targets = allBooks.where((b) => _selectedIds.contains(b.id)).toList();
    if (targets.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('批量移出书架'),
          content: Text(
            '确定要删除所选 ${targets.length} 本书在应用内的本地副本与书签吗？\n'
            '原始文件不会被删除。',
            style: const TextStyle(fontSize: 13.5, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await widget.library.deleteBooks(targets);
    if (!mounted) return;
    _toggleSelectionMode(false);
    _showSnack('已将 ${targets.length} 本书移出书架');
  }

  Future<void> _compressLegacyBooks() async {
    final result = await widget.library.compressLegacyBooks();
    if (!mounted) return;
    if (result.converted == 0) {
      _showSnack('所有书籍副本均已是压缩格式');
    } else {
      _showSnack(
        '已压缩 ${result.converted} 本旧书副本，释放 ${Fmt.fileSize(result.savedBytes)} 空间',
      );
    }
  }

  Future<void> _openBook(Book book) async {
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    final latest = widget.library.bookById(book.id) ?? book;
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (context, animation, secondaryAnimation) => ReaderPage(
          book: latest,
          library: widget.library,
          settingsRepo: widget.settings,
          statsRepo: _stats,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.988, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Future<void> _showBookInfo(Book book) async {
    final latest = widget.library.bookById(book.id) ?? book;
    final action = await showDialog<_BookInfoResult>(
      context: context,
      builder: (context) => _BookInfoDialog(book: latest),
    );
    if (!mounted || action == null) return;
    if (action == _BookInfoResult.read) {
      await _openBook(latest);
    } else if (action == _BookInfoResult.reset) {
      await _confirmResetProgress(latest);
    }
  }

  Future<void> _confirmResetProgress(Book book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('重置阅读进度'),
          content: Text(
            '确定要清除《${book.title}》的阅读进度吗？\n之后将从第一章重新开始。',
            style: const TextStyle(fontSize: 13.5, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('重置'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await widget.library.resetProgress(book.id);
    if (!mounted) return;
    _showSnack('已重置《${book.title}》的阅读进度');
  }

  Future<void> _confirmDelete(Book book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('移出书架'),
          content: Text(
            '将从本地书库删除《${book.title}》及应用内的副本。\n原始文件不会被删除。',
            style: const TextStyle(fontSize: 13.5, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await widget.library.deleteBook(book);
    if (!mounted) return;
    _showSnack('已将《${book.title}》移出书架');
  }

  Future<void> _openJourneySheet() async {
    await showAdaptivePanel<void>(
      context: context,
      placement: AdaptivePanelPlacement.bottomOrCenteredDialog,
      maxDialogWidth: 780,
      maxDialogHeight: 620,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (panelContext) => ReadingJourneySheet(
        statsRepo: _stats,
        asDialog: MediaQuery.sizeOf(panelContext).width >= 600,
      ),
    );
  }

  Future<void> _showAboutDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: widget.library,
        builder: (context, _) => _AboutShijuanDialog(
          bookCount: widget.library.books.length,
          storageBytes: widget.library.storageBytes,
          legacyUncompressedCount: widget.library.legacyUncompressedCount,
          dataDir: widget.library.booksDirectory.parent.path,
          onCompressLegacy: _compressLegacyBooks,
        ),
      ),
    );
  }

  Future<void> _showFailures(List<ImportFailure> failures) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        final surface = Theme.of(context).extension<AppSurface>()!;
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('部分文件未能导入'),
          content: SizedBox(
            width: 440,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: failures.length,
                separatorBuilder: (context, index) =>
                    Divider(height: 16, color: surface.hairline),
                itemBuilder: (context, index) {
                  final failure = failures[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        failure.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        failure.message,
                        style: TextStyle(fontSize: 11.5, color: surface.muted),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _listenable,
      builder: (context, _) {
        final theme = Theme.of(context);
        final surface = theme.extension<AppSurface>()!;
        final allSorted = _sortedBooks();
        final filtered = _filterBooks(allSorted);
        final spotlight = _spotlightBook(allSorted);
        final totalChars =
            allSorted.fold<int>(0, (sum, book) => sum + book.charCount);
        final viewMode = widget.settings.settings.shelfView;
        final adaptive = AppAdaptive.of(context);
        final windowWidth = adaptive.width;
        final horizontalInset = math.max(
          adaptive.pagePadding,
          (windowWidth - AppAdaptive.shelfMaxWidth) / 2,
        );
        final contentWidth = math.max(240.0, windowWidth - horizontalInset * 2);
        final columns = adaptive.shelfGridColumns(contentWidth);
        final selecting = _selectionMode && allSorted.isNotEmpty;
        final listBottomPadding = selecting ? 96.0 : 36.0;

        return CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                () {
              if (allSorted.isNotEmpty && !_searchOpen) _toggleSearch();
            },
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (_selectionMode) {
                _toggleSelectionMode(false);
              } else if (_searchOpen) {
                _toggleSearch();
              }
            },
          },
          child: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [surface.canvasTop, surface.canvasBottom],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: -170,
                  right: -110,
                  child: IgnorePointer(
                    child: Container(
                      width: 460,
                      height: 460,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            theme.colorScheme.primary.withValues(alpha: 0.08),
                            theme.colorScheme.primary.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _buildHeader(
                          theme: theme,
                          surface: surface,
                          allBooks: allSorted,
                          visibleBooks: filtered,
                          totalChars: totalChars,
                          adaptive: adaptive,
                          horizontalInset: horizontalInset,
                        ),
                      ),
                      if (spotlight != null && adaptive.showSplitShelfHero)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              horizontalInset,
                              18,
                              horizontalInset,
                              4,
                            ),
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    flex: 7,
                                    child: _ContinueReadingBanner(
                                      book: spotlight,
                                      theme: theme,
                                      surface: surface,
                                      compact: false,
                                      horizontalPadding: 0,
                                      topPadding: 0,
                                      onOpen: () => _openBook(spotlight),
                                      onInfo: () => _showBookInfo(spotlight),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    flex: 4,
                                    child: _ReadingJourneyHeroCard(
                                      statsRepo: _stats,
                                      theme: theme,
                                      surface: surface,
                                      onTap: _openJourneySheet,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        SliverToBoxAdapter(
                          child: _ReadingJourneyStrip(
                            statsRepo: _stats,
                            theme: theme,
                            surface: surface,
                            compact: adaptive.isCompact,
                            horizontalInset: horizontalInset,
                            onTap: _openJourneySheet,
                          ),
                        ),
                      if (_searchOpen && allSorted.isNotEmpty)
                        SliverToBoxAdapter(
                          child: _buildSearchStrip(
                            theme,
                            surface,
                            horizontalInset,
                          ),
                        ),
                      if (allSorted.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _EmptyShelf(
                            surface: surface,
                            onImport: _openImportBrowser,
                          ),
                        )
                      else ...[
                        if (spotlight != null && !adaptive.showSplitShelfHero)
                          SliverToBoxAdapter(
                            child: _ContinueReadingBanner(
                              book: spotlight,
                              theme: theme,
                              surface: surface,
                              compact: adaptive.isCompact,
                              horizontalPadding: horizontalInset,
                              topPadding: 14,
                              onOpen: () => _openBook(spotlight),
                              onInfo: () => _showBookInfo(spotlight),
                            ),
                          ),
                        if (filtered.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _EmptySearch(
                              query: _searchQuery,
                              surface: surface,
                              onClear: _toggleSearch,
                            ),
                          )
                        else if (viewMode == ShelfViewMode.grid)
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              horizontalInset,
                              20,
                              horizontalInset,
                              listBottomPadding,
                            ),
                            sliver: SliverGrid(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisSpacing: adaptive.gridMainGap,
                                crossAxisSpacing: adaptive.gridGap,
                                childAspectRatio:
                                    adaptive.shelfGridAspectRatio,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final book = filtered[index];
                                  return BookCard(
                                    key: ValueKey(book.id),
                                    book: book,
                                    selectionMode: selecting,
                                    selected: _selectedIds.contains(book.id),
                                    onToggleSelect: () =>
                                        _toggleSelectBook(book.id),
                                    onOpen: () => _openBook(book),
                                    onInfo: () => _showBookInfo(book),
                                    onResetProgress: () =>
                                        _confirmResetProgress(book),
                                    onDelete: () => _confirmDelete(book),
                                  );
                                },
                                childCount: filtered.length,
                              ),
                            ),
                          )
                        else if (adaptive.useTwoColumnShelfList)
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              horizontalInset,
                              18,
                              horizontalInset,
                              listBottomPadding,
                            ),
                            sliver: SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 16,
                                mainAxisExtent: 122,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final book = filtered[index];
                                  return BookListTile(
                                    key: ValueKey('list_${book.id}'),
                                    book: book,
                                    selectionMode: selecting,
                                    selected: _selectedIds.contains(book.id),
                                    onToggleSelect: () =>
                                        _toggleSelectBook(book.id),
                                    onOpen: () => _openBook(book),
                                    onInfo: () => _showBookInfo(book),
                                    onResetProgress: () =>
                                        _confirmResetProgress(book),
                                    onDelete: () => _confirmDelete(book),
                                  );
                                },
                                childCount: filtered.length,
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              horizontalInset,
                              18,
                              horizontalInset,
                              listBottomPadding,
                            ),
                            sliver: SliverList.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (context, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final book = filtered[index];
                                return BookListTile(
                                  key: ValueKey('list_${book.id}'),
                                  book: book,
                                  selectionMode: selecting,
                                  selected: _selectedIds.contains(book.id),
                                  onToggleSelect: () =>
                                      _toggleSelectBook(book.id),
                                  onOpen: () => _openBook(book),
                                  onInfo: () => _showBookInfo(book),
                                  onResetProgress: () =>
                                      _confirmResetProgress(book),
                                  onDelete: () => _confirmDelete(book),
                                );
                              },
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                if (selecting)
                  Positioned(
                    left: horizontalInset,
                    right: horizontalInset,
                    bottom: MediaQuery.paddingOf(context).bottom + 14,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: _BatchSelectionBar(
                          selectedCount: _selectedIds
                              .where((id) => allSorted.any((b) => b.id == id))
                              .length,
                          allVisibleSelected: filtered.isNotEmpty &&
                              filtered
                                  .every((b) => _selectedIds.contains(b.id)),
                          theme: theme,
                          surface: surface,
                          onToggleSelectAll: () =>
                              _toggleSelectAllBooks(filtered),
                          onReset: () => _confirmBatchReset(allSorted),
                          onDelete: () => _confirmBatchDelete(allSorted),
                          onDone: () => _toggleSelectionMode(false),
                        ),
                      ),
                    ),
                  ),
                if (_importing)
                  Positioned.fill(
                    child: _ImportOverlay(
                      status: _importStatus,
                      progress: _importProgress,
                      surface: surface,
                      theme: theme,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader({
    required ThemeData theme,
    required AppSurface surface,
    required List<Book> allBooks,
    required List<Book> visibleBooks,
    required int totalChars,
    required AppAdaptive adaptive,
    required double horizontalInset,
  }) {
    final currentSort = widget.settings.settings.bookSort;
    final viewMode = widget.settings.settings.shelfView;
    final themePref = widget.settings.settings.themePreference;
    final narrow = adaptive.isCompact;
    final tight = adaptive.width < 380;
    final storageNote = widget.library.storageBytes > 0
        ? ' · 占用 ${Fmt.fileSize(widget.library.storageBytes)}'
        : '';

    final subtitle = allBooks.isEmpty
        ? '你的私人离线书库'
        : (_searchQuery.trim().isNotEmpty
            ? '找到 ${visibleBooks.length} / ${allBooks.length} 本'
            : '${allBooks.length} 本藏书 · 共 ${Fmt.charCount(totalChars)}$storageNote');

    final themeIcon = switch (themePref) {
      AppThemePreference.system => Icons.brightness_auto_rounded,
      AppThemePreference.light => Icons.light_mode_rounded,
      AppThemePreference.dark => Icons.dark_mode_rounded,
    };
    final controlGap = adaptive.isMedium || tight ? 6.0 : 8.0;

    final utilityControls = <Widget>[
      if (allBooks.isNotEmpty) ...[
        _HeaderIconButton(
          tooltip: _searchOpen ? '收起搜索' : '搜索书架',
          icon: _searchOpen ? Icons.search_off_rounded : Icons.search_rounded,
          active: _searchOpen,
          surface: surface,
          theme: theme,
          onTap: _toggleSearch,
        ),
        SizedBox(width: controlGap),
        _HeaderIconButton(
          tooltip: _selectionMode ? '退出批量管理' : '批量管理',
          icon: Icons.checklist_rounded,
          active: _selectionMode,
          surface: surface,
          theme: theme,
          onTap: _toggleSelectionMode,
        ),
        SizedBox(width: controlGap),
        _HeaderIconButton(
          tooltip:
              viewMode == ShelfViewMode.grid ? '切换为书目列表' : '切换为封面网格',
          icon: viewMode == ShelfViewMode.grid
              ? Icons.view_agenda_outlined
              : Icons.grid_view_rounded,
          surface: surface,
          theme: theme,
          onTap: _toggleViewMode,
        ),
        SizedBox(width: controlGap),
      ],
      _HeaderIconButton(
        tooltip: '外观：${themePref.label}（点击切换）',
        icon: themeIcon,
        surface: surface,
        theme: theme,
        onTap: _cycleTheme,
      ),
      SizedBox(width: controlGap),
      PopupMenuButton<BookSort>(
        tooltip: '排序：${currentSort.label}',
        initialValue: currentSort,
        position: PopupMenuPosition.under,
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        onSelected: widget.settings.updateSort,
        itemBuilder: (context) => [
          for (final sort in BookSort.values)
            PopupMenuItem<BookSort>(
              value: sort,
              child: Row(
                children: [
                  Text(
                    sort.label,
                    style: TextStyle(
                      fontSize: 13,
                      color: sort == currentSort
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  if (sort == currentSort)
                    Icon(
                      Icons.check_rounded,
                      size: 17,
                      color: theme.colorScheme.primary,
                    ),
                ],
              ),
            ),
        ],
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: surface.card,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: surface.hairline),
          ),
          child: Icon(
            Icons.swap_vert_rounded,
            size: 19,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.74),
          ),
        ),
      ),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalInset,
        narrow ? 16 : 22,
        horizontalInset,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              InkWell(
                onTap: _showAboutDialog,
                borderRadius: BorderRadius.circular(14),
                child: Tooltip(
                  message: '关于拾卷',
                  child: ShijuanLogo(
                    size: narrow ? 38 : 42,
                    variant: ShijuanLogoVariant.emblem,
                  ),
                ),
              ),
              SizedBox(width: tight ? 10 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          '书架',
                          style: AppTheme.serif(
                            narrow ? 25 : (adaptive.isMedium ? 27 : 30),
                            color: theme.colorScheme.onSurface,
                            letterSpacing: 1.4,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: surface.sealSoft,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: surface.seal.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Text(
                            '拾卷',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: surface.seal,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: surface.muted,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (!narrow) ...[
                ...utilityControls,
                SizedBox(width: adaptive.isMedium ? 8 : 10),
              ],
              FilledButton.icon(
                onPressed: _openImportBrowser,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: tight ? 12 : (narrow ? 14 : 18),
                    vertical: 12,
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('导入书籍'),
              ),
            ],
          ),
          if (narrow) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                ...utilityControls,
                const Spacer(),
                Text(
                  currentSort.label,
                  style: TextStyle(fontSize: 11.5, color: surface.muted),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Divider(height: 1, color: surface.hairline),
        ],
      ),
    );
  }

  Widget _buildSearchStrip(
    ThemeData theme,
    AppSurface surface,
    double horizontalInset,
  ) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalInset, 14, horizontalInset, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocus,
            style: TextStyle(fontSize: 13.5, color: theme.colorScheme.onSurface),
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: InputDecoration(
              isDense: true,
              hintText: '搜索书名、作者或最近读到的章节…',
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 19,
                color: surface.muted,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      tooltip: '清空',
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: surface.muted,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.surface,
    required this.theme,
    required this.onTap,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final AppSurface surface;
  final ThemeData theme;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? theme.colorScheme.primaryContainer : surface.card,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: active
                    ? theme.colorScheme.primary.withValues(alpha: 0.4)
                    : surface.hairline,
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.74),
            ),
          ),
        ),
      ),
    );
  }
}

/// Spotlight card highlighting the book currently being read.
class _ContinueReadingBanner extends StatelessWidget {
  const _ContinueReadingBanner({
    required this.book,
    required this.theme,
    required this.surface,
    required this.compact,
    this.horizontalPadding = 20,
    this.topPadding = 14,
    required this.onOpen,
    required this.onInfo,
  });

  final Book book;
  final ThemeData theme;
  final AppSurface surface;
  final bool compact;
  final double horizontalPadding;
  final double topPadding;
  final VoidCallback onOpen;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final progress = book.progress.percent.clamp(0.0, 1.0);
    final remainingChars =
        ((1.0 - progress) * book.charCount).round().clamp(0, book.charCount);
    final isFinished = progress >= 0.999;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        topPadding,
        horizontalPadding,
        topPadding == 0 ? 0 : 4,
      ),
      child: Material(
        color: surface.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: EdgeInsets.all(compact ? 16 : 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: surface.hairline),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  surface.elevated,
                  surface.tint.withValues(alpha: 0.42),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                SizedBox(
                  width: compact ? 64 : 76,
                  height: compact ? 88 : 104,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.20),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: BookCoverArt(
                      book: book,
                      compact: true,
                      showWatermark: false,
                      showTitle: !compact,
                      borderRadius: 11,
                    ),
                  ),
                ),
                SizedBox(width: compact ? 14 : 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: surface.sealSoft,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isFinished ? '最近读完' : '案头续读',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: surface.seal,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              book.displayAuthor,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: surface.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.serif(
                          compact ? 18 : 21,
                          color: theme.colorScheme.onSurface,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        book.lastChapterTitle.isEmpty
                            ? '第 ${book.progress.chapterIndex + 1} / ${book.chapterCount} 章'
                            : '读至：${book.lastChapterTitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.72),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 4.5,
                                backgroundColor: theme.colorScheme.primary
                                    .withValues(alpha: 0.12),
                                color: isFinished
                                    ? surface.seal
                                    : theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            isFinished
                                ? '100%'
                                : '${Fmt.percent(progress)} · 还需${Fmt.remainingTime(remainingChars)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isFinished
                                  ? surface.seal
                                  : theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 20),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FilledButton.icon(
                        onPressed: onOpen,
                        icon: const Icon(Icons.menu_book_rounded, size: 17),
                        label: Text(isFinished ? '重温本书' : '继续阅读'),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: onInfo,
                        child: Text(
                          '书籍详情',
                          style: TextStyle(fontSize: 12, color: surface.muted),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.surface, required this.onImport});

  final AppSurface surface;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: surface.tint.withValues(alpha: 0.55),
                border: Border.all(color: surface.hairline),
              ),
              child: const Center(
                child: ShijuanLogo(
                  size: 74,
                  variant: ShijuanLogoVariant.mark,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '书架还是空的',
              style: AppTheme.serif(
                24,
                color: theme.colorScheme.onSurface,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '支持导入本地 TXT、EPUB、MOBI、PDF、Word 文档\n自动识别编码、拆分目录并压缩保存在书库中',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.7,
                color: surface.muted,
              ),
            ),
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text('选择本地书籍'),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _FeatureChip(label: 'TXT · EPUB · MOBI', surface: surface),
                _FeatureChip(label: 'PDF · Word 支持', surface: surface),
                _FeatureChip(label: '压缩存储 · 纯净离线', surface: surface),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.label, required this.surface});

  final String label;
  final AppSurface surface;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: surface.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: surface.hairline),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: surface.muted),
      ),
    );
  }
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch({
    required this.query,
    required this.surface,
    required this.onClear,
  });

  final String query;
  final AppSurface surface;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 42, color: surface.muted),
            const SizedBox(height: 14),
            Text(
              '没有找到「${query.trim()}」相关的书籍',
              style: TextStyle(fontSize: 15, color: theme.colorScheme.onSurface),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: onClear,
              child: const Text('清空搜索'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportOverlay extends StatelessWidget {
  const _ImportOverlay({
    required this.status,
    required this.progress,
    required this.surface,
    required this.theme,
  });

  final String status;
  final double? progress;
  final AppSurface surface;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ModalBarrier(
            dismissible: false,
            color: Colors.black.withValues(alpha: 0.24),
          ),
        ),
        Center(
          child: Material(
            color: surface.card,
            elevation: 14,
            shadowColor: Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              width: math.min(350, MediaQuery.sizeOf(context).width - 48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const ShijuanLogo(
                          size: 38,
                          variant: ShijuanLogoVariant.emblem,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '正在导入书库',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: surface.muted),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3.5,
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: 0.12),
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '自动解析文档结构、识别章节并压缩存入本地书库',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: surface.muted.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _BookInfoResult { read, reset }

class _BookInfoDialog extends StatelessWidget {
  const _BookInfoDialog({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.extension<AppSurface>()!;
    final progress = book.progress.percent.clamp(0.0, 1.0);
    final remainingChars =
        ((1.0 - progress) * book.charCount).round().clamp(0, book.charCount);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      backgroundColor: surface.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 66,
                    height: 90,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: BookCoverArt(
                        book: book,
                        compact: true,
                        showWatermark: false,
                        showTitle: false,
                        borderRadius: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          style: AppTheme.serif(
                            20,
                            color: theme.colorScheme.onSurface,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          book.displayAuthor,
                          style: TextStyle(fontSize: 12.5, color: surface.muted),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _FeatureChip(
                              label: '${book.chapterCount} 章',
                              surface: surface,
                            ),
                            _FeatureChip(
                              label: Fmt.charCount(book.charCount),
                              surface: surface,
                            ),
                            _FeatureChip(
                              label: book.encoding,
                              surface: surface,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: surface.tint.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: surface.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          book.progress.isStarted ? '当前阅读进度' : '尚未开始阅读',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          book.progress.isStarted
                              ? Fmt.percent(progress)
                              : '0%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: 0.12),
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      book.progress.isStarted
                          ? '${book.lastChapterTitle.isEmpty ? '第 ${book.progress.chapterIndex + 1} 章' : book.lastChapterTitle} · ${Fmt.remainingTime(remainingChars)}'
                          : '全书约需 ${Fmt.remainingTime(book.charCount)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: surface.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _InfoRow(label: '原始文件', value: book.fileName),
              _InfoRow(label: '文件大小', value: Fmt.fileSize(book.fileSize)),
              _InfoRow(label: '导入时间', value: Fmt.dateTime(book.importedAt)),
              if (book.progress.updatedAt != null)
                _InfoRow(
                  label: '最近阅读',
                  value: Fmt.dateTime(book.progress.updatedAt!),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (book.progress.isStarted)
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_BookInfoResult.reset),
                      child: Text(
                        '重置进度',
                        style: TextStyle(color: surface.muted),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_BookInfoResult.read),
                    child: Text(book.progress.isStarted ? '继续阅读' : '开始阅读'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutShijuanDialog extends StatelessWidget {
  const _AboutShijuanDialog({
    required this.bookCount,
    required this.storageBytes,
    required this.legacyUncompressedCount,
    required this.dataDir,
    required this.onCompressLegacy,
  });

  final int bookCount;
  final int storageBytes;
  final int legacyUncompressedCount;
  final String dataDir;
  final VoidCallback onCompressLegacy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.extension<AppSurface>()!;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      backgroundColor: surface.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(26, 28, 26, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ShijuanLogo(size: 70, variant: ShijuanLogoVariant.emblem),
              const SizedBox(height: 16),
              Text(
                '拾卷 · ShiJuan Reader',
                style: AppTheme.serif(
                  21,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '静心离线 · 多格式本地书库阅读器',
                style: TextStyle(fontSize: 12.5, color: surface.muted),
              ),
              const SizedBox(height: 18),
              Divider(height: 1, color: surface.hairline),
              const SizedBox(height: 14),
              _InfoRow(
                label: '当前藏书',
                value:
                    '$bookCount 本 · 占用 ${Fmt.fileSize(storageBytes)}（Gzip 压缩存储）',
              ),
              _InfoRow(
                label: '支持格式',
                value: 'TXT · EPUB · MOBI · AZW3 · PDF · Word',
              ),
              _InfoRow(label: '书库目录', value: dataDir),
              _InfoRow(
                label: '内置字体',
                value: '文楷 / 宋体 / 黑体（SIL OFL 1.1）',
              ),
              _InfoRow(
                label: '阅读快捷键',
                value: '← → 空格翻页 · M 菜单 · T 目录 · S 排版 · N 日夜',
              ),
              if (legacyUncompressedCount > 0) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: surface.tint,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: surface.hairline),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '检测到 $legacyUncompressedCount 本旧版未压缩书籍，可一键压缩以节省约 50% 空间',
                          style: TextStyle(
                            fontSize: 12,
                            color: surface.muted,
                            height: 1.45,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onCompressLegacy();
                        },
                        child: const Text('一键压缩'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('知道了'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BatchSelectionBar extends StatelessWidget {
  const _BatchSelectionBar({
    required this.selectedCount,
    required this.allVisibleSelected,
    required this.theme,
    required this.surface,
    required this.onToggleSelectAll,
    required this.onReset,
    required this.onDelete,
    required this.onDone,
  });

  final int selectedCount;
  final bool allVisibleSelected;
  final ThemeData theme;
  final AppSurface surface;
  final VoidCallback onToggleSelectAll;
  final VoidCallback onReset;
  final VoidCallback onDelete;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    final hasSelection = selectedCount > 0;

    List<Widget> buildActionButtons({required bool includeDone}) {
      return [
        OutlinedButton.icon(
          onPressed: onToggleSelectAll,
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          ),
          icon: Icon(
            allVisibleSelected
                ? Icons.deselect_rounded
                : Icons.select_all_rounded,
            size: 16,
          ),
          label: Text(allVisibleSelected ? '取消全选' : '全选'),
        ),
        OutlinedButton.icon(
          onPressed: hasSelection ? onReset : null,
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          ),
          icon: const Icon(Icons.restart_alt_rounded, size: 16),
          label: const Text('重置进度'),
        ),
        FilledButton.tonalIcon(
          onPressed: hasSelection ? onDelete : null,
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            foregroundColor: hasSelection ? cs.error : null,
            backgroundColor: hasSelection
                ? cs.errorContainer.withValues(alpha: 0.65)
                : null,
          ),
          icon: const Icon(Icons.delete_outline_rounded, size: 16),
          label: const Text('移出书架'),
        ),
        if (includeDone)
          TextButton(
            onPressed: onDone,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            child: const Text('完成'),
          ),
      ];
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: surface.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final status = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.checklist_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  selectedCount == 0 ? '点击书籍卡片多选' : '已选择 $selectedCount 本',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          );

          if (constraints.maxWidth >= 580) {
            return Row(
              children: [
                Expanded(child: status),
                const SizedBox(width: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: buildActionButtons(includeDone: true),
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: status),
                  TextButton(
                    onPressed: onDone,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ),
                    child: const Text('退出管理'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: buildActionButtons(includeDone: false),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurface>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(fontSize: 11.5, color: surface.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact reading journey summary strip connecting bookshelf & milestones.
class _ReadingJourneyStrip extends StatelessWidget {
  const _ReadingJourneyStrip({
    required this.statsRepo,
    required this.theme,
    required this.surface,
    required this.compact,
    required this.horizontalInset,
    required this.onTap,
  });

  final StatsRepository statsRepo;
  final ThemeData theme;
  final AppSurface surface;
  final bool compact;
  final double horizontalInset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stats = statsRepo.stats;
    final todayMins = statsRepo.todayReadingSeconds ~/ 60;
    final goalProgress = statsRepo.todayGoalProgress;
    final unlockedCount =
        StampId.values.where((s) => stats.isUnlocked(s)).length;
    final latestUnlocked = StampId.values.lastWhere(
      (s) => stats.isUnlocked(s),
      orElse: () => StampId.firstOpen,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalInset, 14, horizontalInset, 0),
      child: Material(
        color: surface.card,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: surface.hairline),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: goalProgress,
                        strokeWidth: 3,
                        strokeCap: StrokeCap.round,
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: 0.12),
                        color: goalProgress >= 1.0
                            ? surface.seal
                            : theme.colorScheme.primary,
                      ),
                      if (unlockedCount > 0)
                        SealStampBadge(
                          stamp: latestUnlocked,
                          unlocked: true,
                          size: 16,
                        )
                      else
                        Icon(
                          Icons.auto_stories_outlined,
                          size: 13,
                          color: surface.muted,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    todayMins > 0
                        ? '今日已读 $todayMins / ${stats.dailyGoalMinutes} 分钟'
                            '${stats.streakDays > 0 ? ' · 连续 ${stats.streakDays} 天' : ''}'
                        : (stats.streakDays > 0
                            ? '连续拾卷 ${stats.streakDays} 天 · 今日尚未展卷'
                            : '拾卷印记 · 每日阅读 ${stats.dailyGoalMinutes} 分钟目标'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (!compact && stats.totalPagesTurned > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '累计翻阅 ${Fmt.number(stats.totalPagesTurned)} 页',
                    style: TextStyle(fontSize: 11, color: surface.muted),
                  ),
                ],
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: unlockedCount > 0
                        ? surface.sealSoft
                        : surface.tint.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '印章 $unlockedCount/${StampId.values.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: unlockedCount > 0 ? surface.seal : surface.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: surface.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Companion card rendered alongside the spotlight banner on landscape tablets
/// and wide desktop screens.
class _ReadingJourneyHeroCard extends StatelessWidget {
  const _ReadingJourneyHeroCard({
    required this.statsRepo,
    required this.theme,
    required this.surface,
    required this.onTap,
  });

  final StatsRepository statsRepo;
  final ThemeData theme;
  final AppSurface surface;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stats = statsRepo.stats;
    final todayMins = statsRepo.todayReadingSeconds ~/ 60;
    final goalProgress = statsRepo.todayGoalProgress;
    final unlockedStamps =
        StampId.values.where((s) => stats.isUnlocked(s)).toList();
    final unlockedCount = unlockedStamps.length;
    final latestUnlocked =
        unlockedStamps.isNotEmpty ? unlockedStamps.last : StampId.firstOpen;

    return Material(
      color: surface.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: surface.hairline),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                surface.card,
                surface.tint.withValues(alpha: 0.36),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            value: goalProgress,
                            strokeWidth: 4,
                            strokeCap: StrokeCap.round,
                            backgroundColor: theme.colorScheme.primary
                                .withValues(alpha: 0.12),
                            color: goalProgress >= 1.0
                                ? surface.seal
                                : theme.colorScheme.primary,
                          ),
                        ),
                        if (unlockedCount > 0)
                          SealStampBadge(
                            stamp: latestUnlocked,
                            unlocked: true,
                            size: 22,
                          )
                        else
                          Icon(
                            Icons.auto_stories_outlined,
                            size: 16,
                            color: surface.muted,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '拾卷印记',
                              style: AppTheme.serif(
                                16,
                                color: theme.colorScheme.onSurface,
                                height: 1.2,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: unlockedCount > 0
                                    ? surface.sealSoft
                                    : surface.tint.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '印章 $unlockedCount/${StampId.values.length}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: unlockedCount > 0
                                      ? surface.seal
                                      : surface.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          todayMins > 0
                              ? '今日已读 $todayMins / ${stats.dailyGoalMinutes} 分钟'
                              : (stats.streakDays > 0
                                  ? '连续拾卷 ${stats.streakDays} 天'
                                  : '每日阅读 ${stats.dailyGoalMinutes} 分钟目标'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: surface.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (unlockedStamps.isEmpty)
                    Text(
                      '展卷阅读即可集朱砂印章',
                      style: TextStyle(fontSize: 11.5, color: surface.muted),
                    )
                  else
                    for (final s in unlockedStamps.take(5))
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: SealStampBadge(
                          stamp: s,
                          unlocked: true,
                          size: 22,
                        ),
                      ),
                  const Spacer(),
                  Text(
                    stats.streakDays > 0 ? '连读 ${stats.streakDays} 天' : '印章墙',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
