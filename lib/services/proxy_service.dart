import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import '../config.dart';

class ProxyService {
  static final _client = http.Client();
  static final String baseUrl = 'https://places.googleapis.com/v1';
  static const String _apiKey = Config.googleMapsApiKey;
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
          if (fieldMask != null) 'X-Goog-FieldMask': fieldMask,
        };
        final body = jsonEncode(params);

        print('dBug/proxy_service: Making request to ${url.toString()}');
        final response = await http.post(url, headers: headers, body: body);
        print('dBug/proxy_service: Response status: ${response.statusCode}');
        print('dBug/proxy_service: Response body: ${response.body.substring(0, min(200, response.body.length))}...');

        if (response.statusCode != 200) {
          throw Exception('Request failed with status: ${response.statusCode}');
        }

        return json.decode(response.body);

      } catch (e) {
        print('dBug/proxy_service: Error: $e');
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

  static Future<String> getPlacePhoto(String photoName, int width, int height) async {
    final cacheKey = '$photoName-$width-$height';
    if (_photoUrlCache.containsKey(cacheKey)) {
      return _photoUrlCache[cacheKey]!;
    }

    try {
      final url = Uri.parse('$baseUrl/$photoName/media');
      final headers = {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': _apiKey,
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
      print('dBug/proxy_service: Error fetching photo: $e');
      return '';
    }
  }
}
