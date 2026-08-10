import 'package:flutter_test/flutter_test.dart';
import 'package:foodierank/services/proxy_service.dart';

/// An empty restaurant list has two causes that call for opposite reactions:
/// there is genuinely nothing open, or Places never answered. Until 2026-08-10
/// they were indistinguishable — a `.catchError((_) => {})` in the search fan-out
/// flattened every failure into "no places found", so the day the API was
/// disabled on a spend cap, every user was told "No restaurants currently open
/// in this area" about a neighbourhood full of them.
void main() {
  group('a refusal is not an empty neighbourhood', () {
    test('the API being switched off reads as unavailable', () {
      // What a project with places.googleapis.com disabled returns.
      const disabled = PlacesApiException('places:searchText', 403);
      expect(disabled.isUnavailable, isTrue);
      expect(disabled.userMessage, contains('temporarily unavailable'));
      expect(disabled.userMessage, contains('search budget'));
      // The important half: it must not imply the area is empty.
      expect(disabled.userMessage, contains('not that there is nothing open'));
    });

    test('quota exhaustion reads as unavailable too', () {
      const throttled = PlacesApiException('places:searchText', 429);
      expect(throttled.isUnavailable, isTrue);
    });

    test('a server fault is unavailable but does not blame the budget', () {
      const boom = PlacesApiException('places:searchText', 503);
      expect(boom.isUnavailable, isFalse);
      expect(boom.userMessage, contains('try again shortly'));
      expect(boom.userMessage, isNot(contains('budget')));
    });

    test('a refusal is not retried, a transient fault is', () {
      // Retrying a 403 three times with back-off only delays the same answer.
      expect(const PlacesApiException('e', 403).isRetryable, isFalse);
      expect(const PlacesApiException('e', 429).isRetryable, isTrue);
      expect(const PlacesApiException('e', 500).isRetryable, isTrue);
    });
  });
}
