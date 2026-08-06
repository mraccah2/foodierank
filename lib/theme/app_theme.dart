import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_motion.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// The app's two themes, assembled from the tokens.
///
/// Component themes are set here rather than at each call site so that a
/// `Card`, a `FilledButton` or a bottom sheet looks right by default. The
/// widgets are then free of styling arguments, which is what makes a second
/// colour scheme possible at all.
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(AppColors.light());

  static ThemeData dark() => _build(AppColors.dark());

  static ThemeData _build(ColorScheme scheme) {
    final textTheme = AppTypography.build().apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      // Applied to the sans face, so a `Text` with no style still gets it.
      fontFamily: AppTypography.sans,

      // iOS keeps its own transition on purpose: the Cupertino builder is what
      // provides the interactive swipe-to-go-back, and replacing it would take
      // a gesture away rather than add an animation.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: SharedAxisPageTransitionsBuilder(),
          TargetPlatform.fuchsia: SharedAxisPageTransitionsBuilder(),
          TargetPlatform.linux: SharedAxisPageTransitionsBuilder(),
          TargetPlatform.windows: SharedAxisPageTransitionsBuilder(),
        },
      ),

      appBarTheme: AppBarThemeData(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // The header sits on the same paper as the list; a shadow appearing
        // under it on scroll would cut the page in two.
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.serifAt(
          22,
          weight: FontWeight.w600,
          letterSpacing: -0.4,
        ).copyWith(color: scheme.onSurface),
        iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        // A card has to sit visibly *above* the page in both schemes, and the
        // direction of "above" flips: white on sand in light, but a lifted
        // container on near-black in dark, where the lowest tone is the
        // darkest one and a card set to it would sink instead.
        color: scheme.brightness == Brightness.dark
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        selectedColor: scheme.primary,
        disabledColor: scheme.surfaceContainerHigh,
        checkmarkColor: scheme.onPrimary,
        side: BorderSide(color: scheme.outlineVariant),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
        labelStyle: textTheme.labelLarge,
        secondaryLabelStyle:
            textTheme.labelLarge?.copyWith(color: scheme.onPrimary),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        showCheckmark: false,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, AppSpacing.minTouch + 4),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          textStyle: textTheme.labelLarge,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppSpacing.minTouch),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: textTheme.labelLarge,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, AppSpacing.minTouch),
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          minimumSize: const Size(AppSpacing.minTouch, AppSpacing.minTouch),
        ),
      ),

      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surfaceContainer,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: const OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surfaceContainerLow,
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter,
          vertical: AppSpacing.xs,
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle:
            textTheme.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHigh,
        circularTrackColor: Colors.transparent,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: AppRadius.smAll,
        ),
        textStyle:
            textTheme.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),

      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
    );
  }
}
