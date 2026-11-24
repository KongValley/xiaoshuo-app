import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Material-inspired adaptive size buckets shared by phone, tablet, and desktop layouts.
enum AppSizeClass {
  /// Narrow phone portrait & split-screen panes (< 600dp).
  compact,

  /// Large foldables, portrait tablets, and compact landscape panes (600..919dp).
  medium,

  /// Landscape tablets and desktop windows (>= 920dp).
  expanded,
}

/// Immutable adaptive layout metrics computed from current window dimensions.
class AppAdaptive {
  const AppAdaptive._(this.size);

  factory AppAdaptive.of(BuildContext context) =>
      AppAdaptive._(MediaQuery.sizeOf(context));

  factory AppAdaptive.fromSize(Size size) => AppAdaptive._(size);

  final Size size;

  double get width => size.width;
  double get height => size.height;
  bool get isLandscape => width > height;

  AppSizeClass get sizeClass {
    if (width < 600) return AppSizeClass.compact;
    if (width < 920) return AppSizeClass.medium;
    return AppSizeClass.expanded;
  }

  bool get isCompact => sizeClass == AppSizeClass.compact;
  bool get isMedium => sizeClass == AppSizeClass.medium;
  bool get isExpanded => sizeClass == AppSizeClass.expanded;
  bool get isTabletOrLarger => width >= 600;
  bool get showSplitShelfHero => width >= 840;
  bool get useTwoColumnShelfList => width >= 760;

  /// Horizontal screen gutter that adapts smoothly across screen sizes.
  double get pagePadding {
    if (width < 380) return 16;
    if (width < 600) return 20;
    if (width < 920) return 26;
    return 32;
  }

  double get gridGap {
    if (width < 460) return 14;
    if (width < 720) return 18;
    return 22;
  }

  double get gridMainGap => width < 600 ? 20 : 26;

  double get shelfGridAspectRatio => width < 600 ? 0.64 : 0.62;

  static const double shelfMaxWidth = 1180;

  int shelfGridColumns(double contentWidth) {
    if (contentWidth < 460) return 2;
    if (contentWidth < 680) return 3;
    if (contentWidth < 940) return 4;
    if (contentWidth < 1140) return 5;
    return 6;
  }
}

/// How adaptive modal panels appear on larger screens while falling back to bottom sheets on phones.
enum AdaptivePanelPlacement {
  bottomOrCenteredDialog,
  bottomOrEndDrawer,
}

/// Presents a modal sheet on compact screens or a centered dialog / right drawer on tablet & desktop.
Future<T?> showAdaptivePanel<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  AdaptivePanelPlacement placement =
      AdaptivePanelPlacement.bottomOrCenteredDialog,
  double maxDialogWidth = 720,
  double maxDialogHeight = 680,
  double drawerWidth = 420,
  Color? barrierColor,
  String barrierLabel = '关闭面板',
}) {
  final size = MediaQuery.sizeOf(context);
  final useBottomSheet = switch (placement) {
    AdaptivePanelPlacement.bottomOrCenteredDialog => size.width < 600,
    AdaptivePanelPlacement.bottomOrEndDrawer => size.width < 700,
  };

  final resolvedBarrier =
      barrierColor ?? Colors.black.withValues(alpha: 0.28);

  if (useBottomSheet) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 680),
      barrierColor: resolvedBarrier,
      builder: builder,
    );
  }

  if (placement == AdaptivePanelPlacement.bottomOrEndDrawer) {
    final panelWidth = math.min(drawerWidth, size.width * 0.52);
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: barrierLabel,
      barrierColor: resolvedBarrier,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 10),
              child: SizedBox(
                width: panelWidth,
                height: double.infinity,
                child: builder(dialogContext),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.14, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  final width = math.min(maxDialogWidth, size.width - 48);
  final height = math.min(maxDialogHeight, size.height * 0.88);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: barrierLabel,
    barrierColor: resolvedBarrier,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: width,
              maxHeight: height,
            ),
            child: builder(dialogContext),
          ),
        ),
      );
    },
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.965, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}
