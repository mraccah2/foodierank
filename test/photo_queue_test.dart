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
}
