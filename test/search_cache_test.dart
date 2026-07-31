import 'package:flutter_test/flutter_test.dart';
import 'package:foodierank/services/restaurant_service.dart';

void main() {
  group('RestaurantService.queryKey', () {
    test('two identical queries share a key', () {
      expect(
        RestaurantService.queryKey(cuisineType: 'Italian', openNow: true),
        RestaurantService.queryKey(cuisineType: 'Italian', openNow: true),
      );
    });

    test('a different cuisine is a different query', () {
      expect(
        RestaurantService.queryKey(cuisineType: 'Italian'),
        isNot(RestaurantService.queryKey(cuisineType: 'Thai')),
      );
    });

    test('a different price filter is a different query', () {
      // The old cache key ignored these entirely, so a result set fetched
      // under one price filter could be served for another.
      expect(
        RestaurantService.queryKey(priceLevels: ['PRICE_LEVEL_INEXPENSIVE']),
        isNot(RestaurantService.queryKey(
            priceLevels: ['PRICE_LEVEL_EXPENSIVE'])),
      );
    });

    test('price levels are order-insensitive', () {
      expect(
        RestaurantService.queryKey(priceLevels: ['a', 'b']),
        RestaurantService.queryKey(priceLevels: ['b', 'a']),
      );
    });

    test('a keyword search is a different query', () {
      expect(
        RestaurantService.queryKey(searchQuery: 'ramen'),
        isNot(RestaurantService.queryKey(searchQuery: '')),
      );
    });

    test('a custom time is a different query', () {
      expect(
        RestaurantService.queryKey(openNow: false, targetDay: 5,
            targetMinutes: 1200),
        isNot(RestaurantService.queryKey(openNow: true)),
      );
    });

    test('a pinned location is a different query', () {
      expect(
        RestaurantService.queryKey(contextKey: 'lisbon'),
        isNot(RestaurantService.queryKey()),
      );
    });
  });

  group('RestaurantSearchSnapshot', () {
    final snapshot = RestaurantSearchSnapshot(
      places: [
        {'id': 'a', 'rating': 4.5},
        {'id': 'b', 'rating': 4.1},
      ],
      latitude: 40.7,
      longitude: -74.0,
      queryKey: 'k',
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );

    test('round-trips through JSON', () {
      final restored = RestaurantSearchSnapshot.fromJson(snapshot.toJson());

      expect(restored, isNotNull);
      expect(restored!.places, hasLength(2));
      expect(restored.places.first['id'], 'a');
      expect(restored.latitude, 40.7);
      expect(restored.longitude, -74.0);
      expect(restored.queryKey, 'k');
      expect(restored.fetchedAt, snapshot.fetchedAt);
    });

    test('rejects a payload missing its coordinates rather than throwing', () {
      expect(
        RestaurantSearchSnapshot.fromJson({
          'places': <Map<String, dynamic>>[],
          'fetchedAt': 1700000000000,
        }),
        isNull,
      );
    });

    test('rejects a payload with no places', () {
      expect(
        RestaurantSearchSnapshot.fromJson({
          'lat': 1.0,
          'lng': 2.0,
          'fetchedAt': 1700000000000,
        }),
        isNull,
      );
    });
  });

  group('RestaurantService.shouldRefreshData', () {
    test('refreshes when nothing has been fetched yet', () {
      expect(
        RestaurantService.instance.shouldRefreshData(40.7, -74.0),
        isTrue,
      );
    });

    test('reuses a fresh nearby result set for the same query', () {
      RestaurantService.instance.hydrate(RestaurantSearchSnapshot(
        places: [
          {'id': 'a'}
        ],
        latitude: 40.7,
        longitude: -74.0,
        queryKey: RestaurantService.queryKey(cuisineType: 'All'),
        fetchedAt: DateTime.now(),
      ));

      expect(
        RestaurantService.instance
            .shouldRefreshData(40.7, -74.0, cuisineType: 'All'),
        isFalse,
      );
    });

    test('refreshes once the filters change under it', () {
      RestaurantService.instance.hydrate(RestaurantSearchSnapshot(
        places: [
          {'id': 'a'}
        ],
        latitude: 40.7,
        longitude: -74.0,
        queryKey: RestaurantService.queryKey(cuisineType: 'All'),
        fetchedAt: DateTime.now(),
      ));

      expect(
        RestaurantService.instance
            .shouldRefreshData(40.7, -74.0, cuisineType: 'Thai'),
        isTrue,
      );
    });

    test('refreshes after moving more than 300m', () {
      RestaurantService.instance.hydrate(RestaurantSearchSnapshot(
        places: [
          {'id': 'a'}
        ],
        latitude: 40.7,
        longitude: -74.0,
        queryKey: RestaurantService.queryKey(cuisineType: 'All'),
        fetchedAt: DateTime.now(),
      ));

      // ~0.01 degrees of latitude is a bit over a kilometre.
      expect(
        RestaurantService.instance
            .shouldRefreshData(40.71, -74.0, cuisineType: 'All'),
        isTrue,
      );
    });

    test('refreshes a result set older than an hour', () {
      RestaurantService.instance.hydrate(RestaurantSearchSnapshot(
        places: [
          {'id': 'a'}
        ],
        latitude: 40.7,
        longitude: -74.0,
        queryKey: RestaurantService.queryKey(cuisineType: 'All'),
        fetchedAt: DateTime.now().subtract(const Duration(hours: 2)),
      ));

      expect(
        RestaurantService.instance
            .shouldRefreshData(40.7, -74.0, cuisineType: 'All'),
        isTrue,
      );
    });
  });
}
