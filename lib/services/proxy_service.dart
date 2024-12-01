import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import '../config.dart';

class ProxyService {
  static final _client = http.Client();
  static const String baseUrl = 'http://localhost:8080';
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
        final url = Uri.parse('$baseUrl/api/place/v1/$endpoint');
        
        final headers = {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
          if (fieldMask != null) 'X-Goog-FieldMask': fieldMask,
        };

        final response = await http.post(
          url,
          headers: headers,
          body: json.encode(params),
        );

        if (response.statusCode != 200) {
          throw Exception('Places API request failed with status ${response.statusCode}: ${response.body}');
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

  static Future<String> getPlacePhoto(String photoName, int width, int height) async {
    final cacheKey = '$photoName-$width-$height';
    if (_photoUrlCache.containsKey(cacheKey)) {
      return _photoUrlCache[cacheKey]!;
    }

    try {
      final url = Uri.parse('$baseUrl/api/place/v1/$photoName/media').replace(
        queryParameters: {
          'maxWidthPx': width.toString(),
          'maxHeightPx': height.toString(),
          'key': _apiKey,
          'skipHttpRedirect': 'true',
        },
      );

      final response = await _client.get(url);
      final data = jsonDecode(response.body);
      final photoUri = data['photoUri'] ?? '';
      _photoUrlCache[cacheKey] = photoUri;
      return photoUri;
    } catch (e) {
      return '';
    }
  }
}
