import 'dart:convert';
import 'dart:typed_data';

import '../config.dart';
import 'app_http.dart';

/// A failed call to the Places gateway (or to Google behind it).
class PlacesApiException implements Exception {
  /// The gateway op that failed — `searchText`, `photo`, ...
  final String endpoint;
  final int statusCode;

  /// The gateway's `error` string, when it sent one.
  final String? message;

  const PlacesApiException(this.endpoint, this.statusCode, [this.message]);

  /// The status Google itself answered with, when the gateway relayed a
  /// Google failure as a 502 (`"Google 403: ..."`). Null for the gateway's
  /// own statuses.
  int? get upstreamStatus {
    final match = RegExp(r'^Google (\d{3})').firstMatch(message ?? '');
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// The status that actually describes the failure: Google's when the
  /// gateway was only relaying it, the gateway's own otherwise.
  int get _effectiveStatus => upstreamStatus ?? statusCode;

  /// Whether the same request could plausibly succeed on another attempt.
  ///
  /// A 400, 401 or 403 means the request, the key, or the API itself is
  /// wrong, and will stay wrong; retrying with back-off only delays the same
  /// failure by several seconds. Rate limits and server faults are worth
  /// another go — including the gateway's 503, which means another caller is
  /// fetching the same thing right now.
  bool get isRetryable => _effectiveStatus == 429 || _effectiveStatus >= 500;

  /// Whether Places refused us outright, as opposed to having nothing to say.
  ///
  /// 401 is the gateway rejecting our app key; 403 is the API switched off or
  /// the key revoked; 429 is quota. None of those mean "no restaurants here",
  /// which is exactly what an empty result set was being reported as — on
  /// 2026-08-10 the API was disabled on a spend cap and every user saw "No
  /// restaurants currently open in this area" instead.
  bool get isUnavailable =>
      _effectiveStatus == 401 ||
      _effectiveStatus == 403 ||
      _effectiveStatus == 429;

  /// What to tell someone looking at an empty screen.
  String get userMessage => isUnavailable
      ? 'Restaurant search is temporarily unavailable. This usually means the '
          'app has reached its search budget for the month — it is not that '
          'there is nothing open nearby.'
      : 'Restaurant search is temporarily unavailable. Please try again shortly.';

  @override
  String toString() => 'Places gateway $endpoint failed with status $statusCode'
      '${message == null ? '' : ': $message'}';
}

/// The one client for Places, which since 2026-10 means our shared Places
/// gateway rather than places.googleapis.com.
///
/// The gateway speaks Google's shapes inside a small envelope: a search body is
/// Google's own `searchText` / `searchNearby` / `autocomplete` body plus an
/// `op`, and the answer carries Google's `places` / `suggestions` arrays. It
/// always returns every field, so there are no field masks here any more —
/// a place is bought from Google once and every later caller, from any app,
/// gets all of it for free.
///
/// Pure Dart (no Flutter imports), so `bin/foodierank.dart` shares it.
class ProxyService {
  static const int _maxAttempts = 3;

  /// Back-off between attempts. Deliberately short — the caller is a user
  /// watching a spinner, and a search sector that ultimately fails contributes
  /// nothing rather than aborting the round. The first step is ~1 s because
  /// the gateway's 503 means "someone else is fetching this exact thing";
  /// by then their answer is usually cached.
  static const List<Duration> _backoff = [
    Duration(milliseconds: 1000),
    Duration(milliseconds: 1500),
  ];

  /// Public photo URLs by `'<placeId>:<slot>'`. The gateway's URLs are
  /// permanent, so once known one never needs asking for again this session.
  static final Map<String, String> _photoUrlCache = {};
  static final Map<String, Future<({Uint8List? bytes, String? url})>>
      _photoRequests = {};

  /// POSTs `{op, ...body}` to the gateway and returns the decoded envelope.
  static Future<Map<String, dynamic>> gateway(
    String op,
    Map<String, dynamic> body,
  ) {
    final headers = {
      'Content-Type': 'application/json',
      'x-app-key': Config.placesGatewayKey,
    };
    final payload = jsonEncode({...body, 'op': op});

    return _withRetries(() async {
      final response = await appHttpClient
          .post(Uri.parse(Config.placesGatewayUrl),
              headers: headers, body: payload)
          .timeout(kRequestTimeout);

      if (response.statusCode != 200) {
        String? error;
        try {
          error = (json.decode(response.body) as Map<String, dynamic>)['error']
              as String?;
        } catch (_) {}
        throw PlacesApiException(op, response.statusCode, error);
      }
      return json.decode(response.body) as Map<String, dynamic>;
    });
  }

  /// Google's Text Search. [params] is Google's request body; the result has
  /// Google's `places` array.
  ///
  /// [fields] cuts each place down to what the caller reads (`'photos.name'`
  /// keeps only the name of each photo). A full place is ~30 KB, mostly
  /// reviews and photo attributions, so an untrimmed sector search is ~650 KB
  /// — and a screen waits on four of them. The gateway trims the response
  /// only; its cache key ignores this.
  ///
  /// [heldPhotos] asks which photo slots the gateway already stores, which
  /// [isPhotoHeld] then answers for the photo loader.
  static Future<Map<String, dynamic>> searchText(Map<String, dynamic> params,
          {List<String>? fields, bool heldPhotos = false}) =>
      _search('searchText', params, fields, heldPhotos);

  /// Google's Nearby Search, same contract as [searchText].
  static Future<Map<String, dynamic>> searchNearby(Map<String, dynamic> params,
          {List<String>? fields, bool heldPhotos = false}) =>
      _search('searchNearby', params, fields, heldPhotos);

  static Future<Map<String, dynamic>> _search(
      String op,
      Map<String, dynamic> params,
      List<String>? fields,
      bool heldPhotos) async {
    final response = await gateway(op, {
      ...params,
      if (fields != null) 'fields': fields,
      if (heldPhotos) 'heldPhotos': true,
    });
    recordHeldPhotos(response['heldPhotos']);
    return response;
  }

  /// Takes in a search's `heldPhotos` map (`{placeId: [slots]}`). Anything
  /// else — an older gateway that did not send one — is ignored, which leaves
  /// those places "unknown" and the loader probing Storage as before.
  static void recordHeldPhotos(Object? held) {
    if (held is! Map) return;
    held.forEach((placeId, slots) {
      if (placeId is! String || slots is! List) return;
      _heldPhotoSlots[placeId] = {
        for (final s in slots)
          if (s is num) s.toInt(),
      };
    });
  }

  /// Photo slots the gateway said it stores, by place id, from the searches
  /// that asked. A place absent here has simply not been asked about.
  static final Map<String, Set<int>> _heldPhotoSlots = {};

  /// Whether the gateway already stores photo [slot] of [placeId]: true, false,
  /// or null when no search this session has said.
  ///
  /// A cold photo used to cost three requests in series — a Storage probe that
  /// answered 400 (~0.75 s), the `photo` op that stored it (~1.5 s), then the
  /// download. Knowing up front skips the probe for those, and still lets a
  /// held photo go straight to Storage without asking the gateway anything.
  static bool? isPhotoHeld(String placeId, int slot) =>
      _heldPhotoSlots[placeId]?.contains(slot);

  /// Records that the gateway has just stored photo [slot] of [placeId].
  static void notePhotoHeld(String placeId, int slot) =>
      (_heldPhotoSlots[placeId] ??= {}).add(slot);

  /// Google's Autocomplete; the result has Google's `suggestions` array.
  static Future<Map<String, dynamic>> autocomplete(
          Map<String, dynamic> params) =>
      gateway('autocomplete', params);

  /// The full Google Place for [placeId], or null when Google does not know
  /// the id.
  static Future<Map<String, dynamic>?> placeDetails(String placeId) async {
    final response = await gateway('details', {'placeId': placeId});
    if (response['notFound'] == true) return null;
    return response['place'] as Map<String, dynamic>?;
  }

  /// Where the gateway keeps photo [slot] of [placeId] once it holds it.
  ///
  /// The path is fixed by the gateway (`photos/<placeId>/<slot>.jpg`), so a
  /// photo already stored — nearly all of them, after the first person to see
  /// a place — can be fetched straight from Storage's CDN without first asking
  /// the gateway for its URL. That ask cost 0.8 s even when the gateway already
  /// had the photo, in series before every download. Storage answers 400 for a
  /// photo not stored yet (or stored as the rare PNG); [photo] covers both.
  static Uri storedPhotoUrl(String placeId, int slot) =>
      Uri.parse(Config.placesGatewayUrl).replace(
        pathSegments: [
          'storage',
          'v1',
          'object',
          'public',
          'photos',
          placeId,
          '$slot.jpg',
        ],
      );

  /// Photo [slot] of [placeId]: the image itself when the gateway has just
  /// bought it, its permanent public URL when the gateway already held it, or
  /// neither when it cannot be had.
  ///
  /// Asks the gateway, which buys and stores the photo if it has not yet. Try
  /// [storedPhotoUrl] first; this is the fallback.
  ///
  /// It asks with `bytes: true`. Without it, a photo the gateway had to buy
  /// came back as a URL and the app then downloaded, from a CDN that had not
  /// seen the file yet, the bytes the gateway had just held in memory: a
  /// second round trip, ~1 s, on every photo nobody had looked at before.
  ///
  /// A slot is the photo's index in that place's `photos` array — Google's
  /// photo resource names are minted fresh on every response, so they cannot
  /// identify a picture; the place id and index can.
  ///
  /// Never throws: a photo that cannot be had is a placeholder, not an error.
  static Future<({Uint8List? bytes, String? url})> photo(
      String placeId, int slot) {
    final key = '$placeId:$slot';
    final cached = _photoUrlCache[key];
    if (cached != null) return Future.value((bytes: null, url: cached));
    final pending = _photoRequests[key];
    if (pending != null) return pending;

    final request = () async {
      try {
        final result = await _withRetries(() async {
          final response = await appHttpClient
              .post(
                Uri.parse(Config.placesGatewayUrl),
                headers: {
                  'Content-Type': 'application/json',
                  'x-app-key': Config.placesGatewayKey,
                },
                body: jsonEncode({
                  'op': 'photo',
                  'placeId': placeId,
                  'slot': slot,
                  'bytes': true
                }),
              )
              .timeout(kPhotoTimeout);
          if (response.statusCode != 200) {
            throw PlacesApiException('photo', response.statusCode);
          }
          final type = response.headers['content-type'] ?? '';
          if (type.startsWith('image/')) {
            return (
              bytes: response.bodyBytes,
              url: response.headers['x-photo-url'],
            );
          }
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          final url = (json['photo'] as Map<String, dynamic>?)?['public_url']
              as String?;
          return (bytes: null, url: url);
        });
        // Only a real URL is worth remembering; caching a miss would make a
        // single transient failure permanent for the life of the process.
        final url = result.url;
        if (url != null && url.isNotEmpty) _photoUrlCache[key] = url;
        return result;
      } catch (_) {
        return (bytes: null, url: null);
      }
    }();
    _photoRequests[key] = request;
    // A block body: `=> remove(key)` would hand the removed future — this very
    // request — back to whenComplete, which would then wait on itself.
    request.whenComplete(() {
      _photoRequests.remove(key);
    });
    return request;
  }

  /// Runs [send], retrying transient failures with a short back-off. A
  /// [PlacesApiException] the server will keep rejecting propagates on the
  /// first attempt rather than costing the user two more round trips.
  static Future<T> _withRetries<T>(Future<T> Function() send) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await send();
      } catch (e) {
        final lastAttempt = attempt >= _maxAttempts - 1;
        final permanent = e is PlacesApiException && !e.isRetryable;
        if (lastAttempt || permanent) rethrow;
        await Future.delayed(_backoff[attempt.clamp(0, _backoff.length - 1)]);
      }
    }
  }
}
