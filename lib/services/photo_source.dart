import 'dart:typed_data';

/// The slice of [RestaurantService] that photo widgets actually use.
///
/// It exists so `PlacePhoto` can be driven by a fake in tests. The widget used
/// to reach for the singleton directly, which meant the seam between "the
/// bytes arrived" and "the widget showed them" — where a self-awaiting future
/// once stranded every photo on screen — could not be tested at all.
///
/// Pure Dart, like the service that implements it, so `bin/foodierank.dart`
/// still loads without Flutter.
abstract class PhotoSource {
  /// Bytes already in memory, or null. Must not start a fetch: callers use it
  /// during `build`.
  ///
  /// [cacheId] is the stable identity of the picture — see [loadPhoto].
  Uint8List? getCachedPhoto(String photoRef, {String? cacheId});

  /// Bytes for [photoRef], fetching if needed.
  ///
  /// [photoRef] is the Places photo resource name, which is what the fetch
  /// needs — but **Google mints a fresh one on every search response**, so it
  /// is useless as a cache key. Two `places:searchText` calls seconds apart for
  /// the same restaurant return the same place id and the same ten photos under
  /// entirely different `photos[i].name` values. Keying the caches on it gave a
  /// disk tier that could never hit across searches: every filter tap
  /// re-downloaded all twenty pictures at $7 per thousand.
  ///
  /// [cacheId] is the stable identity to remember the bytes under —
  /// `'<placeId>:<photoIndex>'`, both of which outlive any single response.
  /// Null falls back to [photoRef], which is right for callers that have no
  /// place context (and for `bin/foodierank.dart`, which has no disk tier).
  ///
  /// Must always complete. A future that hangs, or completes with an error,
  /// leaves a placeholder on screen with nothing to go on.
  Future<Uint8List?> loadPhoto(
    String photoRef, {
    String? cacheId,
    int maxWidth,
    int maxHeight,
    bool priority,
  });
}
