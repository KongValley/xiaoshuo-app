import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'theme.dart';

/// Stands in for a part of the interface that failed to build. In release
/// builds Flutter would otherwise show a blank grey rectangle with no hint
/// that anything went wrong.
class ErrorPane extends StatelessWidget {
  const ErrorPane({super.key, this.detail});

  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sentiment_dissatisfied_rounded,
              size: 36,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              '这里出了点问题',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '返回上一页再试一次，通常就能恢复。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (detail != null && detail!.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                detail!,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The whole app when the library cannot be initialised. Without it a startup
/// failure leaves a blank window and no way to tell what happened.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '墨读',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: StartupErrorPage(error: error),
    );
  }
}

class StartupErrorPage extends StatelessWidget {
  const StartupErrorPage({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.extension<AppSurface>()!;
    final detail = error.toString();

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '书库无法打开',
                  style: AppTheme.serif(
                    26,
                    color: theme.colorScheme.onSurface,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '应用没能初始化自己的数据目录，所以这次没有启动。\n'
                  '书籍和阅读进度仍然保存在设备上，多半不会丢失。'
                  '请检查剩余存储空间，或卸载后重新安装，再试一次。',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.8,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  '错误信息',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    color: surface.muted,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: surface.tint.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: surface.hairline),
                  ),
                  child: SelectionArea(
                    child: Text(
                      detail,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: theme.colorScheme.onSurface,
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
}
