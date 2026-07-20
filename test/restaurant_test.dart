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

  group('Restaurant.rankingScore', () {
    Restaurant make(
            {double rating = 0,
            int reviews = 0,
            double bonus = 0,
            double penalty = 0}) =>
        Restaurant(
          id: '1',
          name: 'Test',
          mainPhotoUrl: '',
          placeId: '1',
          rating: rating,
          reviewCount: reviews,
          destinationBonus: bonus,
          touristPenalty: penalty,
        );

    test('zero reviews yields a zero score', () {
      expect(make(rating: 5.0, reviews: 0, bonus: 1.5).rankingScore, 0);
    });

    test('a highly rated small place outranks a mediocre giant', () {
      final gem = make(rating: 4.8, reviews: 150);
      final touristTrap = make(rating: 4.4, reviews: 6000);
      expect(gem.rankingScore, greaterThan(touristTrap.rankingScore));
    });

    test('review volume still helps but saturates', () {
      final tiny = make(rating: 4.5, reviews: 10).rankingScore;
      final medium = make(rating: 4.5, reviews: 200).rankingScore;
      final huge = make(rating: 4.5, reviews: 20000).rankingScore;
      expect(medium, greaterThan(tiny));
      expect(huge, greaterThan(medium));
      // The 200 → 20,000 gain is a fraction of the 10 → 200 gain.
      expect(huge - medium, lessThan((medium - tiny) / 2));
    });

    test('destination bonus lifts and tourist penalty drops the score', () {
      final base = make(rating: 4.5, reviews: 300).rankingScore;
      expect(make(rating: 4.5, reviews: 300, bonus: 1.5).rankingScore,
          greaterThan(base));
      expect(make(rating: 4.5, reviews: 300, penalty: 1.0).rankingScore,
          lessThan(base));
    });

    test('locality terms cannot flip a clearly better rating', () {
      final worstCaseGreat =
          make(rating: 4.8, reviews: 500, penalty: 1.0);
      final bestCaseMediocre =
          make(rating: 4.0, reviews: 500, bonus: 1.5);
      expect(worstCaseGreat.rankingScore,
          greaterThan(bestCaseMediocre.rankingScore));
    });
  });
}
