// Temporary: where a search's time goes, from a cold process.
import 'dart:io';
import 'package:foodierank/services/restaurant_service.dart';

String ms(Stopwatch s) => '${s.elapsedMilliseconds}ms'.padLeft(7);

Future<void> main(List<String> args) async {
  final lat = double.parse(args[0]), lng = double.parse(args[1]);
  for (final run in ['cold process']) {
    final sw = Stopwatch()..start();
    final places = await RestaurantService.instance.getNearbyRestaurants(lat, lng,
        onSearchUpdate: (n, t, r) => print('${ms(sw)}  round @ ${r.round()}m: $n places'),
        onPartialResults: (p) => print('${ms(sw)}  FIRST CONTENT possible: ${p.length} places'));
    print('${ms(sw)}  done (${places.length}) [$run]');
  }
  exit(0);
}
