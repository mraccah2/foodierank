import 'package:foodierank/services/proxy_service.dart';
import 'package:foodierank/config.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';

class RestaurantService {
  /// Retrieves a list of nearby restaurants based on location and radius
  Future<List<Map<String, dynamic>>> getNearbyRestaurants(
      double latitude, double longitude, double radius) async {
    final params = {
      'locationRestriction': {
        'circle': {
          'center': {
            'latitude': latitude,
            'longitude': longitude,
          },
          'radius': radius,
        },
      },
      'includedTypes': ['restaurant'],
      'maxResultCount': 20,
      'languageCode': 'en',
    };

    try {
      final response = await ProxyService.placesApiGet(
        'places:searchNearby',
        params,
        fieldMask: 'places.id,places.displayName,places.rating,places.userRatingCount,places.photos,places.priceLevel,places.types,places.formattedAddress,places.location,places.editorialSummary',
      );

      if (response.containsKey('places')) {
        final List<dynamic> places = response['places'];
        return places.map((place) {
          final name = place['displayName']?['text'] ?? 'Unknown';
          final editorialSummary = place['editorialSummary'];
          
          // Extract photo references from the photos array
          final photos = place['photos'] as List<dynamic>?;
          final photoRefs = photos?.map((photo) => photo['name'] as String).toList() ?? [];
          
          final mappedPlace = <String, dynamic>{
            ...Map<String, dynamic>.from(place),
            'photoRefs': photoRefs,
          };
          
          return mappedPlace;
        }).toList();
      }
      return [];

    } catch (e) {
      rethrow;
    }
  }

  String getPriceLevel(String? priceLevel) {
    switch (priceLevel) {
      case 'PRICE_LEVEL_FREE':
        return '';
      case 'PRICE_LEVEL_INEXPENSIVE':
        return '\$';
      case 'PRICE_LEVEL_MODERATE':
        return '\$\$';
      case 'PRICE_LEVEL_EXPENSIVE':
        return '\$\$\$';
      case 'PRICE_LEVEL_VERY_EXPENSIVE':
        return '\$\$\$\$';
      default:
        return '';
    }
  }

  Future<Uint8List?> getPlacePhoto(String photoName, {int maxWidth = 800, int maxHeight = 450}) async {
    try {
      final uri = Uri.parse('${ProxyService.baseUrl}/api/place/v1/${photoName}/media').replace(
        queryParameters: {
          'maxWidthPx': maxWidth.toString(),
          'maxHeightPx': maxHeight.toString(),
          'key': Config.googleMapsApiKey,
        },
      );
      
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'image/*',
        },
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
} 