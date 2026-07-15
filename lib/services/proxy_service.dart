import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import '../config.dart';

class ProxyService {
  static final _client = http.Client();
  static const String baseUrl = 'https://places.googleapis.com/v1';
  static final String _apiKey = Config.googleMapsApiKey;
  static final Map<String, String> _photoUrlCache = {};

  static Future<Map<String, dynamic>> placesApiGet(
    String endpoint,
    Map<String, dynamic> params, {
    String? fieldMask,
  }) async {
    int retryCount = 0;
    const int maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        final url = Uri.parse('$baseUrl/$endpoint');

        final headers = {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          ...Config.appAttestationHeaders,
          if (fieldMask != null) 'X-Goog-FieldMask': fieldMask,
        };

        final body = jsonEncode(params);

        final response = await http.post(url, headers: headers, body: body);

        if (response.statusCode != 200) {
          throw Exception('Request failed with status: ${response.statusCode}');
        }

        return json.decode(response.body);
      } catch (e) {
        retryCount++;
        if (retryCount < maxRetries) {
          final delay = Duration(seconds: pow(2, retryCount).toInt());
          await Future.delayed(delay);
          continue;
        }
        rethrow;
      }
    }
    throw Exception('Failed to get response after $maxRetries attempts');
  }

  /// Performs an HTTP GET against the Places API (New) — used for endpoints that
  /// are read-only, such as Place Details (`places/{placeId}`). Mirrors the
  /// headers and retry/back-off behaviour of [placesApiGet] (which, despite its
  /// name, issues a POST for the search endpoints).
  static Future<Map<String, dynamic>> placesApiGetDetails(
    String path, {
    required String fieldMask,
    Map<String, String>? queryParameters,
  }) async {
    int retryCount = 0;
    const int maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        final url = Uri.parse('$baseUrl/$path').replace(
          queryParameters: queryParameters,
        );

        final headers = {
          'X-Goog-Api-Key': _apiKey,
          ...Config.appAttestationHeaders,
          'X-Goog-FieldMask': fieldMask,
        };

        final response = await _client.get(url, headers: headers);

        if (response.statusCode != 200) {
          throw Exception('Request failed with status: ${response.statusCode}');
        }

        return json.decode(response.body) as Map<String, dynamic>;
      } catch (e) {
        retryCount++;
        if (retryCount < maxRetries) {
          final delay = Duration(seconds: pow(2, retryCount).toInt());
          await Future.delayed(delay);
          continue;
        }
        rethrow;
      }
    }
    throw Exception('Failed to get response after $maxRetries attempts');
  }

  static Future<String> getPlacePhoto(
      String photoName, int width, int height) async {
    final cacheKey = '$photoName-$width-$height';
    if (_photoUrlCache.containsKey(cacheKey)) {
      return _photoUrlCache[cacheKey]!;
    }

    try {
      final url = Uri.parse('$baseUrl/$photoName/media');
      final headers = {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': _apiKey,
        ...Config.appAttestationHeaders,
      };

      final response = await _client.get(
        url.replace(queryParameters: {
          'maxWidthPx': width.toString(),
          'maxHeightPx': height.toString(),
          'skipHttpRedirect': 'true',
        }),
        headers: headers,
      );

      final data = jsonDecode(response.body);
      final photoUri = data['photoUri'] ?? '';
      _photoUrlCache[cacheKey] = photoUri;
      return photoUri;
    } catch (e) {
      return '';
    }
  }
}
