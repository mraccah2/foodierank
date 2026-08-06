import 'package:flutter/material.dart';

/// A saved-place marker mirrored from the signed-in user's Google Maps data.
///
/// A place can carry more than one of these at once in Google Maps, but
/// FoodieRank only ever renders *one* — the highest-precedence marker present.
/// See [PlaceSaveState.displayStatus].
///
/// Declaration order **is** the precedence order: heart beats star, star beats
/// flag. [PlaceSaveState.displayStatus] relies on that, so do not reorder these
/// without updating it.
enum PlaceStatus {
  /// "Favorites" in Google Maps.
  loved,

  /// "Starred places" in Google Maps. The only marker the Data Portability API
  /// can supply; the other two arrive via a Takeout import.
  starred,

  /// "Want to go" in Google Maps.
  wantToGo,
}

extension PlaceStatusDisplay on PlaceStatus {
  IconData get icon => switch (this) {
        PlaceStatus.loved => Icons.favorite,
        PlaceStatus.starred => Icons.star,
        PlaceStatus.wantToGo => Icons.flag,
      };

  /// The marker's colour for the current scheme.
  ///
  /// These are the app's only colours that carry meaning rather than
  /// hierarchy, so they are named here rather than derived from the theme — but
  /// the light values are all mid-tone, and mid-tone on a near-black card is
  /// the one thing that reads as broken. Hence a pair.
  Color colorFor(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (this) {
      PlaceStatus.loved =>
        dark ? const Color(0xFFFF7B72) : const Color(0xFFE53935),
      // Blue, not yellow: the cards already show an amber star for the
      // Google rating, and two yellow stars would read as one metric.
      PlaceStatus.starred =>
        dark ? const Color(0xFF6BB6FF) : const Color(0xFF1E7BE0),
      PlaceStatus.wantToGo =>
        dark ? const Color(0xFF5FD07F) : const Color(0xFF2E9E4F),
    };
  }

  /// Used for the tap-to-clear semantics label and any undo messaging.
  String get label => switch (this) {
        PlaceStatus.loved => 'Loved',
        PlaceStatus.starred => 'Starred',
        PlaceStatus.wantToGo => 'Want to go',
      };

  /// Stable key for persistence. Deliberately not `name`, so renaming an enum
  /// value can never silently orphan stored data.
  String get storageKey => switch (this) {
        PlaceStatus.loved => 'loved',
        PlaceStatus.starred => 'starred',
        PlaceStatus.wantToGo => 'want_to_go',
      };

  static PlaceStatus? fromStorageKey(String key) => switch (key) {
        'loved' => PlaceStatus.loved,
        'starred' => PlaceStatus.starred,
        'want_to_go' => PlaceStatus.wantToGo,
        _ => null,
      };
}

/// Everything FoodieRank knows about how one place is saved in Google Maps:
/// the markers on it, plus the names of any custom lists it belongs to
/// (e.g. "Iceland trip").
///
/// Lists are tracked separately from [statuses] because they render separately
/// — the marker collapses to a single icon, while list membership is its own
/// indicator.
@immutable
class PlaceSaveState {
  final Set<PlaceStatus> statuses;

  /// Custom Google Maps list names this place appears in.
  final Set<String> lists;

  const PlaceSaveState({
    this.statuses = const {},
    this.lists = const {},
  });

  static const PlaceSaveState empty = PlaceSaveState();

  /// The single marker to render: heart over star over flag. Null when the
  /// place carries no marker (it may still be in a list).
  PlaceStatus? get displayStatus {
    for (final status in PlaceStatus.values) {
      if (statuses.contains(status)) return status;
    }
    return null;
  }

  /// The marker that surfaces once [displayStatus] is cleared — what the user
  /// sees after a tap. Null when this is the last one.
  PlaceStatus? get nextStatus {
    var seenCurrent = false;
    for (final status in PlaceStatus.values) {
      if (!statuses.contains(status)) continue;
      if (seenCurrent) return status;
      seenCurrent = true;
    }
    return null;
  }

  bool get isEmpty => statuses.isEmpty && lists.isEmpty;
  bool get isNotEmpty => !isEmpty;

  PlaceSaveState without(PlaceStatus status) => PlaceSaveState(
        statuses: statuses.where((s) => s != status).toSet(),
        lists: lists,
      );

  PlaceSaveState with_(PlaceStatus status) => PlaceSaveState(
        statuses: {...statuses, status},
        lists: lists,
      );

  Map<String, dynamic> toJson() => {
        'statuses': statuses.map((s) => s.storageKey).toList(),
        'lists': lists.toList(),
      };

  factory PlaceSaveState.fromJson(Map<String, dynamic> json) {
    final rawStatuses = (json['statuses'] as List?) ?? const [];
    final rawLists = (json['lists'] as List?) ?? const [];
    return PlaceSaveState(
      statuses: rawStatuses
          .whereType<String>()
          .map(PlaceStatusDisplay.fromStorageKey)
          .whereType<PlaceStatus>()
          .toSet(),
      lists: rawLists.whereType<String>().toSet(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlaceSaveState &&
      _setEquals(statuses, other.statuses) &&
      _setEquals(lists, other.lists);

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(statuses),
        Object.hashAllUnordered(lists),
      );

  static bool _setEquals<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);
}
