import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A small, non-interactive label — a cuisine, a price band.
///
/// Replaces the `Container` + `BoxDecoration` pair that appeared in both cards
/// with `Colors.blue.withValues(alpha: 0.1)` hardcoded into it, which in dark
/// mode would have been a navy smear behind grey text.
class TonalChip extends StatelessWidget {
  final String label;

  /// Tighter padding and a smaller face, for dense list rows.
  final bool dense;

  const TonalChip({super.key, required this.label, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.sm : AppSpacing.md,
        vertical: dense ? AppSpacing.xxs : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        label,
        style: (dense ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)
            ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// A `·` separator sized to sit between metadata fragments on one line.
class MetaDot extends StatelessWidget {
  const MetaDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm - 2),
      child: Text(
        '·',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
      ),
    );
  }
}
