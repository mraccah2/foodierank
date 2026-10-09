import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/restaurant.dart';
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

  static final Completer<void> _content = Completer<void>();

  /// Completes once the list has something to show: restored results, or the
  /// launch search's first places with the photos of the first screenful — or
  /// once there will be nothing to wait for (no position, a failed search).
  /// The splash holds until then, so the list opens on content instead of a
  /// skeleton. Never throws.
  static Future<void> get ready => _content.future;

  /// Rows on a phone's first screen, whose photos the splash waits for.
  static const int _firstScreenRows = 6;

  /// How long the splash holds for those photos once the places are in. A
  /// photo is decoration; a slow one fills in on the list instead.
  static const Duration _photoWait = Duration(milliseconds: 1500);

  /// Call once, after the disk caches are installed. Nothing here is awaited.
  static void begin() {
    final position = LocationService.instance.current();
    final restored = _restore();
    unawaited(restored.then((cached) {
      if (cached != null) _done();
    }));
    unawaited(_search(restored, position));
  }

  static void _done() {
    if (!_content.isCompleted) _content.complete();
  }

  /// [places] ranked as the list will rank them, then their first photos —
  /// shared with the requests the in-round warm already started — before the
  /// splash lets go.
  static Future<void> _showable(List<Map<String, dynamic>> places) async {
    if (_content.isCompleted) return;
    final firstScreen = places.map(Restaurant.fromJson).toList()
      ..sort((a, b) => b.rankingScore.compareTo(a.rankingScore));
    try {
      await Future.wait([
        for (final r in firstScreen.take(_firstScreenRows))
          if (r.photoRefs.isNotEmpty)
            RestaurantService.instance.loadPhoto(r.photoRefs.first,
                cacheId: '${r.id}:0', priority: true),
      ]).timeout(_photoWait);
    } catch (_) {
      // Slow or failed photos fill in on the list.
    }
    _done();
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
      if (fix == null) return _done();
      final service = RestaurantService.instance;
      if (cached != null &&
          !service.shouldRefreshData(fix.latitude, fix.longitude,
              priceLevels: RestaurantService.allPriceLevels,
              cuisineType: 'All')) {
        return;
      }
      final places = await service.fetchRestaurants(
          fix.latitude, fix.longitude,
          priceLevels: RestaurantService.allPriceLevels,
          cuisineType: 'All',
          onPartialResults: (partial) => unawaited(_showable(partial)));
      await _showable(places);
    } catch (_) {
      // The list screen runs the search itself, and reports, if this did not.
    }
    _done();
  }
}
