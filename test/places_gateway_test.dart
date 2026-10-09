import 'package:flutter_test/flutter_test.dart';
import 'package:foodierank/services/proxy_service.dart';
import 'package:foodierank/services/restaurant_service.dart';

/// The pieces of the Places gateway cutover that can be checked without a
/// network: how a photo is addressed, how "open now" is evaluated client-side,
/// and how a gateway failure is classified.
void main() {
  group('gatewayPhotoTarget', () {
    test('reads place id and slot from the cache id every caller passes', () {
      final target = RestaurantService.gatewayPhotoTarget(
          'places/ChIJabc/photos/ROTATING_NONCE', 'ChIJabc:3');
      expect(target?.placeId, 'ChIJabc');
      expect(target?.slot, 3);
    });

    test('ignores the rotating Google resource name entirely', () {
      // Two searches, two different names, one photo.
      expect(
        RestaurantService.gatewayPhotoTarget('places/P/photos/ONE', 'P:0'),
        RestaurantService.gatewayPhotoTarget('places/P/photos/TWO', 'P:0'),
      );
    });

    test('no cache id means no slot, so no request rather than a wrong photo',
        () {
      expect(RestaurantService.gatewayPhotoTarget('places/P/photos/X', null),
          isNull);
    });

    test('a malformed cache id is a miss', () {
      expect(RestaurantService.gatewayPhotoTarget('ref', 'P'), isNull);
      expect(RestaurantService.gatewayPhotoTarget('ref', 'P:x'), isNull);
      expect(RestaurantService.gatewayPhotoTarget('ref', ':0'), isNull);
      expect(RestaurantService.gatewayPhotoTarget('ref', 'P:-1'), isNull);
    });
  });

  group('storedPhotoUrl', () {
    test('is the gateway\'s fixed Storage path, on the gateway\'s host', () {
      final url = ProxyService.storedPhotoUrl('ChIJs0_cUCw1GQ0RKWxVUZplTmQ', 2);
      expect(url.toString(),
          'https://cndaivlyzonqndnvzilr.supabase.co/storage/v1/object/public/photos/ChIJs0_cUCw1GQ0RKWxVUZplTmQ/2.jpg');
    });

    test('keeps a place id\'s URL-safe characters intact', () {
      final url = ProxyService.storedPhotoUrl('ChIJ-a_b', 0);
      expect(url.path, '/storage/v1/object/public/photos/ChIJ-a_b/0.jpg');
    });
  });

  group('placeLocalTime', () {
    // 2026-10-02 is a Friday.
    final nowUtc = DateTime.utc(2026, 10, 2, 23, 30);

    test('applies the place\'s own UTC offset', () {
      // 23:30 UTC is 19:30 in New York (UTC-4 in October).
      final ny = RestaurantService.placeLocalTime(nowUtc, -240);
      expect(ny.day, 5); // Friday
      expect(ny.minutes, 19 * 60 + 30);
    });

    test('rolls the weekday over across midnight', () {
      // 23:30 UTC is 01:30 Saturday in Paris (UTC+2 in October).
      final paris = RestaurantService.placeLocalTime(nowUtc, 120);
      expect(paris.day, 6); // Saturday
      expect(paris.minutes, 90);
    });

    test('Sunday is day 0, as isOpenAt expects', () {
      final sunday =
          RestaurantService.placeLocalTime(DateTime.utc(2026, 10, 4, 12), 0);
      expect(sunday.day, 0);
    });

    test('feeds isOpenAt correctly for a place that is open now', () {
      // Open Friday 17:00–23:00.
      final periods = [
        {
          'open': {'day': 5, 'hour': 17, 'minute': 0},
          'close': {'day': 5, 'hour': 23, 'minute': 0},
        },
      ];
      final ny = RestaurantService.placeLocalTime(nowUtc, -240);
      expect(RestaurantService.isOpenAt(periods, ny.day, ny.minutes), isTrue);
      final paris = RestaurantService.placeLocalTime(nowUtc, 120);
      expect(RestaurantService.isOpenAt(periods, paris.day, paris.minutes),
          isFalse);
    });
  });

  group('PlacesApiException', () {
    test('a bad app key is "unavailable" and not retried', () {
      const e = PlacesApiException('searchText', 401, 'bad app key');
      expect(e.isUnavailable, isTrue);
      expect(e.isRetryable, isFalse);
    });

    test('the gateway\'s 503 (someone else is fetching) is retried', () {
      const e = PlacesApiException('details', 503);
      expect(e.isRetryable, isTrue);
      expect(e.isUnavailable, isFalse);
    });

    test('a relayed Google 403 is classified as Google\'s 403', () {
      const e = PlacesApiException(
          'searchText', 502, 'Google 403: {"error": "PERMISSION_DENIED"}');
      expect(e.upstreamStatus, 403);
      expect(e.isUnavailable, isTrue);
      expect(e.isRetryable, isFalse);
    });

    test('a relayed Google 400 is not retried', () {
      const e = PlacesApiException('details', 502, 'Google 400: bad id');
      expect(e.isRetryable, isFalse);
    });

    test('a bare 502 with no Google status is retried', () {
      const e = PlacesApiException('searchText', 502);
      expect(e.upstreamStatus, isNull);
      expect(e.isRetryable, isTrue);
    });
  });

  group('held photos', () {
    test('a search\'s heldPhotos map says which slots skip the probe', () {
      ProxyService.recordHeldPhotos({
        'HeldA': [0, 2],
        'HeldB': <int>[],
      });
      expect(ProxyService.isPhotoHeld('HeldA', 0), isTrue);
      expect(ProxyService.isPhotoHeld('HeldA', 1), isFalse);
      expect(ProxyService.isPhotoHeld('HeldB', 0), isFalse);
    });

    test('a place no search has mentioned is unknown, not "not held"', () {
      // Unknown keeps the Storage probe; "not held" would skip it and buy.
      expect(ProxyService.isPhotoHeld('NeverSeen', 0), isNull);
    });

    test('an older gateway without the map changes nothing', () {
      ProxyService.recordHeldPhotos(null);
      ProxyService.recordHeldPhotos({'Bad': 'x', 3: [0]});
      expect(ProxyService.isPhotoHeld('Bad', 0), isNull);
    });

    test('a photo the gateway just stored counts as held', () {
      ProxyService.recordHeldPhotos({'Fresh': <int>[]});
      ProxyService.notePhotoHeld('Fresh', 0);
      expect(ProxyService.isPhotoHeld('Fresh', 0), isTrue);
    });
  });
}
