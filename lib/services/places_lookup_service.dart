import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'proxy_service.dart';
import 'api_usage_tracker.dart';

/// A single autocomplete suggestion.
class PlacePrediction {
  final String placeId;
  final String mainText;
  final String secondaryText;

  const PlacePrediction({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
  });
}

/// A resolved place / location the user can search around.
class PlaceResult {
  final double lat;
  final double lng;
  final String label;
  final String address;

  const PlaceResult({
    required this.lat,
    required this.lng,
    required this.label,
    this.address = '',
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'label': label,
        'address': address,
      };

  factory PlaceResult.fromJson(Map<String, dynamic> json) => PlaceResult(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        label: json['label'] as String? ?? '',
        address: json['address'] as String? ?? '',
      );
}

/// Resolves places for the "search a different location" flow: autocomplete
/// predictions, place details (→ coordinates), reverse-geocoding a dropped map
/// pin, and a small persisted list of recent locations.
///
/// Reuses [ProxyService] (the same Places API New REST client the restaurant
/// search uses) so no new key or endpoint host is introduced for autocomplete
/// and details.
class PlaceLookupService {
  static final PlaceLookupService instance = PlaceLookupService._internal();
  PlaceLookupService._internal();

  static const String _recentsKey = 'recent_search_locations';
  static const int _maxRecents = 6;

  /// Autocomplete session tokens group as-you-type requests with the final
  /// details fetch for billing; a token is minted per picker session.
  static String newSessionToken() {
    final rand = Random();
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(rand.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }

  /// Live predictions for [input]. Returns an empty list on blank input or error
  /// (the picker degrades gracefully rather than surfacing a network error).
  Future<List<PlacePrediction>> autocomplete(
    String input, {
    required String sessionToken,
    double? biasLat,
    double? biasLng,
  }) async {
    if (input.trim().isEmpty) return const [];

    try {
      final params = <String, dynamic>{
        'input': input,
        'sessionToken': sessionToken,
        'languageCode': 'en',
        if (biasLat != null && biasLng != null)
          'locationBias': {
            'circle': {
              'center': {'latitude': biasLat, 'longitude': biasLng},
              'radius': 50000.0,
            },
          },
      };

      ApiUsageTracker.instance.incrementTextSearch();
      final response = await ProxyService.placesApiGet(
        'places:autocomplete',
        params,
        fieldMask:
            'suggestions.placePrediction.placeId,suggestions.placePrediction.text,suggestions.placePrediction.structuredFormat',
      );

      final suggestions =
          (response['suggestions'] as List<dynamic>?) ?? const [];
      final results = <PlacePrediction>[];
      for (final s in suggestions) {
        final p = (s as Map<String, dynamic>)['placePrediction']
            as Map<String, dynamic>?;
        if (p == null) continue;
        final placeId = p['placeId'] as String?;
        if (placeId == null) continue;

        final structured = p['structuredFormat'] as Map<String, dynamic>?;
        final mainText =
            (structured?['mainText'] as Map<String, dynamic>?)?['text']
                    as String? ??
                (p['text'] as Map<String, dynamic>?)?['text'] as String? ??
                '';
        final secondaryText =
            (structured?['secondaryText'] as Map<String, dynamic>?)?['text']
                    as String? ??
                '';

        results.add(PlacePrediction(
          placeId: placeId,
          mainText: mainText,
          secondaryText: secondaryText,
        ));
      }
      return results;
    } catch (_) {
      return const [];
    }
  }

  /// Resolves a chosen prediction to coordinates. Returns null on failure.
  Future<PlaceResult?> placeDetails(
    String placeId, {
    String? sessionToken,
  }) async {
    try {
      final response = await ProxyService.placesApiGetDetails(
        'places/$placeId',
        fieldMask: 'displayName,formattedAddress,location',
        queryParameters:
            sessionToken != null ? {'sessionToken': sessionToken} : null,
      );

      final location = response['location'] as Map<String, dynamic>?;
      final lat = (location?['latitude'] as num?)?.toDouble();
      final lng = (location?['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;

      final name =
          (response['displayName'] as Map<String, dynamic>?)?['text']
                  as String? ??
              '';
      final address = response['formattedAddress'] as String? ?? '';

      return PlaceResult(
        lat: lat,
        lng: lng,
        label: name.isNotEmpty ? name : address,
        address: address,
      );
    } catch (_) {
      return null;
    }
  }

  /// Best-effort reverse geocode of a dropped map pin. Uses the classic
  /// Geocoding API (same key/host family the app already uses for map media);
  /// on any failure it falls back to a coordinate label so the picker still
  /// works even if the Geocoding API is not enabled on the key.
  Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final uri = Uri.parse('${Config.baseUrl}/geocode/json').replace(
        queryParameters: {
          'latlng': '$lat,$lng',
          'key': Config.googleMapsApiKey,
        },
      );

      final client = http.Client();
      try {
        final response = await client.get(
          uri,
          headers: {
            ...Config.appAttestationHeaders,
            'User-Agent': 'FoodieRank/1.0',
          },
        ).timeout(const Duration(seconds: 6));

        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final results = data['results'] as List<dynamic>?;
          if (results != null && results.isNotEmpty) {
            final addr = (results.first as Map<String, dynamic>)['formatted_address']
                as String?;
            if (addr != null && addr.isNotEmpty) return addr;
          }
        }
      } finally {
        client.close();
      }
    } catch (_) {
      // fall through to coordinate label
    }
    return 'Pinned location (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
  }

  // --- Recent locations (persisted) ----------------------------------------

  Future<List<PlaceResult>> getRecents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_recentsKey) ?? const [];
      return raw
          .map((s) => PlaceResult.fromJson(
              json.decode(s) as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> addRecent(PlaceResult place) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_recentsKey) ?? <String>[];
      // De-duplicate by label, newest first, capped.
      final decoded = existing
          .map((s) => PlaceResult.fromJson(
              json.decode(s) as Map<String, dynamic>))
          .where((p) => p.label != place.label)
          .toList();
      decoded.insert(0, place);
      final trimmed = decoded.take(_maxRecents).toList();
      await prefs.setStringList(
        _recentsKey,
        trimmed.map((p) => json.encode(p.toJson())).toList(),
      );
    } catch (_) {
      // recents are a convenience; ignore persistence failures
    }
  }
}
