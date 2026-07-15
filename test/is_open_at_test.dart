import 'package:flutter_test/flutter_test.dart';
import 'package:foodierank/services/restaurant_service.dart';

/// Builds a Places-API opening-hours point. day: 0 = Sunday … 6 = Saturday.
Map<String, dynamic> _pt(int day, int hour, [int minute = 0]) =>
    {'day': day, 'hour': hour, 'minute': minute};

Map<String, dynamic> _period(Map<String, dynamic> open,
        [Map<String, dynamic>? close]) =>
    {'open': open, if (close != null) 'close': close};

void main() {
  group('RestaurantService.isOpenAt — unknown hours', () {
    test('null periods → treated as closed', () {
      expect(RestaurantService.isOpenAt(null, 1, 10 * 60), isFalse);
    });

    test('empty periods → treated as closed', () {
      expect(RestaurantService.isOpenAt(const [], 1, 10 * 60), isFalse);
    });
  });

  group('RestaurantService.isOpenAt — normal daytime hours', () {
    // Monday 09:00–17:00
    final periods = [_period(_pt(1, 9), _pt(1, 17))];

    test('inside the window is open', () {
      expect(RestaurantService.isOpenAt(periods, 1, 10 * 60), isTrue);
    });

    test('before opening is closed', () {
      expect(RestaurantService.isOpenAt(periods, 1, 8 * 60), isFalse);
    });

    test('exactly at closing is closed (end-exclusive)', () {
      expect(RestaurantService.isOpenAt(periods, 1, 17 * 60), isFalse);
    });

    test('exactly at opening is open (start-inclusive)', () {
      expect(RestaurantService.isOpenAt(periods, 1, 9 * 60), isTrue);
    });

    test('a different day is closed', () {
      expect(RestaurantService.isOpenAt(periods, 2, 10 * 60), isFalse);
    });
  });

  group('RestaurantService.isOpenAt — 24 hours', () {
    // Open with no close per the API contract for always-open places.
    final periods = [_period(_pt(0, 0, 0))];

    test('any day/time is open', () {
      expect(RestaurantService.isOpenAt(periods, 3, 3 * 60), isTrue);
      expect(RestaurantService.isOpenAt(periods, 6, 23 * 60 + 59), isTrue);
    });
  });

  group('RestaurantService.isOpenAt — overnight (crosses midnight)', () {
    // Friday 22:00 → Saturday 02:00
    final periods = [_period(_pt(5, 22), _pt(6, 2))];

    test('late on the opening day is open', () {
      expect(RestaurantService.isOpenAt(periods, 5, 23 * 60), isTrue);
    });

    test('early on the following day is open', () {
      expect(RestaurantService.isOpenAt(periods, 6, 1 * 60), isTrue);
    });

    test('after close on the following day is closed', () {
      expect(RestaurantService.isOpenAt(periods, 6, 3 * 60), isFalse);
    });
  });

  group('RestaurantService.isOpenAt — week wrap (Sat night into Sun)', () {
    // Saturday 22:00 → Sunday 02:00
    final periods = [_period(_pt(6, 22), _pt(0, 2))];

    test('Saturday night is open', () {
      expect(RestaurantService.isOpenAt(periods, 6, 23 * 60), isTrue);
    });

    test('Sunday small hours are open (wrapped)', () {
      expect(RestaurantService.isOpenAt(periods, 0, 1 * 60), isTrue);
    });

    test('Sunday after close is closed', () {
      expect(RestaurantService.isOpenAt(periods, 0, 3 * 60), isFalse);
    });
  });

  group('RestaurantService.isOpenAt — multiple periods same day', () {
    // Monday lunch 11:00–14:00 and dinner 17:00–22:00
    final periods = [
      _period(_pt(1, 11), _pt(1, 14)),
      _period(_pt(1, 17), _pt(1, 22)),
    ];

    test('lunch time is open', () {
      expect(RestaurantService.isOpenAt(periods, 1, 12 * 60), isTrue);
    });

    test('the afternoon gap is closed', () {
      expect(RestaurantService.isOpenAt(periods, 1, 15 * 60), isFalse);
    });

    test('dinner time is open', () {
      expect(RestaurantService.isOpenAt(periods, 1, 20 * 60), isTrue);
    });
  });
}
