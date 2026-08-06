import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// The header controls, as one horizontally scrollable rail.
///
/// There were two centred rows before this: four bordered `ElevatedButton`s
/// above five pills, nine fixed-width controls competing for a phone's width
/// with nowhere to go when they ran out of it. Scrolling is the thing that lets
/// each control be a comfortable size instead of the smallest size that fits.
///
/// Purely presentational — every callback here is the screen's existing handler,
/// unchanged.
class FilterRail extends StatelessWidget {
  final String typeLabel;

  /// Whether a cuisine other than "All" is applied.
  final bool typeIsCustom;
  final VoidCallback onType;

  final String priceLabel;

  /// Whether the price range has been narrowed from the full span.
  final bool priceIsCustom;
  final VoidCallback onPrice;

  final bool sortByRank;
  final VoidCallback onToggleSort;

  final String locationLabel;
  final bool locationIsCustom;
  final VoidCallback onLocation;
  final VoidCallback? onClearLocation;

  final String timeLabel;
  final bool timeIsCustom;
  final VoidCallback onTime;
  final VoidCallback? onClearTime;

  final bool searchActive;
  final VoidCallback onToggleSearch;

  final bool taggedOnly;
  final VoidCallback onToggleTagged;

  final bool mapActive;
  final VoidCallback onToggleMap;

  final bool cardView;
  final VoidCallback onToggleView;

  const FilterRail({
    super.key,
    required this.typeLabel,
    required this.typeIsCustom,
    required this.onType,
    required this.priceLabel,
    required this.priceIsCustom,
    required this.onPrice,
    required this.sortByRank,
    required this.onToggleSort,
    required this.locationLabel,
    required this.locationIsCustom,
    required this.onLocation,
    required this.onClearLocation,
    required this.timeLabel,
    required this.timeIsCustom,
    required this.onTime,
    required this.onClearTime,
    required this.searchActive,
    required this.onToggleSearch,
    required this.taggedOnly,
    required this.onToggleTagged,
    required this.mapActive,
    required this.onToggleMap,
    required this.cardView,
    required this.onToggleView,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _RailChip.height + AppSpacing.sm,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter,
          vertical: AppSpacing.xs,
        ),
        children: [
          _RailIcon(
            icon: Icons.search_rounded,
            tooltip: 'Search by name',
            active: searchActive,
            onTap: onToggleSearch,
          ),
          const _Gap(),

          // Both of these are *always* applied — "Near me" and "Open now" are
          // the defaults, not the absence of a filter — so they read as on from
          // a cold start rather than waiting to be customised. Only a
          // customised one offers a clear.
          _RailChip(
            icon: Icons.place_outlined,
            label: locationLabel,
            selected: true,
            onTap: onLocation,
            onClear: onClearLocation,
          ),
          const _Gap(),
          _RailChip(
            icon: Icons.schedule_rounded,
            label: timeLabel,
            selected: true,
            onTap: onTime,
            onClear: onClearTime,
          ),
          const _Gap(),

          // These three do have an "off" state, so they fill only once they
          // are actually narrowing the results.
          _RailChip(
            label: typeLabel,
            selected: typeIsCustom,
            onTap: onType,
            trailingChevron: true,
          ),
          const _Gap(),
          _RailChip(
            label: priceLabel,
            selected: priceIsCustom,
            onTap: onPrice,
            trailingChevron: true,
          ),
          const _Gap(),

          _RailChip(
            icon: sortByRank
                ? Icons.star_rounded
                : Icons.directions_walk_rounded,
            label: sortByRank ? 'Rank' : 'Distance',
            selected: !sortByRank,
            onTap: onToggleSort,
          ),
          const _Gap(),

          _RailIcon(
            icon: taggedOnly ? Icons.flag_rounded : Icons.flag_outlined,
            tooltip: 'Only saved places',
            active: taggedOnly,
            onTap: onToggleTagged,
          ),
          const _Gap(),
          _RailIcon(
            icon: Icons.map_outlined,
            tooltip: 'Map view',
            active: mapActive,
            onTap: onToggleMap,
          ),
          const _Gap(),
          _RailIcon(
            icon: cardView
                ? Icons.view_list_rounded
                : Icons.crop_portrait_rounded,
            tooltip: cardView ? 'List view' : 'Card view',
            active: false,
            onTap: onToggleView,
          ),
        ],
      ),
    );
  }
}

class _Gap extends StatelessWidget {
  const _Gap();

  @override
  Widget build(BuildContext context) => const SizedBox(width: AppSpacing.sm);
}

/// A labelled control. Selected chips fill with the accent; the rest sit on a
/// tonal surface with a hairline, which is what makes a rail of eight of them
/// read as one row of controls rather than eight outlined boxes.
class _RailChip extends StatelessWidget {
  static const double height = 42;

  final IconData? icon;
  final String label;
  final bool selected;
  final bool trailingChevron;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _RailChip({
    this.icon,
    required this.label,
    this.selected = false,
    this.trailingChevron = false,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final fg = selected ? scheme.onPrimary : scheme.onSurface;
    final bg = selected ? scheme.primary : scheme.surfaceContainer;

    return Material(
      color: bg,
      borderRadius: AppRadius.pillAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.pillAll,
        child: Container(
          height: height,
          padding: EdgeInsets.only(
            left: AppSpacing.lg - (icon != null ? 4 : 0),
            right: onClear != null ? AppSpacing.sm : AppSpacing.lg,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.pillAll,
            border: Border.all(
              color: selected ? Colors.transparent : scheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: AppSpacing.sm - 2),
              ],
              ConstrainedBox(
                // Long picked-place names truncate rather than pushing the rest
                // of the rail off the end.
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(color: fg),
                ),
              ),
              if (trailingChevron) ...[
                const SizedBox(width: AppSpacing.xs),
                Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: fg),
              ],
              if (onClear != null)
                // Its own recogniser, deeper in the tree, so clearing wins the
                // gesture arena instead of also opening the picker.
                GestureDetector(
                  onTap: onClear,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.xs,
                      right: AppSpacing.xs,
                    ),
                    child: Icon(Icons.close_rounded, size: 18, color: fg),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A square icon toggle, sized to sit flush with [_RailChip].
class _RailIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  const _RailIcon({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = active ? scheme.onPrimary : scheme.onSurface;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? scheme.primary : scheme.surfaceContainer,
        borderRadius: AppRadius.pillAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.pillAll,
          child: Container(
            width: _RailChip.height,
            height: _RailChip.height,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: active ? Colors.transparent : scheme.outlineVariant,
              ),
            ),
            child: Icon(icon, size: 20, color: fg),
          ),
        ),
      ),
    );
  }
}
