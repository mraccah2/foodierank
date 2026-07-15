import 'package:flutter_test/flutter_test.dart';
import 'package:foodierank/models/search_context.dart';

void main() {
  group('SearchContext — defaults', () {
    const ctx = SearchContext.initial;

    test('starts as the default near-me / open-now context', () {
      expect(ctx.isDefault, isTrue);
      expect(ctx.isCustomLocation, isFalse);
      expect(ctx.isCustomTime, isFalse);
      expect(ctx.locationDisplay, 'Near me');
      expect(ctx.timeDisplay, 'Open now');
      expect(ctx.cacheKey, 'me|now');
    });
  });

  group('SearchContext — location', () {
    test('withLocation sets a custom centre and label', () {
      final ctx = SearchContext.initial.withLocation(
        lat: 48.8584,
        lng: 2.2945,
        label: 'Eiffel Tower',
      );
      expect(ctx.isCustomLocation, isTrue);
      expect(ctx.isDefault, isFalse);
      expect(ctx.locationDisplay, 'Eiffel Tower');
      expect(ctx.cacheKey, contains('48.8584'));
    });

    test('clearLocation returns to Near me but keeps the time', () {
      final ctx = SearchContext.initial
          .withTime(day: 0, minutes: 540, label: 'Breakfast')
          .withLocation(lat: 1, lng: 2, label: 'Somewhere')
          .clearLocation();
      expect(ctx.isCustomLocation, isFalse);
      expect(ctx.isCustomTime, isTrue);
      expect(ctx.timeDisplay, 'Breakfast');
    });
  });

  group('SearchContext — time', () {
    test('withTime sets a custom day/time', () {
      final ctx = SearchContext.initial
          .withTime(day: 0, minutes: 540, label: 'Breakfast');
      expect(ctx.isCustomTime, isTrue);
      expect(ctx.timeMode, TimeMode.custom);
      expect(ctx.targetDay, 0);
      expect(ctx.targetMinutes, 540);
      expect(ctx.timeDisplay, 'Breakfast');
      expect(ctx.cacheKey, 'me|d0@540');
    });

    test('clearTime returns to Open now but keeps the location', () {
      final ctx = SearchContext.initial
          .withLocation(lat: 1, lng: 2, label: 'Somewhere')
          .withTime(day: 3, minutes: 720, label: 'Lunch')
          .clearTime();
      expect(ctx.isCustomTime, isFalse);
      expect(ctx.isCustomLocation, isTrue);
      expect(ctx.locationDisplay, 'Somewhere');
    });
  });

  group('SearchContext — formatting', () {
    test('formatClock renders 12-hour times', () {
      expect(SearchContext.formatClock(0), '12:00 AM');
      expect(SearchContext.formatClock(90), '1:30 AM');
      expect(SearchContext.formatClock(8 * 60), '8:00 AM');
      expect(SearchContext.formatClock(12 * 60), '12:00 PM');
      expect(SearchContext.formatClock(13 * 60 + 5), '1:05 PM');
      expect(SearchContext.formatClock(22 * 60), '10:00 PM');
    });

    test('formatDayTime combines weekday and clock', () {
      expect(SearchContext.formatDayTime(0, 9 * 60), 'Sun 9:00 AM');
      expect(SearchContext.formatDayTime(6, 19 * 60), 'Sat 7:00 PM');
    });
  });
}
