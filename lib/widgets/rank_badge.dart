import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// A restaurant's position in the current ranking.
///
/// Two treatments, because rank is doing two different jobs. On a list row it
/// is an index — quiet, at the edge, there when you look for it. On a card face
/// it sits over a photograph and has to survive whatever is underneath it.
///
/// Both used to be the same amber circle, which on a list row read as a
/// notification badge and on a photo read as a sticker.
class RankBadge extends StatelessWidget {
  final int rank;

  /// Filled treatment, for placing over a photograph.
  final bool onPhoto;

  const RankBadge({super.key, required this.rank, this.onPhoto = false});

  const RankBadge.overlay({super.key, required this.rank}) : onPhoto = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!onPhoto) {
      return Text(
        '$rank',
        style: AppTypography.serifAt(
          20,
          weight: FontWeight.w600,
          letterSpacing: -0.5,
        ).copyWith(color: scheme.outline),
        semanticsLabel: 'Ranked number $rank',
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.mapPin,
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        '$rank',
        style: AppTypography.serifAt(
          16,
          weight: FontWeight.w600,
          letterSpacing: -0.2,
        ).copyWith(color: AppColors.onMapPin),
        semanticsLabel: 'Ranked number $rank',
      ),
    );
  }
}
