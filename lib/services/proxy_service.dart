import 'dart:convert';

import '../config.dart';
import 'app_http.dart';

/// A non-2xx response from the Places API.
class PlacesApiException implements Exception {
  final String endpoint;
  final int statusCode;

  const PlacesApiException(this.endpoint, this.statusCode);

  /// Whether the same request could plausibly succeed on another attempt.
  ///
  /// A 400 or 403 means the request, the key, or the key's app restrictions are
  /// wrong, and will stay wrong; retrying three times with back-off only delays
  /// the same failure by several seconds. Rate limits and server faults are
  /// worth another go.
  bool get isRetryable => statusCode == 429 || statusCode >= 500;

  @override
  String toString() => 'Places API $endpoint failed with status $statusCode';
}

class ProxyService {
  static const String baseUrl = 'https://places.googleapis.com/v1';
  static final String _apiKey = Config.googleMapsApiKey;
  static final Map<String, String> _photoUrlCache = {};

  static const int _maxAttempts = 3;

  /// Back-off between attempts. Deliberately short — the caller is a user
  /// watching a spinner, and a search sector that ultimately fails contributes
  /// nothing rather than aborting the round.
  static const List<Duration> _backoff = [
    Duration(milliseconds: 400),
    Duration(milliseconds: 1200),
  ];

  /// POSTs to a Places API (New) search endpoint.
  static Future<Map<String, dynamic>> placesApiGet(
    String endpoint,
    Map<String, dynamic> params, {
    String? fieldMask,
  }) {
    final headers = {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': _apiKey,
      ...Config.appAttestationHeaders,
      if (fieldMask != null) 'X-Goog-FieldMask': fieldMask,
    };
    final body = jsonEncode(params);

    return _withRetries(endpoint, () async {
      final response = await appHttpClient
          .post(Uri.parse('$baseUrl/$endpoint'), headers: headers, body: body)
          .timeout(kRequestTimeout);

      if (response.statusCode != 200) {
        throw PlacesApiException(endpoint, response.statusCode);
      }
      return json.decode(response.body) as Map<String, dynamic>;
    });
  }

  /// Performs an HTTP GET against the Places API (New) — used for endpoints that
  /// are read-only, such as Place Details (`places/{placeId}`). Mirrors the
  /// headers and retry/back-off behaviour of [placesApiGet] (which, despite its
  /// name, issues a POST for the search endpoints).
  static Future<Map<String, dynamic>> placesApiGetDetails(
    String path, {
    required String fieldMask,
    Map<String, String>? queryParameters,
  }) {
    final headers = {
      'X-Goog-Api-Key': _apiKey,
      ...Config.appAttestationHeaders,
      'X-Goog-FieldMask': fieldMask,
    };
    final url =
        Uri.parse('$baseUrl/$path').replace(queryParameters: queryParameters);

    return _withRetries(path, () async {
      final response =
          await appHttpClient.get(url, headers: headers).timeout(kRequestTimeout);

      if (response.statusCode != 200) {
        throw PlacesApiException(path, response.statusCode);
      }
      return json.decode(response.body) as Map<String, dynamic>;
    });
  }

  /// Runs [send], retrying transient failures with a short back-off. A
  /// [PlacesApiException] the server will keep rejecting propagates on the
  /// first attempt rather than costing the user two more round trips.
  static Future<T> _withRetries<T>(
    String label,
    Future<T> Function() send,
  ) async {
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

  static Future<String> getPlacePhoto(
      String photoName, int width, int height) async {
    final cacheKey = '$photoName-$width-$height';
    final cached = _photoUrlCache[cacheKey];
    if (cached != null) return cached;

    try {
      final url = Uri.parse('$baseUrl/$photoName/media');
      final response = await appHttpClient.get(
        url.replace(queryParameters: {
          'maxWidthPx': width.toString(),
          'maxHeightPx': height.toString(),
          'skipHttpRedirect': 'true',
        }),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          ...Config.appAttestationHeaders,
        },
      ).timeout(kRequestTimeout);

      final data = jsonDecode(response.body);
      final photoUri = (data['photoUri'] as String?) ?? '';
      // Only a real URL is worth remembering; caching '' would make a single
      // transient failure permanent for the life of the process.
      if (photoUri.isNotEmpty) _photoUrlCache[cacheKey] = photoUri;
      return photoUri;
    } catch (e) {
      return '';
    }
  }
}
