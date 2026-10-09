import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// The three ways the results can be shown. They are peers, not a hierarchy.
enum ViewMode { card, list, map }

/// The header controls, as one horizontally scrollable rail.
///
/// There were two centred rows before this: four bordered `ElevatedButton`s
/// above five pills, nine fixed-width controls competing for a phone's width
/// with nowhere to go when they ran out of it. Scrolling is the thing that lets
/// each control be a comfortable size instead of the smallest size that fits.
///
/// Search and the view switcher sit together, pinned at the leading edge; only
/// the filter chips after them scroll. They used to scroll too, which meant the
/// two controls you reach for most were the ones most often off-screen.
///
/// Purely presentational — every callback here is the screen's own handler.
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

  final ViewMode view;
  final ValueChanged<ViewMode> onSelectView;

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
    required this.view,
    required this.onSelectView,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _RailChip.height + AppSpacing.sm,
      child: Row(
        children: [
          const SizedBox(width: AppSpacing.gutter),
          _PinnedTray(
            searchActive: searchActive,
            onToggleSearch: onToggleSearch,
            view: view,
            onSelectView: onSelectView,
          ),
          Expanded(
            child: _EdgeFade(
              child: ListView(
                scrollDirection: Axis.horizontal,
                // The chips run to the screen edge, so the last one gets the
                // gutter inside the scroll rather than a wall outside it.
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.xs,
                  AppSpacing.gutter,
                  AppSpacing.xs,
                ),
                children: [
                  // Both of these are *always* applied — "Near me" and "Open
                  // now" are the defaults, not the absence of a filter — so
                  // they read as on from a cold start rather than waiting to be
                  // customised. Only a customised one offers a clear.
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

                  // These three do have an "off" state, so they fill only once
                  // they are actually narrowing the results.
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades the scrolling chips out at both ends, so they visibly slide under the
/// pinned controls instead of being cut off by an invisible wall.
class _EdgeFade extends StatelessWidget {
  final Widget child;

  const _EdgeFade({required this.child});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        // A fixed 12pt fade, whatever width the chips end up with.
        final stop =
            bounds.width == 0 ? 0.0 : (12 / bounds.width).clamp(0, 0.5);
        return LinearGradient(
          colors: const [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0, stop.toDouble(), 1 - stop.toDouble(), 1],
        ).createShader(bounds);
      },
      child: child,
    );
  }
}

/// The list / card / map switcher and search, as one pinned tray.
///
/// The tray sits a tone deeper than the chips and has no hairline of its own,
/// so it reads as a fixed part of the header rather than as two more filters —
/// the chips slide under it, it never moves.
///
/// The views were once a toggle whose icon showed the view you would switch
/// *to*, plus a separate map button, so nothing on screen said which view you
/// were in. Here the filled segment is the current view, and every view is one
/// tap away.
class _PinnedTray extends StatelessWidget {
  static const double _segment = 36;
  static const double _inset = 3;

  static const _views = [
    (ViewMode.list, Icons.view_list_rounded, 'List view'),
    (ViewMode.card, Icons.crop_portrait_rounded, 'Cards view'),
    (ViewMode.map, Icons.map_outlined, 'Map view'),
  ];

  final bool searchActive;
  final VoidCallback onToggleSearch;
  final ViewMode view;
  final ValueChanged<ViewMode> onSelectView;

  const _PinnedTray({
    required this.searchActive,
    required this.onToggleSearch,
    required this.view,
    required this.onSelectView,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final index = _views.indexWhere((v) => v.$1 == view);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final motion =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);

    return Container(
      height: _RailChip.height,
      padding: const EdgeInsets.all(_inset),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: _segment * _views.length,
            child: Stack(
              children: [
                // The selection slides to the tapped view — it shows what
                // changed.
                AnimatedPositioned(
                  duration: motion,
                  curve: Curves.easeOutCubic,
                  left: _segment * index,
                  top: 0,
                  bottom: 0,
                  width: _segment,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: AppRadius.pillAll,
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final (mode, icon, label) in _views)
                      _TraySegment(
                        icon: icon,
                        label: label,
                        selected: mode == view,
                        width: _segment,
                        onTap: mode == view ? null : () => onSelectView(mode),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: _segment - 16,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            color: scheme.outline.withValues(alpha: 0.35),
          ),
          // Search is a switch of its own, not one of the views, so it fills
          // in place rather than taking the sliding selection.
          AnimatedContainer(
            duration: motion,
            decoration: BoxDecoration(
              color: searchActive ? scheme.primary : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: _TraySegment(
              icon: Icons.search_rounded,
              label: 'Search by name',
              selected: searchActive,
              width: _segment,
              // Tapping again closes it, so it stays tappable while on.
              onTap: onToggleSearch,
            ),
          ),
        ],
      ),
    );
  }
}

class _TraySegment extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final double width;
  final VoidCallback? onTap;

  const _TraySegment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: SizedBox(
            width: width,
            height: double.infinity,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: Icon(
                icon,
                key: ValueKey(selected),
                size: 19,
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
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
