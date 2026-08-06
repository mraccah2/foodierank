import 'package:flutter/material.dart';

import '../models/restaurant.dart';
import '../theme/app_spacing.dart';
import 'place_photo.dart';
import 'place_status_icon.dart';
import 'rank_badge.dart';
import 'rating_row.dart';
import 'tonal_chip.dart';

/// One restaurant, as a row in the default list.
///
/// This was a floating `Card(elevation: 2)` with a 36pt amber circle leading it
/// and a 60pt thumbnail trailing it. Three changes: the photograph comes first,
/// because that is what the eye is scanning for in a list of restaurants; the
/// rank stops being a badge and becomes a numeral; and the row sits directly on
/// the page, separated by a hairline, rather than floating on it.
class MinimalRestaurantCard extends StatelessWidget {
  final Restaurant restaurant;
  final int ranking;
  final double? currentLat;
  final double? currentLng;
  final VoidCallback onTap;

  const MinimalRestaurantCard({
    super.key,
    required this.restaurant,
    required this.ranking,
    this.currentLat,
    this.currentLng,
    required this.onTap,
  });

  static const double _thumb = 80;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    String distance = '';
    if (currentLat != null && currentLng != null) {
      distance = restaurant.location.formatDistance(currentLat!, currentLng!);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.gutter,
            vertical: AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (restaurant.photoRefs.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: AppRadius.mdAll,
                  child: PlacePhoto(
                    photoRef: restaurant.photoRefs.first,
                    width: _thumb,
                    height: _thumb,
                    // The only photo a list row shows.
                    priority: true,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Name, with the Google Maps save marker alongside it. It
                    // sits here rather than in the metadata row below so its
                    // yellow star is never confused with the rating star.
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            restaurant.name,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        PlaceStatusIcon(placeId: restaurant.placeId, size: 16),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs + 2),

                    // Rating, price and distance on one line — all short, all
                    // numeric, and read together rather than one at a time.
                    Row(
                      children: [
                        RatingRow(
                          rating: restaurant.rating,
                          reviewCount: restaurant.reviewCount,
                          iconSize: 15,
                          style: theme.textTheme.bodySmall,
                        ),
                        if (restaurant.priceLevel.isNotEmpty) ...[
                          const MetaDot(),
                          Text(
                            restaurant.priceLevel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (distance.isNotEmpty) ...[
                          const MetaDot(),
                          Flexible(
                            child: Text(
                              distance,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    if (restaurant.cuisineLabel != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      TonalChip(label: restaurant.cuisineLabel!, dense: true),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: RankBadge(rank: ranking),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
