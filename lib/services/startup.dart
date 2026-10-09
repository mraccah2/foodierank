import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'location_service.dart';
import 'restaurant_disk_cache.dart';
import 'restaurant_service.dart';

/// The work a launch needs before it can show restaurants, begun in `main`
/// before the first frame rather than by the screens that wait on it.
///
/// The search used to start only once the splash had restored the last result
/// set and resolved a position, then handed over to the list screen: the
/// splash's whole stay on screen, plus a fade, went by before the first request
/// left the phone. Now the restore, the location fix and the default search all
/// begin at launch. The splash waits on [ready]; the list screen asks
/// [RestaurantService.fetchRestaurants] the same question and joins the search
/// already under way, partial results included.
class Startup {
  const Startup._();

  static Future<void>? _ready;

  /// Completes once there is something to draw from: restored results, or —
  /// without any — a position to search around. Never throws.
  static Future<void> get ready => _ready ?? Future<void>.value();

  /// Call once, after the disk caches are installed. Nothing here is awaited.
  static void begin() {
    final position = LocationService.instance.current();
    final restored = _restore();
    _ready = () async {
      if (await restored == null) await position;
    }();
    unawaited(_search(restored, position));
  }

  static Future<RestaurantSearchSnapshot?> _restore() async {
    final cached = await RestaurantDiskCache.load();
    if (cached != null) RestaurantService.instance.hydrate(cached);
    return cached;
  }

  /// The list screen's default search — near me, open now, no filters — unless
  /// the restored results already answer it. Only that question is asked here:
  /// it is the one a launch shows, and any other would not be joined.
  static Future<void> _search(Future<RestaurantSearchSnapshot?> restored,
      Future<Position?> position) async {
    try {
      final cached = await restored;
      final fix = await position;
      if (fix == null) return;
      final service = RestaurantService.instance;
      if (cached != null &&
          !service.shouldRefreshData(fix.latitude, fix.longitude,
              priceLevels: RestaurantService.allPriceLevels,
              cuisineType: 'All')) {
        return;
      }
      await service.fetchRestaurants(fix.latitude, fix.longitude,
          priceLevels: RestaurantService.allPriceLevels, cuisineType: 'All');
    } catch (_) {
      // The list screen runs the search itself, and reports, if this did not.
    }
  }
}
