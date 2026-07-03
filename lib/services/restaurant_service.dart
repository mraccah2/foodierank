import 'package:foodierank/services/proxy_service.dart';
import 'package:foodierank/config.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import '../services/navigation_service.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';
import 'dart:math';
import 'api_usage_tracker.dart';

class RestaurantService {
  static final RestaurantService instance = RestaurantService._internal();
  List<Map<String, dynamic>>? _cachedRestaurants;
  final Map<String, Uint8List> _photoCache = {};
  DateTime? _lastFetchTime;
  double? _lastFetchLatitude;
  double? _lastFetchLongitude;

  factory RestaurantService() {
    return instance;
  }

  RestaurantService._internal();

  List<Map<String, dynamic>>? get cachedRestaurants => _cachedRestaurants;

  Future<List<Map<String, dynamic>>> fetchRestaurants(
      double latitude, double longitude,
      {List<String>? priceLevels,
      String? cuisineType,
      bool openNow = true,
      String? searchQuery,
      void Function(int count, String type, double radius)?
          onSearchUpdate}) async {
    _lastFetchTime = DateTime.now();
    _lastFetchLatitude = latitude;
    _lastFetchLongitude = longitude;

    _cachedRestaurants = await getNearbyRestaurants(
      latitude,
      longitude,
      priceLevels: priceLevels,
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
  static const double _initialRadius = 1000; // start ~1km
  static const double _radiusGrowth = 2.0; // double the search radius each round
  static const double maxRadius = 100000; // safety cap (~100km) for remote areas
  static const List<String> cuisineTypes = [
    'All',
    'American',
    'Asian',
    'Bakery',
    'Bar',
    'BBQ',
    'Bistro',
    'Brazilian',
    'British',
    'Brunch',
    'Buffet',
    'Burger',
    'Coffee',
    'Caribbean',
    'Chinese',
    'Deli',
    'Diner',
    'French',
    'Fusion',
    'German',
    'Greek',
    'Hawaiian',
    'Indian',
    'Indonesian',
    'Italian',
    'Japanese',
    'Korean',
    'Lebanese',
    'Mediterranean',
    'Mexican',
    'Moroccan',
    'Noodles',
    'Persian',
    'Pizza',
    'Pub',
    'Ramen',
    'Seafood',
    'Spanish',
    'Steakhouse',
    'Sushi',
    'Tapas',
    'Thai',
    'Vegan',
    'Vegetarian',
    'Vietnamese',
    'Other'
  ];

  Future<List<Map<String, dynamic>>> getNearbyRestaurants(
      double latitude, double longitude,
      {List<String>? priceLevels,
      String? cuisineType,
      bool openNow = true,
      String? searchQuery,
      void Function(int count, String type, double radius)?
          onSearchUpdate}) async {
    if (latitude.isNaN || longitude.isNaN) {
      throw ArgumentError('Invalid coordinates provided');
    }

    double radius = _initialRadius;
    final Set<String> foundIds = {};
    final List<Map<String, dynamic>> allRestaurants = [];

    // Keep widening the search until we have enough places or we hit the
    // safety cap. Dense areas are satisfied on the first (smallest) round;
    // rural areas keep doubling the radius outward until they reach the
    // nearest populated towns.
    while (allRestaurants.length < _targetCount) {
      if (radius.isNaN) break;

      final params = _buildSearchParams(
        latitude,
        longitude,
        radius,
        cuisineType: cuisineType,
        priceLevels: priceLevels,
        openNow: openNow,
        searchQuery: searchQuery,
      );

      ApiUsageTracker.instance.incrementTextSearch();
      final response = await ProxyService.placesApiGet(
        'places:searchText',
        params,
        fieldMask:
            'places.id,places.displayName,places.rating,places.userRatingCount,places.photos,places.priceLevel,places.types,places.formattedAddress,places.location,places.editorialSummary',
      );

      final places = (response['places'] as List<dynamic>?) ?? const [];
      for (final place in places) {
        final id = place['id'] as String?;
        if (id == null || foundIds.contains(id)) continue;
        try {
          final mappedPlace =
              _mapPlace(place as Map<String, dynamic>, priceLevels);
          if (mappedPlace != null) {
            foundIds.add(id);
            allRestaurants.add(mappedPlace);
          }
        } catch (_) {
          // Skip a place with unexpected/missing fields rather than aborting
          // the whole search.
        }
      }

      onSearchUpdate?.call(
          allRestaurants.length, cuisineType ?? 'restaurant', radius);

      // Stop once we have enough, or once we've already searched at the
      // maximum radius (truly remote — return whatever we found).
      if (allRestaurants.length >= _targetCount || radius >= maxRadius) break;
      radius = (radius * _radiusGrowth).clamp(_initialRadius, maxRadius);
    }

    return allRestaurants;
  }

  Map<String, dynamic> _buildSearchParams(
      double latitude, double longitude, double radius,
      {String? cuisineType,
      List<String>? priceLevels,
      bool openNow = true,
      String? searchQuery}) {
    const double metersPerDegree = 111320.0;
    double halfRadiusDegrees = radius / metersPerDegree;

    if (latitude.isNaN ||
        longitude.isNaN ||
        radius.isNaN ||
        halfRadiusDegrees.isNaN) {
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
      if (priceLevels != null) ...{
        'priceLevels': priceLevels,
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

  Map<String, dynamic>? _mapPlace(
      Map<String, dynamic> place, List<String>? targetPriceLevels) {
    final photos = place['photos'] as List<dynamic>?;
    final photoRefs =
        photos?.map((photo) => photo['name'] as String).toList() ?? [];

    // Extract country from formatted address
    final formattedAddress = place['formattedAddress'] as String;
    final country = formattedAddress.split(',').last.trim();

    return {
      ...Map<String, dynamic>.from(place),
      'photoRefs': photoRefs,
      'location': {
        ...place['location'] as Map<String, dynamic>,
        'country': country,
      },
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

  Future<Uint8List?> getPlacePhoto(String photoName,
      {int maxWidth = 800, int maxHeight = 450}) async {
    ApiUsageTracker.instance.incrementPhoto();
    try {
      final uri = Uri.parse('${ProxyService.baseUrl}/$photoName/media');

      final client = http.Client();
      try {
        final response = await client.get(
          uri.replace(queryParameters: {
            'maxWidthPx': maxWidth.toString(),
            'maxHeightPx': maxHeight.toString(),
            'key': Config.googleMapsApiKey,
          }),
          headers: {
            'X-Goog-Api-Key': Config.googleMapsApiKey,
            ...Config.appAttestationHeaders,
            'Accept': 'image/*',
            'User-Agent': 'FoodieRank/1.0',
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) return response.bodyBytes;
        return null;
      } finally {
        client.close();
      }
    } catch (e) {
      return null;
    }
  }

  Future<void> prefetchHeaderPhotos(List<String> photoRefs) async {
    await Future.wait(photoRefs.map((photoRef) async {
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
    }));
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

  bool shouldRefreshData(double currentLat, double currentLng) {
    if (_lastFetchTime == null ||
        _lastFetchLatitude == null ||
        _lastFetchLongitude == null) {
      return true;
    }

    // Check if more than an hour has passed
    final timeDifference = DateTime.now().difference(_lastFetchTime!);
    if (timeDifference.inHours >= 1) {
      return true;
    }

    // Calculate distance from last fetch location
    final distance = _calculateDistance(
        _lastFetchLatitude!, _lastFetchLongitude!, currentLat, currentLng);

    // Return true if more than 300m away
    return distance > 300;
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371e3; // Earth's radius in meters
    final phi1 = lat1 * pi / 180;
    final phi2 = lat2 * pi / 180;
    final deltaPhi = (lat2 - lat1) * pi / 180;
    final deltaLambda = (lon2 - lon1) * pi / 180;

    final a = sin(deltaPhi / 2) * sin(deltaPhi / 2) +
        cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c; // Distance in meters
  }

  String? findPrimaryCuisine(List<String> types, {String? country}) {
    // Common cuisine keywords that appear in Google Places types
    final cuisineKeywords = {
      'afghani',
      'african',
      'american',
      'arabic',
      'argentinian',
      'asian',
      'australian',
      'austrian',
      'bbq',
      'barbeque',
      'belgian',
      'brazilian',
      'british',
      'caribbean',
      'chinese',
      'colombian',
      'croatian',
      'cuban',
      'czech',
      'danish',
      'ethiopian',
      'filipino',
      'finnish',
      'french',
      'georgian',
      'german',
      'greek',
      'hungarian',
      'indian',
      'indonesian',
      'irish',
      'israeli',
      'italian',
      'jamaican',
      'japanese',
      'korean',
      'latin',
      'lebanese',
      'malaysian',
      'malay',
      'mediterranean',
      'mexican',
      'middle_eastern',
      'moroccan',
      'nepalese',
      'nigerian',
      'norwegian',
      'pakistani',
      'peruvian',
      'persian',
      'pizza',
      'polish',
      'portuguese',
      'romanian',
      'russian',
      'scandinavian',
      'scottish',
      'seafood',
      'singaporean',
      'south_african',
      'sushi',
      'spanish',
      'swedish',
      'swiss',
      'taiwanese',
      'thai',
      'turkish',
      'ukrainian',
      'uruguayan',
      'vegetarian',
      'venezuelan',
      'vietnamese',
      'welsh'
    };

    // First pass: check for compound types
    for (var type in types) {
      final normalizedType = type.toLowerCase();
      final baseCuisine = normalizedType.split('_').first;
      if (cuisineKeywords.contains(baseCuisine)) {
        return baseCuisine;
      }
    }

    // Second pass: direct match with cuisine keywords
    for (var type in types) {
      final normalizedType = type.toLowerCase();
      if (cuisineKeywords.contains(normalizedType)) {
        return type;
      }
    }

    // Modified: If using country-based default, append a question mark
    if (country != null) {
      final defaultCuisine = getDefaultCuisineByLocation(country);
      if (defaultCuisine != null) {
        return '$defaultCuisine?'; // Add question mark to indicate it's a guess
      }
    }

    return null;
  }

  String formatCuisineDisplay(String cuisine) {
    return cuisine
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  String? getDefaultCuisineByLocation(String country) {
    // Map of countries to their primary cuisine
    final Map<String, String> countryCuisineMap = {
      'Afghanistan': 'afghan',
      'Argentina': 'argentinian',
      // ... (keep all the existing country mappings)
      'Spain': 'spanish',
      // ... (keep all the remaining mappings)
    };

    return countryCuisineMap[country];
  }
}
