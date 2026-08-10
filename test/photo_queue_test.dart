import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:foodierank/services/restaurant_service.dart';

/// The photo queue must always hand back a *completed* future, whatever
/// happens underneath. A widget calls `loadPhoto(...).then(...)`, so a future
/// that hangs, or that completes with an error, leaves a placeholder on screen
/// forever with nothing logged.
void main() {
  final service = RestaurantService.instance;

  tearDown(() {
    service.photoCacheRead = null;
    service.photoCacheWrite = null;
  });

  test('a disk hit completes', () async {
    service.photoCacheRead = (ref) async => Uint8List.fromList([1, 2, 3]);
    final bytes = await service.loadPhoto('disk-hit').timeout(
          const Duration(seconds: 5),
        );
    expect(bytes, isNotNull);
  });

  test('a failing disk read does not poison the future', () async {
    // If this escapes, `.then` never runs its callback and the photo shimmers
    // forever.
    service.photoCacheRead = (ref) async => throw StateError('disk exploded');
    final bytes = await service.loadPhoto('disk-throws').timeout(
          const Duration(seconds: 20),
        );
    expect(bytes, isNull);
  });

  test('a failing disk write does not poison the future', () async {
    service.photoCacheRead = (ref) async => null;
    service.photoCacheWrite = (ref, bytes) async => throw StateError('no space');
    final bytes = await service.loadPhoto('write-throws').timeout(
          const Duration(seconds: 20),
        );
    // Network is unavailable in tests, so null is the expected outcome; the
    // point is that it completes at all.
    expect(bytes, isNull);
  });

  test('more requests than slots all complete, and none leak a slot', () async {
    // Twenty concurrent requests through a six-slot semaphore. A slot that is
    // taken and never released deadlocks everything queued behind it.
    service.photoCacheRead = (ref) async => null;
    final results = await Future.wait([
      for (var i = 0; i < 20; i++) service.loadPhoto('leak-$i'),
    ]).timeout(const Duration(seconds: 40));
    expect(results, hasLength(20));
  });

  test('mixed priorities all complete', () async {
    service.photoCacheRead = (ref) async => null;
    final results = await Future.wait([
      for (var i = 0; i < 10; i++)
        service.loadPhoto('mixed-first-$i', priority: true),
      for (var i = 0; i < 10; i++)
        service.loadPhoto('mixed-rest-$i', priority: false),
    ]).timeout(const Duration(seconds: 40));
    expect(results, hasLength(20));
  });

  test('the queue still works after a batch has drained', () async {
    // A leaked slot from an earlier batch only shows up as a hang here.
    service.photoCacheRead = (ref) async => null;
    await Future.wait([
      for (var i = 0; i < 10; i++) service.loadPhoto('batch1-$i'),
    ]).timeout(const Duration(seconds: 40));

    service.photoCacheRead = (ref) async => Uint8List.fromList([9]);
    final again = await service.loadPhoto('batch2').timeout(
          const Duration(seconds: 5),
        );
    expect(again, isNotNull);
  });

  // Google mints a fresh `photos[i].name` on every search response — verified
  // against the live API: two identical searches seconds apart returned the
  // same place and the same ten photos under different references. Keying the
  // caches on that reference gave a disk tier with a 0% cross-search hit rate,
  // so every filter tap re-downloaded twenty pictures. These lock the fix in.
  group('cache keys survive a rotating photo reference', () {
    test('a second search for the same place reads the first search\'s disk '
        'entry', () async {
      final keysRead = <String>[];
      service.photoCacheRead = (key) async {
        keysRead.add(key);
        return Uint8List.fromList([7]);
      };

      await service.loadPhoto('places/PLACE_A/photos/REF_FROM_SEARCH_1',
          cacheId: 'PLACE_A:0');
      await service.loadPhoto('places/PLACE_A/photos/REF_FROM_SEARCH_2',
          cacheId: 'PLACE_A:0');

      // Both look in the same place. The second is served from memory, so the
      // disk is only consulted once — the important part is that neither read
      // is keyed on the reference that changed.
      expect(keysRead, isNotEmpty);
      expect(keysRead.every((k) => k.startsWith('PLACE_A:0@')), isTrue,
          reason: 'disk lookups must use the stable id, not the reference');
    });

    test('memory serves the new reference from the old bytes', () async {
      service.photoCacheRead = (key) async => Uint8List.fromList([1, 2, 3]);
      await service.loadPhoto('places/PLACE_B/photos/REF_ONE',
          cacheId: 'PLACE_B:0');

      // No disk tier at all now: a cache keyed on the reference would have to
      // go to the network here and come back null.
      service.photoCacheRead = null;
      final cached = service.getCachedPhoto(
          'places/PLACE_B/photos/REF_TWO_TOTALLY_DIFFERENT',
          cacheId: 'PLACE_B:0');
      expect(cached, isNotNull,
          reason: 'a rotated reference must still hit the cached bytes');
    });

    test('different photos of one place do not collide', () async {
      service.photoCacheRead = (key) async => null;
      service.photoCacheWrite = (key, bytes) async {};

      expect(
        RestaurantService.photoCacheKey('ref-x', 'PLACE_C:0', 800, 450),
        isNot(RestaurantService.photoCacheKey('ref-y', 'PLACE_C:1', 800, 450)),
      );
      // Nor do two sizes of the same photo: the list thumbnail and the card
      // header are fetched at different dimensions.
      expect(
        RestaurantService.photoCacheKey('ref-x', 'PLACE_C:0', 800, 450),
        isNot(RestaurantService.photoCacheKey('ref-x', 'PLACE_C:0', 96, 96)),
      );
    });

    test('a caller with no place context still works', () async {
      // `bin/foodierank.dart` and any ad-hoc caller pass no cacheId; the
      // reference has to remain a usable fallback.
      service.photoCacheRead = (key) async => Uint8List.fromList([4]);
      final bytes = await service.loadPhoto('bare-ref').timeout(
            const Duration(seconds: 5),
          );
      expect(bytes, isNotNull);
    });
  });
}
