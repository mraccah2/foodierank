import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'shimmer.dart';

/// What the list looks like while the first search is in flight.
///
/// A screenful of the shape that is coming, rather than a single spinner in the
/// middle of an empty page. It costs nothing extra: every box here shares the
/// one [ShimmerDriver] ticker the photo placeholders already use.
class RestaurantListSkeleton extends StatelessWidget {
  /// Optional progress text from the search, shown under the rows.
  final String? status;

  const RestaurantListSkeleton({super.key, this.status});

  static const int _rows = 7;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: _rows + (status == null ? 0 : 1),
      separatorBuilder: (_, __) => const Divider(
        indent: AppSpacing.gutter,
        endIndent: AppSpacing.gutter,
      ),
      itemBuilder: (context, index) {
        if (index >= _rows) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              AppSpacing.xl,
              AppSpacing.xxl,
              AppSpacing.sm,
            ),
            child: Text(
              status!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return const _SkeletonRow();
      },
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: AppRadius.mdAll,
            child: const ShimmerBox(width: 80, height: 80),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.xs),
                ClipRRect(
                  borderRadius: AppRadius.smAll,
                  child: const ShimmerBox(width: 170, height: 15),
                ),
                const SizedBox(height: AppSpacing.md),
                ClipRRect(
                  borderRadius: AppRadius.smAll,
                  child: const ShimmerBox(width: 220, height: 11),
                ),
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: AppRadius.smAll,
                  child: const ShimmerBox(width: 120, height: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
