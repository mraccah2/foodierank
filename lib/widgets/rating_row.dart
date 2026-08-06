import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// The Google rating: one filled star, the score, and the review count.
///
/// This replaces a `List.generate(5, …)` that drew five icons and quantised the
/// score into whole, half and empty stars — five glyphs to convey what "4.6"
/// already says exactly, and at list-row size the half-star was
/// indistinguishable from a full one anyway.
class RatingRow extends StatelessWidget {
  final double rating;
  final int reviewCount;
  final double iconSize;
  final TextStyle? style;

  /// Drops the review count, for rows too narrow to carry it.
  final bool compact;

  const RatingRow({
    super.key,
    required this.rating,
    required this.reviewCount,
    this.iconSize = 16,
    this.style,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = style ?? theme.textTheme.bodySmall;
    final starColor = AppColors.ratingStar(theme.brightness);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: iconSize, color: starColor),
        const SizedBox(width: AppSpacing.xs),
        Text(rating.toStringAsFixed(1), style: textStyle),
        if (!compact) ...[
          const SizedBox(width: AppSpacing.xs),
          Text(
            '(${_formatCount(reviewCount)})',
            style: textStyle?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  /// Four-plus digits of review count is noise at this size; a place with 1,204
  /// reviews and one with 1,207 are telling you the same thing.
  static String _formatCount(int count) {
    if (count < 1000) return '$count';
    final thousands = count / 1000;
    return thousands >= 10
        ? '${thousands.round()}k'
        : '${thousands.toStringAsFixed(1)}k';
  }
}
