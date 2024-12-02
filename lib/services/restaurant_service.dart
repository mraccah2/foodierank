import 'package:foodierank/services/proxy_service.dart';
import 'package:foodierank/config.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'package:flutter/material.dart' show TimeOfDay;

class RestaurantService {
  static const int _targetCount = 20;
  static const double _initialRadius = 500;
  static const double _minIncrement = 500;
  static const double _maxIncrement = 2000;
  static const double _maxRadius = 5000;
  static const int _lowResultsThreshold = 3;
  static const List<String> cuisineTypes = [
    'American', 'Asian', 'Bakery', 'Bar', 'BBQ', 'Bistro', 'Brazilian', 'British',
    'Brunch', 'Buffet', 'Burger', 'Cafe', 'Caribbean', 'Chinese', 'Deli', 'Diner',
    'French', 'Fusion', 'German', 'Greek', 'Hawaiian', 'Indian', 'Indonesian',
    'Italian', 'Japanese', 'Korean', 'Lebanese', 'Mediterranean', 'Mexican',
    'Moroccan', 'Noodles', 'Persian', 'Pizza', 'Pub', 'Ramen', 'Seafood',
    'Spanish', 'Steakhouse', 'Sushi', 'Tapas', 'Thai', 'Vegan', 'Vegetarian',
    'Vietnamese', 'Other'
  ];

  Future<List<Map<String, dynamic>>> getNearbyRestaurants(
    double latitude,
    double longitude,
    {String? priceLevel, String? cuisineType, String? openDay, TimeOfDay? openTime}
  ) async {
    print('dBug/restaurant_service: Starting search with lat:$latitude, lng:$longitude, price:$priceLevel, cuisine:$cuisineType');
    
    double radius = _initialRadius;
    double currentIncrement = _minIncrement;
    final Set<String> foundIds = {};
    List<Map<String, dynamic>> allRestaurants = [];

    while (allRestaurants.length < _targetCount && radius <= _maxRadius) {
      final params = _buildSearchParams(
        latitude,
        longitude,
        radius,
        cuisineType: cuisineType,
        priceLevel: priceLevel,
      );
      
      print('dBug/restaurant_service: API request params: $params');

      try {
        final response = await ProxyService.placesApiGet(
          'places:searchText',
          params,
          fieldMask: 'places.id,places.displayName,places.rating,places.userRatingCount,places.photos,places.priceLevel,places.types,places.formattedAddress,places.location,places.editorialSummary',
        );
        
        print('dBug/restaurant_service: API response received: ${response.containsKey('places') ? '${response['places'].length} places found' : 'No places key in response'}');

        if (response.containsKey('places')) {
          final List<dynamic> places = response['places'];
          int newMatchingPlaces = 0;

          for (final place in places) {
            final id = place['id'] as String;
            if (!foundIds.contains(id)) {
              final mappedPlace = _mapPlace(place, priceLevel);
              if (mappedPlace != null) {
                foundIds.add(id);
                allRestaurants.add(mappedPlace);
                newMatchingPlaces++;
              }
            }
          }

          print('dBug/restaurant_service: Found $newMatchingPlaces new matching places, total: ${allRestaurants.length}');

          if (newMatchingPlaces < _lowResultsThreshold) {
            currentIncrement = (currentIncrement * 1.5).clamp(_minIncrement, _maxIncrement);
            radius += currentIncrement;
            print('dBug/restaurant_service: Low results, expanding radius to $radius meters');
          } else if (allRestaurants.length < _targetCount) {
            radius += _minIncrement;
            print('dBug/restaurant_service: Normal expansion, new radius: $radius meters');
          }
        }
      } catch (e) {
        print('dBug/restaurant_service: Error in API call: $e');
        rethrow;
      }
    }

    print('dBug/restaurant_service: Search completed. Found ${allRestaurants.length} restaurants');
    return allRestaurants;
  }

  Map<String, dynamic> _buildSearchParams(
    double latitude,
    double longitude,
    double radius,
    {String? cuisineType, String? priceLevel}
  ) {
    return {
      'textQuery': cuisineType != null && cuisineType != 'Other' 
        ? '$cuisineType restaurant'
        : 'restaurant',
      'locationBias': {
        'circle': {
          'center': {
            'latitude': latitude,
            'longitude': longitude,
          },
          'radius': radius,
        },
      },
      'includedType': 'restaurant',
      'maxResultCount': _targetCount,
      'languageCode': 'en',
      if (priceLevel != null) ...{
        'priceLevels': [_convertPriceLevel(priceLevel)],
      },
    };
  }

  String _convertPriceLevel(String priceLevel) {
    switch (priceLevel) {
      case '\$': return 'PRICE_LEVEL_INEXPENSIVE';
      case '\$\$': return 'PRICE_LEVEL_MODERATE';
      case '\$\$\$': return 'PRICE_LEVEL_EXPENSIVE';
      case '\$\$\$\$': return 'PRICE_LEVEL_VERY_EXPENSIVE';
      default: return '';
    }
  }

  Map<String, dynamic>? _mapPlace(Map<String, dynamic> place, String? targetPriceLevel) {
    // First convert the API price level to our format ($, $$, etc)
    final placePrice = getPriceLevel(place['priceLevel']);
    
    // If we have a target price level, only include exact matches
    if (targetPriceLevel != null && placePrice != targetPriceLevel) {
      return null;
    }

    final photos = place['photos'] as List<dynamic>?;
    final photoRefs = photos?.map((photo) => photo['name'] as String).toList() ?? [];
    
    return {
      ...Map<String, dynamic>.from(place),
      'photoRefs': photoRefs,
    };
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
      final uri = Uri.parse('${ProxyService.baseUrl}/$photoName/media');
      
      final response = await http.get(
        uri.replace(queryParameters: {
          'maxWidthPx': maxWidth.toString(),
          'maxHeightPx': maxHeight.toString(),
        }),
        headers: {
          'X-Goog-Api-Key': Config.googleMapsApiKey,
          'Accept': 'image/*',
        },
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      print('dBug/restaurant_service: Photo fetch failed with status: ${response.statusCode}');
      return null;
    } catch (e) {
      print('dBug/restaurant_service: Error fetching photo: $e');
      return null;
    }
  }
} 