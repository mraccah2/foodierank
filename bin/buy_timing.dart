// Temporary: time the gateway's `photo` op on photos nobody has bought yet.
import 'dart:io';
import 'package:foodierank/services/proxy_service.dart';
import 'package:foodierank/services/restaurant_service.dart';

Future<void> main(List<String> args) async {
  final places = await RestaurantService.instance.getNearbyRestaurants(
      double.parse(args[0]), double.parse(args[1]), openNow: false);
  final times = <int>[];
  for (final p in places) {
    if (times.length >= 8) break;
    final id = p['id'] as String;
    final slot = 4 + times.length % 3;
    if ((p['photoRefs'] as List).length <= slot) continue;
    if (ProxyService.isPhotoHeld(id, slot) != false) continue;
    final sw = Stopwatch()..start();
    final got = await ProxyService.photo(id, slot);
    times.add(sw.elapsedMilliseconds);
    print('  $id/$slot ${sw.elapsedMilliseconds}ms ${got.bytes == null ? 'NO BYTES' : '${got.bytes!.length ~/ 1024}KB'}');
  }
  times.sort();
  print('median ${times[times.length ~/ 2]}ms over ${times.length}');
  exit(0);
}
