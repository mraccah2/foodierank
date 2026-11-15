// Temporary timing harness: search -> first-screen photos, as the app does it.
import 'dart:io';

import 'package:foodierank/services/restaurant_service.dart';

String ms(Stopwatch s) => '${s.elapsedMilliseconds}ms'.padLeft(7);

Future<void> main(List<String> args) async {
  final lat = double.parse(args[0]), lng = double.parse(args[1]);
  final cuisine = args.length > 2 ? args[2] : null;
  final svc = RestaurantService.instance
    ..warmPhotosDuringSearch = Platform.environment['WARM'] == '1';
  final sw = Stopwatch()..start();

  final places = await svc.getNearbyRestaurants(lat, lng,
      cuisineType: cuisine,
      onSearchUpdate: (n, t, r) =>
          print('${ms(sw)}  round done: $n places @ ${r.round()}m'));
  print('${ms(sw)}  search + locality scores done (${places.length} places) '
      '— list renders here; photos start now');

  // What the app fetches: warmFirstPhotos takes 5, then each visible row asks
  // for its own slot-0 photo (~8 rows on screen), all priority.
  final photoStart = sw.elapsedMilliseconds;
  final visible = places.take(8).toList();
  await Future.wait([
    for (final (i, p) in visible.indexed)
      () async {
        final refs = (p['photoRefs'] as List?) ?? const [];
        if (refs.isEmpty) return;
        final t = Stopwatch()..start();
        final b = await svc.loadPhoto(refs.first as String,
            cacheId: '${p['id']}:0', priority: true);
        print('${ms(sw)}  photo row $i  ${t.elapsedMilliseconds}ms '
            '${b == null ? 'FAILED' : '${b.length ~/ 1024}KB'}');
      }()
  ]);
  print('${ms(sw)}  all visible photos in '
      '(${sw.elapsedMilliseconds - photoStart}ms after the list)');
  exit(0);
}
