import 'package:flutter/material.dart';

import '../models/place_status.dart';
import '../services/place_status_store.dart';

/// Shows how a place is saved in the signed-in user's Google Maps account.
///
/// Two independent indicators sit side by side:
///
///  * **The marker** — heart, star or flag, collapsed to a *single* icon by
///    [PlaceSaveState.displayStatus] precedence. Tapping it clears that marker;
///    if the place carries a lower-precedence one, that becomes visible.
///  * **List membership** — a bookmark for places in a custom list such as
///    "Iceland trip". Not tappable: lists are membership, not a marker.
///
/// Renders nothing at all when signed out, or when the place is unsaved.
class PlaceStatusIcon extends StatelessWidget {
  final String placeId;

  /// Defaults to the app-wide [placeStatusStore]; injectable for tests.
  final PlaceStatusStore? store;

  /// Icon size in logical pixels. The tap target is padded out to at least
  /// 40dp regardless, so this can go small on dense list rows.
  final double size;

  /// When true, custom list names render beside the bookmark. Card layouts
  /// have the width for this; compact list rows do not.
  final bool showListLabel;

  /// Whether an unmarked place offers the "want to go" shortcut.
  final bool allowAdding;

  const PlaceStatusIcon({
    super.key,
    required this.placeId,
    this.store,
    this.size = 20,
    this.showListLabel = false,
    this.allowAdding = true,
  });

  @override
  Widget build(BuildContext context) {
    final store = this.store ?? placeStatusStore;
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        // Signed out there is nowhere to keep a mark, so offer nothing.
        if (!store.isAvailable) return const SizedBox.shrink();

        final state = store.stateFor(placeId);
        final status = state.displayStatus;

        if (state.isEmpty) {
          return allowAdding
              ? _buildAddAffordance(context, store)
              : const SizedBox.shrink();
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status != null) _buildMarker(context, store, status, state),
            if (state.lists.isNotEmpty) _buildListIndicator(context, state),
          ],
        );
      },
    );
  }

  /// A muted outline flag on unmarked places, so a spot noticed in the
  /// rankings can be saved for later without leaving the list.
  ///
  /// Deliberately low-contrast: it appears on every unmarked card, and should
  /// read as an available action rather than as a marker the place already has.
  Widget _buildAddAffordance(BuildContext context, PlaceStatusStore store) {
    return Semantics(
      button: true,
      label: 'Save as want to go',
      child: InkResponse(
        onTap: () => store.addStatus(placeId, PlaceStatus.wantToGo),
        radius: size,
        containedInkWell: false,
        child: Padding(
          padding: EdgeInsets.all((40 - size).clamp(0, 12) / 2),
          child: Icon(
            Icons.outlined_flag,
            size: size,
            color: Colors.grey.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }

  Widget _buildMarker(
    BuildContext context,
    PlaceStatusStore store,
    PlaceStatus status,
    PlaceSaveState state,
  ) {
    final next = state.nextStatus;
    final hint = next == null
        ? 'Remove ${status.label.toLowerCase()}'
        : 'Remove ${status.label.toLowerCase()}, revealing '
            '${next.label.toLowerCase()}';

    return Semantics(
      button: true,
      label: status.label,
      hint: hint,
      child: InkResponse(
        onTap: () => store.clearTopStatus(placeId),
        radius: size,
        containedInkWell: false,
        child: Padding(
          // Keeps the tap target comfortable even at small icon sizes.
          padding: EdgeInsets.all((40 - size).clamp(0, 12) / 2),
          child: Icon(
            status.icon,
            size: size,
            color: status.color,
          ),
        ),
      ),
    );
  }

  Widget _buildListIndicator(BuildContext context, PlaceSaveState state) {
    final names = state.lists.toList()..sort();
    final tooltip = names.length == 1
        ? 'In list "${names.first}"'
        : 'In lists: ${names.join(", ")}';

    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark,
              size: size * 0.9,
              color: Colors.blueGrey[600],
            ),
            if (showListLabel) ...[
              const SizedBox(width: 3),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  names.first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: size * 0.6,
                    color: Colors.blueGrey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // Extra lists collapse to a count rather than wrapping the row.
              if (names.length > 1)
                Text(
                  ' +${names.length - 1}',
                  style: TextStyle(
                    fontSize: size * 0.6,
                    color: Colors.blueGrey[500],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
