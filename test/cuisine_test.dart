import 'package:flutter_test/flutter_test.dart';
import 'package:foodierank/models/cuisine.dart';
import 'package:foodierank/models/restaurant.dart';

void main() {
  group('Cuisine.resolve', () {
    test('reads the cuisine out of a compound Places type', () {
      expect(Cuisine.resolve(['italian_restaurant', 'food']), 'italian');
    });

    test('matches an underscored keyword the compound pass would split', () {
      expect(Cuisine.resolve(['middle_eastern']), 'middle_eastern');
    });

    test('prefers the types over the country', () {
      expect(
        Cuisine.resolve(['japanese_restaurant'], country: 'France'),
        'japanese',
      );
    });

    test('falls back to the country, marked as a guess', () {
      expect(Cuisine.resolve(['restaurant'], country: 'France'), 'french?');
    });

    test('gives up rather than guessing from an unmapped country', () {
      expect(Cuisine.resolve(['restaurant'], country: 'Narnia'), isNull);
    });

    test('gives up when there is nothing to go on', () {
      expect(Cuisine.resolve(const []), isNull);
    });
  });

  group('Cuisine.format', () {
    test('splits underscores into words', () {
      expect(Cuisine.format('middle_eastern'), 'Middle Eastern');
    });

    test('keeps the guess marker', () {
      expect(Cuisine.format('french?'), 'French?');
    });

    test('survives an empty segment rather than throwing', () {
      // The card's old copy indexed word[0] unguarded.
      expect(Cuisine.format('thai_'), 'Thai ');
    });
  });

  group('Restaurant.cuisineLabel', () {
    test('is resolved once at parse time', () {
      final restaurant = Restaurant.fromJson({
        'id': 'abc',
        'displayName': {'text': 'Osteria'},
        'formattedAddress': 'Via Roma 1, Italy',
        'userRatingCount': 100,
        'rating': 4.5,
        'types': ['italian_restaurant'],
        'location': {'latitude': 41.9, 'longitude': 12.5, 'country': 'Italy'},
      });

      expect(restaurant.cuisineLabel, 'Italian');
    });

    test('falls back to the country when the types say nothing', () {
      final restaurant = Restaurant.fromJson({
        'id': 'def',
        'displayName': {'text': 'Chez Nous'},
        'formattedAddress': '1 Rue de Paris, France',
        'userRatingCount': 50,
        'rating': 4.2,
        'types': ['restaurant', 'point_of_interest'],
        'location': {'latitude': 48.8, 'longitude': 2.3, 'country': 'France'},
      });

      expect(restaurant.cuisineLabel, 'French?');
    });

    test('is null when neither the types nor the country help', () {
      final restaurant = Restaurant.fromJson({
        'id': 'ghi',
        'displayName': {'text': 'The Place'},
        'formattedAddress': 'Somewhere, Narnia',
        'userRatingCount': 10,
        'rating': 4.0,
        'types': ['restaurant'],
        'location': {'latitude': 1.0, 'longitude': 1.0, 'country': 'Narnia'},
      });

      expect(restaurant.cuisineLabel, isNull);
    });
  });
}
