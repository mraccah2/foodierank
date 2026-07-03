import 'package:flutter_test/flutter_test.dart';
import 'package:foodierank/models/restaurant.dart';

void main() {
  group('Location.calculateDistance', () {
    const loc = Location(
      latitude: 0,
      longitude: 0,
      formattedAddress: '',
      country: '',
    );

    test('distance between identical points is zero', () {
      expect(loc.calculateDistance(40.0, -73.0, 40.0, -73.0), closeTo(0, 0.001));
    });

    test('roughly one degree of latitude is ~111 km', () {
      final km = loc.calculateDistance(0, 0, 1, 0);
      expect(km, closeTo(111.0, 2.0));
    });
  });

  group('Location.formatDistance', () {
    test('sub-kilometer distances are shown in meters', () {
      const here = Location(
        latitude: 40.0,
        longitude: -73.0,
        formattedAddress: '',
        country: '',
      );
      // ~200m north
      final label = here.formatDistance(40.0018, -73.0);
      expect(label.endsWith('m'), isTrue);
      expect(label.endsWith('km'), isFalse);
    });

    test('multi-kilometer distances are shown in kilometers', () {
      const here = Location(
        latitude: 40.0,
        longitude: -73.0,
        formattedAddress: '',
        country: '',
      );
      final label = here.formatDistance(41.0, -73.0);
      expect(label.endsWith('km'), isTrue);
    });
  });

  group('Restaurant.calculateWilsonScore', () {
    final restaurant = Restaurant(id: '1', name: 'Test', mainPhotoUrl: '',
        reviewCount: 0, placeId: '1');

    test('zero reviews yields a zero score', () {
      expect(restaurant.calculateWilsonScore(5.0, 0), 0);
    });

    test('score stays within the unit interval', () {
      final score = restaurant.calculateWilsonScore(4.5, 200);
      expect(score, greaterThan(0));
      expect(score, lessThanOrEqualTo(1));
    });

    test('more reviews at the same rating ranks higher', () {
      final few = restaurant.calculateWilsonScore(4.5, 10);
      final many = restaurant.calculateWilsonScore(4.5, 1000);
      expect(many, greaterThan(few));
    });
  });
}
