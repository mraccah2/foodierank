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
  Uint8List? getCachedPhoto(String photoRef);

  /// Bytes for [photoRef], fetching if needed.
  ///
  /// Must always complete. A future that hangs, or completes with an error,
  /// leaves a placeholder on screen with nothing to go on.
  Future<Uint8List?> loadPhoto(
    String photoRef, {
    int maxWidth,
    int maxHeight,
    bool priority,
  });
}
