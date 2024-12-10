import 'package:foodierank/services/proxy_service.dart';
import 'package:foodierank/config.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import '../services/navigation_service.dart';
import 'package:flutter/widgets.dart';

class RestaurantService {
  static final RestaurantService instance = RestaurantService._internal();
  List<Map<String, dynamic>>? _cachedRestaurants;
  final Map<String, Uint8List> _photoCache = {};
  
  factory RestaurantService() {
    return instance;
  }

  RestaurantService._internal();

  List<Map<String, dynamic>>? get cachedRestaurants => _cachedRestaurants;

  Future<List<Map<String, dynamic>>> fetchRestaurants(
    double latitude,
    double longitude,
    {String? priceLevel,
    String? cuisineType,
    bool openNow = true,
    String? searchQuery,
    void Function(int count, String type, double radius)? onSearchUpdate}
  ) async {
    _cachedRestaurants = await getNearbyRestaurants(
      latitude, 
      longitude,
      priceLevel: priceLevel,
      cuisineType: cuisineType != 'All' ? cuisineType : null,
      openNow: openNow,
      searchQuery: searchQuery,
      onSearchUpdate: onSearchUpdate,
    );
    
    // Immediately prefetch all primary photos
    if (_cachedRestaurants != null) {
      final headerPhotoRefs = _cachedRestaurants!
          .expand((r) => (r['photoRefs'] as List<dynamic>?)?.take(1) ?? [])
          .cast<String>()
          .toList();
      
      await prefetchHeaderPhotos(headerPhotoRefs);
    }
    
    return _cachedRestaurants!;
  }

  static const int _targetCount = 20;
  static const double _initialRadius = 500;
  static const double _minIncrement = 500;
  static const double _maxIncrement = 2000;
  static const double maxRadius = 5000;
  static const List<String> cuisineTypes = [
    'All', 'American', 'Asian', 'Bakery', 'Bar', 'BBQ', 'Bistro', 'Brazilian', 'British',
    'Brunch', 'Buffet', 'Burger', 'Coffee', 'Caribbean', 'Chinese', 'Deli', 'Diner',
    'French', 'Fusion', 'German', 'Greek', 'Hawaiian', 'Indian', 'Indonesian',
    'Italian', 'Japanese', 'Korean', 'Lebanese', 'Mediterranean', 'Mexican',
    'Moroccan', 'Noodles', 'Persian', 'Pizza', 'Pub', 'Ramen', 'Seafood',
    'Spanish', 'Steakhouse', 'Sushi', 'Tapas', 'Thai', 'Vegan', 'Vegetarian',
    'Vietnamese', 'Other'
  ];

  Future<List<Map<String, dynamic>>> getNearbyRestaurants(
    double latitude,
    double longitude,
    {String? priceLevel, 
    String? cuisineType, 
    bool openNow = true,
    String? searchQuery,
    void Function(int count, String type, double radius)? onSearchUpdate}
  ) async {
    if (latitude.isNaN || longitude.isNaN) {
      throw ArgumentError('Invalid coordinates provided');
    }

    double radius = _initialRadius;
    double currentIncrement = _minIncrement;
    final Set<String> foundIds = {};
    List<Map<String, dynamic>> allRestaurants = [];

    while (allRestaurants.length < _targetCount && radius <= maxRadius) {
      if (radius.isNaN || currentIncrement.isNaN) {
        break;
      }

      final params = _buildSearchParams(
        latitude,
        longitude,
        radius,
        cuisineType: cuisineType,
        priceLevel: priceLevel,
        openNow: openNow,
        searchQuery: searchQuery,
      );
      
      try {
        final response = await ProxyService.placesApiGet(
          'places:searchText',
          params,
          fieldMask: 'places.id,places.displayName,places.rating,places.userRatingCount,places.photos,places.priceLevel,places.types,places.formattedAddress,places.location,places.editorialSummary',
        );
        
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

          onSearchUpdate?.call(
            allRestaurants.length,
            cuisineType ?? 'restaurant',
            radius
          );

          if (places.isEmpty || newMatchingPlaces == 0) {
            radius += currentIncrement;
            currentIncrement = (currentIncrement * 1.5).clamp(_minIncrement, _maxIncrement);
          }
        } else {
          radius += currentIncrement;
          currentIncrement = (currentIncrement * 1.5).clamp(_minIncrement, _maxIncrement);
        }
      } catch (e) {
        rethrow;
      }

      if (currentIncrement.isNaN) {
        break;
      }
    }

    return allRestaurants;
  }

  Map<String, dynamic> _buildSearchParams(
    double latitude,
    double longitude,
    double radius,
    {String? cuisineType, String? priceLevel, bool openNow = true, String? searchQuery}
  ) {
    const double metersPerDegree = 111320.0;
    double halfRadiusDegrees = radius / metersPerDegree;

    if (latitude.isNaN || longitude.isNaN || radius.isNaN || halfRadiusDegrees.isNaN) {
      throw ArgumentError('Invalid parameters for search');
    }

    final params = {
      'textQuery': searchQuery?.isNotEmpty == true
          ? searchQuery
          : cuisineType != null && cuisineType != 'Other' 
            ? '$cuisineType restaurant'
            : 'restaurant',
      'locationRestriction': {
        'rectangle': {
          'low': {
            'latitude': latitude - halfRadiusDegrees,
            'longitude': longitude - halfRadiusDegrees,
          },
          'high': {
            'latitude': latitude + halfRadiusDegrees,
            'longitude': longitude + halfRadiusDegrees,
          },
        },
      },
      'maxResultCount': _targetCount,
      'languageCode': 'en',
      if (openNow) 'openNow': openNow,
      if (priceLevel != null) ...{
        'priceLevels': [_convertPriceLevel(priceLevel)],
      },
    };
    
    final lowLat = latitude - halfRadiusDegrees;
    final lowLng = longitude - halfRadiusDegrees;
    final highLat = latitude + halfRadiusDegrees;
    final highLng = longitude + halfRadiusDegrees;
    
    if (lowLat.isNaN || lowLng.isNaN || highLat.isNaN || highLng.isNaN) {
      throw ArgumentError('Invalid coordinate calculations');
    }
    
    return params;
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
    final photos = place['photos'] as List<dynamic>?;    final photoRefs = photos?.map((photo) => photo['name'] as String).toList() ?? [];
    
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
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> prefetchHeaderPhotos(List<String> photoRefs) async {
    await Future.wait(
      photoRefs.map((photoRef) async {
        if (!_photoCache.containsKey(photoRef)) {
          try {
            final photoBytes = await getPlacePhoto(photoRef);
            if (photoBytes != null) {
              _photoCache[photoRef] = photoBytes;
            }
          } catch (e) {
            // Silently handle error
          }
        }
      })
    );
  }

  Uint8List? getCachedPhoto(String photoRef) {
    return _photoCache[photoRef];
  }

  Future<void> loadAndCacheRestaurants() async {
    if (_cachedRestaurants != null) return;
    
    final restaurants = await fetchRestaurants(37.785834, -122.406417);
    final headerPhotoRefs = restaurants
        .expand((r) => (r['photoRefs'] as List<dynamic>?)?.take(1) ?? [])
        .cast<String>()
        .toList();
        
    // Wait for photo URLs to be cached
    await prefetchHeaderPhotos(headerPhotoRefs);
    
    // Preload images into memory
    for (final photoRef in headerPhotoRefs) {
      final photoBytes = getCachedPhoto(photoRef);
      if (photoBytes != null) {
        await precacheImage(
          MemoryImage(photoBytes),
          NavigationService.navigatorKey.currentContext!,
        );
      }
    }
  }
} 