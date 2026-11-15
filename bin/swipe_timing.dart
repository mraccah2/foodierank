// Temporary: swipe through a place's photos every 700 ms, with and without
// lookahead, and report how long each photo kept the user waiting.
import 'dart:io';
import 'package:foodierank/services/restaurant_service.dart';

Future<void> main(List<String> args) async {
  final svc = RestaurantService.instance;
  final places = await svc.getNearbyRestaurants(
      double.parse(args[0]), double.parse(args[1]), openNow: false);
  // Two places whose later photos nobody has loaded yet.
  for (final (label, ahead, p) in <(String, int, Map<String, dynamic>)>[
    ('no lookahead (build 51)', 0, places[places.length - 1]),
    ('5 ahead, 1 on open', RestaurantService.photosAheadWhileBrowsing, places[places.length - 2]),
    ('5 ahead, 2 on open', RestaurantService.photosAheadWhileBrowsing, places[places.length - 3]),
  ]) {
    final id = p['id'] as String;
    final refs = (p['photoRefs'] as List).cast<String>();
    print('== $label — ${p['displayName']?['text']}');
    // Card opens on photo 0 (already loaded) with one ahead.
    await svc.loadPhoto(refs[0], cacheId: '$id:0', priority: true);
    if (ahead > 0) svc.prefetchPhotosAhead(id, refs, 0, label.contains('2 on open') ? 2 : 1);
    for (var i = 1; i <= 6 && i < refs.length; i++) {
      await Future.delayed(const Duration(milliseconds: 700)); // looking at photo i-1
      final sw = Stopwatch()..start();
      if (ahead > 0) svc.prefetchPhotosAhead(id, refs, i, ahead);
      await svc.loadPhoto(refs[i], cacheId: '$id:$i');
      print('  swipe to photo ${i + 1}: waited ${sw.elapsedMilliseconds}ms');
    }
  }
  exit(0);
}
