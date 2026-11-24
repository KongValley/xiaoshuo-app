import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shijuan_reader/data/models/book.dart';
import 'package:shijuan_reader/data/models/chapter.dart';
import 'package:shijuan_reader/data/models/reader_settings.dart';
import 'package:shijuan_reader/features/reader/reader_controller.dart';

const _paragraph = '夜色渐深，风从窗缝里钻进来，书页轻轻翻动，远处传来几声犬吠。\n';
const _size = Size(312, 528);

void main() {
  late String content;
  late List<Chapter> chapters;

  // Three chapters. The first is a single page; the second spans many.
  setUp(() {
    final first = List.filled(3, _paragraph).join();
    final second = List.filled(90, _paragraph).join();
    final third = List.filled(4, _paragraph).join();
    content = first + second + third;
    chapters = [
      Chapter(title: '第一章 起点', start: 0, end: first.length),
      Chapter(
        title: '第二章 转折',
        start: first.length,
        end: first.length + second.length,
      ),
      Chapter(
        title: '第三章 结尾',
        start: first.length + second.length,
        end: content.length,
      ),
    ];
  });

  // The binding rejects a test that leaves a timer behind, so every
  // controller is disposed at the end of the test body rather than in a
  // tearDown callback, which only runs after that check.
  ReaderController create({
    ReadingProgress progress = const ReadingProgress(),
    void Function(ReaderPosition)? onProgress,
  }) {
    final book = Book(
      id: 'book',
      title: '测试小说',
      author: '',
      fileName: '测试小说.txt',
      encoding: 'UTF-8',
      charCount: content.length,
      chapterCount: chapters.length,
      fileSize: 0,
      importedAt: DateTime(2026, 1, 1),
      lastOpenedAt: DateTime(2026, 1, 1),
      lastChapterTitle: '',
      progress: progress,
    );
    return ReaderController(
      book: book,
      content: content,
      chapters: chapters,
      settings: const ReaderSettings(),
      onProgress: onProgress ?? (_) {},
    );
  }

  testWidgets('turns pages across chapters and reports progress', (
    tester,
  ) async {
    final positions = <ReaderPosition>[];
    final controller = create(onProgress: positions.add);
    controller.ensureLayout(_size);

    expect(controller.hasLayout, isTrue);
    expect(controller.chapterIndex, 0);
    expect(controller.isFirstPageOfBook, isTrue);
    expect(controller.turnPage(-1), isFalse);

    // Chapter one is a single page at this size, so one turn crosses over.
    expect(controller.turnPage(1), isTrue);
    expect(controller.chapterIndex, 1);
    expect(controller.pageIndex, 0);
    expect(controller.pages.length, greaterThan(2));

    expect(controller.turnPage(1), isTrue);
    expect(controller.pageIndex, 1);

    // Going back from a first page lands on the last page of the chapter
    // before it.
    controller.goToChapter(1, offsetInChapter: 0);
    expect(controller.turnPage(-1), isTrue);
    expect(controller.chapterIndex, 0);
    expect(controller.pageIndex, controller.pages.length - 1);

    expect(controller.nextChapter(), isTrue);
    expect(controller.chapterIndex, 1);
    expect(controller.previousChapter(), isTrue);
    expect(controller.chapterIndex, 0);
    expect(controller.previousChapter(), isFalse);

    expect(positions, isNotEmpty);
    expect(positions.last.chapterTitle, '第一章 起点');
    expect(positions.last.percent, 0);

    controller.dispose();
  });

  testWidgets('restores the saved page and reports the end of the book', (
    tester,
  ) async {
    final probe = create();
    probe.ensureLayout(_size);
    probe.goToChapter(1);
    probe.turnPage(1);
    // The reader saves the first character of whichever page was on screen.
    final saved = probe.absoluteOffset;
    expect(saved, greaterThan(chapters[1].start));
    probe.dispose();

    final restored = create(
      progress: ReadingProgress(
        chapterIndex: 1,
        charOffset: saved,
        percent: 0.4,
        updatedAt: DateTime(2026, 1, 2),
      ),
    );
    restored.ensureLayout(_size);
    expect(restored.chapterIndex, 1);
    expect(restored.absoluteOffset, saved);

    // A different text size keeps the reader on the page holding that spot.
    restored.applySettings(const ReaderSettings(fontSize: 26));
    final page = restored.pages[restored.pageIndex];
    expect(chapters[1].start + page.start, lessThanOrEqualTo(saved));
    expect(chapters[1].start + page.end, greaterThan(saved));

    // The last page of the last chapter means the book is finished.
    expect(restored.nextChapter(), isTrue);
    var turns = 0;
    while (restored.turnPage(1) && turns < 100) {
      turns++;
    }
    expect(restored.isLastPageOfBook, isTrue);
    expect(restored.percent, 1);
    expect(restored.turnPage(1), isFalse);

    restored.dispose();
  });

  testWidgets('lays out the neighbouring chapters once the reader is idle', (
    tester,
  ) async {
    final controller = create();
    expect(controller.cachedChapters, isEmpty);

    controller.ensureLayout(_size);
    expect(controller.cachedChapters, {0});

    // Nothing happens while the reader is still turning pages.
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.cachedChapters, {0});
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.cachedChapters, {0, 1});

    // Crossing into the warmed chapter is a cache hit, and the chapter after
    // it is warmed in turn.
    expect(controller.turnPage(1), isTrue);
    await tester.pump(const Duration(milliseconds: 700));
    expect(controller.chapterIndex, 1);
    expect(controller.cachedChapters, {0, 1, 2});

    controller.dispose();
  });
}
