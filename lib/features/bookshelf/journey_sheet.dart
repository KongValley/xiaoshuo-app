import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/seal_badges.dart';
import '../../core/theme.dart';
import '../../data/models/reading_stats.dart';
import '../../data/stats_repository.dart';

/// Modal gallery displaying daily reading ring, streak, stats, and interactive
/// chop-seal achievements.
class ReadingJourneySheet extends StatefulWidget {
  const ReadingJourneySheet({
    super.key,
    required this.statsRepo,
    this.asDialog = false,
  });

  final StatsRepository statsRepo;
  final bool asDialog;

  @override
  State<ReadingJourneySheet> createState() => _ReadingJourneySheetState();
}

class _ReadingJourneySheetState extends State<ReadingJourneySheet> {
  StampId _selectedStamp = StampId.firstOpen;

  @override
  void initState() {
    super.initState();
    final stats = widget.statsRepo.stats;
    for (final s in StampId.values) {
      if (stats.isUnlocked(s)) {
        _selectedStamp = s;
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.extension<AppSurface>()!;

    return AnimatedBuilder(
      animation: widget.statsRepo,
      builder: (context, _) {
        final stats = widget.statsRepo.stats;
        final todaySeconds = widget.statsRepo.todayReadingSeconds;
        final goalProgress = widget.statsRepo.todayGoalProgress;
        final unlockedCount =
            StampId.values.where((s) => stats.isUnlocked(s)).length;
        final maxSheetHeight =
            math.min(720.0, MediaQuery.sizeOf(context).height * 0.86);

        return Material(
          color: surface.card,
          elevation: widget.asDialog ? 16 : 0,
          shadowColor: Colors.black.withValues(alpha: 0.22),
          borderRadius: widget.asDialog
              ? BorderRadius.circular(24)
              : const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: widget.asDialog ? null : maxSheetHeight,
            child: Column(
              mainAxisSize: widget.asDialog ? MainAxisSize.min : MainAxisSize.max,
              children: [
                if (!widget.asDialog) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: surface.muted.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    widget.asDialog ? 18 : 14,
                    10,
                    10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '拾卷印记',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.serif(
                                22,
                                color: theme.colorScheme.onSurface,
                                letterSpacing: 0.8,
                              ),
                            ),
                            Text(
                              '已集 $unlockedCount / ${StampId.values.length} 枚朱砂印记',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: surface.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<int>(
                        tooltip: '调整每日阅读目标',
                        initialValue: stats.dailyGoalMinutes,
                        color: theme.colorScheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        onSelected: widget.statsRepo.updateDailyGoalMinutes,
                        itemBuilder: (context) => [
                          for (final mins in const [10, 20, 30, 45, 60])
                            PopupMenuItem<int>(
                              value: mins,
                              child: Row(
                                children: [
                                  Text(
                                    '每日 $mins 分钟',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  const Spacer(),
                                  if (mins == stats.dailyGoalMinutes)
                                    Icon(
                                      Icons.check_rounded,
                                      size: 16,
                                      color: theme.colorScheme.primary,
                                    ),
                                ],
                              ),
                            ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: surface.tint.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: surface.hairline),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.flag_outlined,
                                size: 14,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '目标 ${stats.dailyGoalMinutes} 分',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: '关闭',
                        icon: Icon(Icons.close_rounded, color: surface.muted),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: surface.hairline),
                Flexible(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final twoPane = constraints.maxWidth >= 620;
                      final summaryCard = _DailySummaryCard(
                        todaySeconds: todaySeconds,
                        goalMinutes: stats.dailyGoalMinutes,
                        goalProgress: goalProgress,
                        stats: stats,
                        theme: theme,
                        surface: surface,
                      );
                      final detailPanel = _StampDetailPanel(
                        stamp: _selectedStamp,
                        stats: stats,
                        theme: theme,
                        surface: surface,
                      );
                      final wallHeader = Row(
                        children: [
                          Text(
                            '朱砂印章墙',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: surface.muted,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                '轻点印章可赏玩落印',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: surface.muted.withValues(alpha: 0.8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );

                      Widget buildGrid(double gridWidth) {
                        final cols = gridWidth < 290 ? 3 : 4;
                        final sealSize = gridWidth < 340 ? 42.0 : 50.0;
                        final ratio = gridWidth < 340 ? 0.78 : 0.86;
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: StampId.values.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 10,
                            childAspectRatio: ratio,
                          ),
                          itemBuilder: (context, index) {
                            final stamp = StampId.values[index];
                            final unlocked = stats.isUnlocked(stamp);
                            final selected = stamp == _selectedStamp;
                            return InkWell(
                              onTap: () =>
                                  setState(() => _selectedStamp = stamp),
                              borderRadius: BorderRadius.circular(14),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? surface.tint.withValues(alpha: 0.72)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: selected
                                        ? theme.colorScheme.primary
                                            .withValues(alpha: 0.45)
                                        : Colors.transparent,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SealStampBadge(
                                      stamp: stamp,
                                      unlocked: unlocked,
                                      size: sealSize,
                                      interactive: true,
                                      onTap: () => setState(
                                        () => _selectedStamp = stamp,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      stamp.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: unlocked
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: unlocked
                                            ? theme.colorScheme.onSurface
                                            : surface.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      }

                      if (twoPane) {
                        final rightWidth = (constraints.maxWidth - 64) * 0.52;
                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                child: Column(
                                  children: [
                                    summaryCard,
                                    const SizedBox(height: 14),
                                    detailPanel,
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                flex: 6,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    wallHeader,
                                    const SizedBox(height: 12),
                                    buildGrid(rightWidth),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            summaryCard,
                            const SizedBox(height: 18),
                            wallHeader,
                            const SizedBox(height: 12),
                            buildGrid(constraints.maxWidth - 40),
                            const SizedBox(height: 16),
                            detailPanel,
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DailySummaryCard extends StatelessWidget {
  const _DailySummaryCard({
    required this.todaySeconds,
    required this.goalMinutes,
    required this.goalProgress,
    required this.stats,
    required this.theme,
    required this.surface,
  });

  final int todaySeconds;
  final int goalMinutes;
  final double goalProgress;
  final ReadingStats stats;
  final ThemeData theme;
  final AppSurface surface;

  @override
  Widget build(BuildContext context) {
    final todayMins = todaySeconds ~/ 60;
    final goalReached = goalProgress >= 1.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surface.tint.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: surface.hairline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 82,
                height: 82,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 78,
                      height: 78,
                      child: CircularProgressIndicator(
                        value: goalProgress,
                        strokeWidth: 6.5,
                        strokeCap: StrokeCap.round,
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: 0.12),
                        color: goalReached
                            ? surface.seal
                            : theme.colorScheme.primary,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$todayMins',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '分钟',
                          style: TextStyle(fontSize: 10, color: surface.muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: goalReached
                                ? surface.sealSoft
                                : theme.colorScheme.primary
                                    .withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            goalReached ? '今日目标已达成' : '今日阅读进行中',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: goalReached
                                  ? surface.seal
                                  : theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      stats.streakDays > 0
                          ? '已连续拾卷 ${stats.streakDays} 天'
                          : '今日展卷，开启你的阅读连击',
                      style: AppTheme.serif(
                        17,
                        color: theme.colorScheme.onSurface,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '目标每日 $goalMinutes 分钟 · 最长连续 ${stats.bestStreakDays} 天',
                      style: TextStyle(fontSize: 11.5, color: surface.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: surface.hairline),
          const SizedBox(height: 14),
          Row(
            children: [
              _MetricCell(
                label: '累计时长',
                value: Fmt.readingDuration(stats.totalReadingSeconds),
                theme: theme,
                surface: surface,
              ),
              _MetricCell(
                label: '翻阅页数',
                value: '${Fmt.number(stats.totalPagesTurned)} 页',
                theme: theme,
                surface: surface,
              ),
              _MetricCell(
                label: '读完章节',
                value: '${Fmt.number(stats.totalChaptersFinished)} 章',
                theme: theme,
                surface: surface,
              ),
              _MetricCell(
                label: '圆满合卷',
                value: '${stats.finishedBookIds.length} 本',
                theme: theme,
                surface: surface,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.label,
    required this.value,
    required this.theme,
    required this.surface,
  });

  final String label;
  final String value;
  final ThemeData theme;
  final AppSurface surface;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(fontSize: 10.5, color: surface.muted),
          ),
        ],
      ),
    );
  }
}

class _StampDetailPanel extends StatelessWidget {
  const _StampDetailPanel({
    required this.stamp,
    required this.stats,
    required this.theme,
    required this.surface,
  });

  final StampId stamp;
  final ReadingStats stats;
  final ThemeData theme;
  final AppSurface surface;

  @override
  Widget build(BuildContext context) {
    final unlocked = stats.isUnlocked(stamp);
    final rawDate = stats.unlockedStamps[stamp.name];
    final parsedDate = rawDate != null ? DateTime.tryParse(rawDate) : null;
    final progress = stats.progressValueFor(stamp);
    final fraction = (progress / stamp.target).clamp(0.0, 1.0);

    String progressLabel() {
      if (unlocked) {
        return parsedDate != null
            ? '落印于 ${Fmt.date(parsedDate)}'
            : '已落印';
      }
      if (stamp == StampId.session15m) {
        return '单次最长 ${Fmt.readingDuration(progress)} / 15 分钟';
      }
      if (stamp == StampId.chars5w) {
        return '${Fmt.charCount(progress)} / 5 万字';
      }
      if (stamp.target == 1) return '待达成';
      return '当前进度：$progress / ${stamp.target}';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface.elevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: unlocked
              ? stamp.accent.withValues(alpha: 0.35)
              : surface.hairline,
        ),
      ),
      child: Row(
        children: [
          SealStampBadge(
            stamp: stamp,
            unlocked: unlocked,
            size: 56,
            interactive: true,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      stamp.title,
                      style: AppTheme.serif(
                        17,
                        color: theme.colorScheme.onSurface,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: unlocked
                            ? stamp.accent.withValues(alpha: 0.14)
                            : surface.tint,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        unlocked ? '已获印' : '未解锁',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: unlocked ? stamp.accent : surface.muted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  stamp.subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${stamp.requirement} · ${progressLabel()}',
                  style: TextStyle(fontSize: 11, color: surface.muted),
                ),
                if (!unlocked && stamp.target > 1) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 3,
                      backgroundColor:
                          theme.colorScheme.primary.withValues(alpha: 0.10),
                      color: stamp.accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
