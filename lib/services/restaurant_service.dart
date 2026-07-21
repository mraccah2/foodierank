import 'package:foodierank/services/proxy_service.dart';
import 'package:foodierank/config.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
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
  String? _lastContextKey;

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
      int? targetDay,
      int? targetMinutes,
      String? contextKey,
      void Function(int count, String type, double radius)?
          onSearchUpdate}) async {
    _lastFetchTime = DateTime.now();
    _lastFetchLatitude = latitude;
    _lastFetchLongitude = longitude;
    _lastContextKey = contextKey;

    _cachedRestaurants = await getNearbyRestaurants(
      latitude,
      longitude,
      priceLevels: priceLevels,
      cuisineType: cuisineType != 'All' ? cuisineType : null,
      openNow: openNow,
      searchQuery: searchQuery,
      targetDay: targetDay,
      targetMinutes: targetMinutes,
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
  static const int _sectorsPerSide = 2; // query the box as a 2×2 grid

  // Locality-signal tuning (see _applyLocalityScores).
  static const double _neighborhoodRadius = 500; // meters
  static const double _maxDestinationExcess = 1.5; // log-review units
  static const double _poiPenaltyRadius = 250; // meters
  static const double _attractionWeight = 0.25; // per attraction within radius
  static const double _hotelWeight = 0.12; // per hotel within radius
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
      int? targetDay,
      int? targetMinutes,
      void Function(int count, String type, double radius)?
          onSearchUpdate}) async {
    if (latitude.isNaN || longitude.isNaN) {
      throw ArgumentError('Invalid coordinates provided');
    }

    // "Custom time" means the user asked for a specific day/time-of-day rather
    // than "open now". The Places `openNow` filter only knows the present, so we
    // must instead request each place's opening hours and filter client-side.
    final bool customTime = targetDay != null && targetMinutes != null;

    // Opening-hours fields are a billable Enterprise-SKU add-on, so only request
    // them when a custom time is active; the default "open now" path keeps its
    // cheaper field mask unchanged.
    const String baseFieldMask =
        'places.id,places.displayName,places.rating,places.userRatingCount,places.photos,places.priceLevel,places.types,places.formattedAddress,places.location,places.editorialSummary';
    final String fieldMask = customTime
        ? '$baseFieldMask,places.regularOpeningHours,places.utcOffsetMinutes'
        : baseFieldMask;

    double radius = _initialRadius;
    final Set<String> foundIds = {};
    final List<Map<String, dynamic>> allRestaurants = [];

    // Keep widening the search until we have enough places or we hit the
    // safety cap. Dense areas are satisfied on the first (smallest) round;
    // rural areas keep doubling the radius outward until they reach the
    // nearest populated towns. With a custom time we count only the places that
    // are open at that time toward the target.
    while (allRestaurants.length < _targetCount) {
      if (radius.isNaN) break;

      // Text Search ranks by Google's own "prominence" within the requested
      // box, so one big query in a touristy city fills all 20 slots with the
      // famous places. Querying each sector of the box separately forces every
      // quarter of the map to contribute its own local best, letting
      // lower-prominence neighborhoods into the pool. A sector that fails
      // (after ProxyService's retries) contributes nothing rather than
      // aborting the round.
      final responses = await Future.wait(
        _sectorRects(latitude, longitude, radius).map((rect) {
          ApiUsageTracker.instance.incrementTextSearch();
          return ProxyService.placesApiGet(
            'places:searchText',
            _buildSearchParams(
              rect,
              cuisineType: cuisineType,
              priceLevels: priceLevels,
              // With a custom time we drop the server-side open filter and
              // evaluate opening hours ourselves.
              openNow: customTime ? false : openNow,
              searchQuery: searchQuery,
            ),
            fieldMask: fieldMask,
          ).catchError((_) => <String, dynamic>{});
        }),
      );

      for (final response in responses) {
        final places = (response['places'] as List<dynamic>?) ?? const [];
        for (final place in places) {
          final id = place['id'] as String?;
          if (id == null || foundIds.contains(id)) continue;
          foundIds.add(id); // mark seen so later, wider rounds skip it
          try {
            final mappedPlace =
                _mapPlace(place as Map<String, dynamic>, priceLevels);
            if (mappedPlace == null) continue;

            if (customTime) {
              final periods = (mappedPlace['regularOpeningHours']
                  as Map<String, dynamic>?)?['periods'] as List<dynamic>?;
              if (!isOpenAt(periods, targetDay, targetMinutes)) continue;
            }

            allRestaurants.add(mappedPlace);
          } catch (_) {
            // Skip a place with unexpected/missing fields rather than aborting
            // the whole search.
          }
        }
      }

      onSearchUpdate?.call(
          allRestaurants.length, cuisineType ?? 'restaurant', radius);

      // Stop once we have enough, or once we've already searched at the
      // maximum radius (truly remote — return whatever we found).
      if (allRestaurants.length >= _targetCount || radius >= maxRadius) break;
      radius = (radius * _radiusGrowth).clamp(_initialRadius, maxRadius);
    }

    await _applyLocalityScores(allRestaurants, latitude, longitude, radius);

    return allRestaurants;
  }

  /// Splits the square search box of [radius] meters around the center into a
  /// [_sectorsPerSide]×[_sectorsPerSide] grid of sub-rectangles.
  List<({double lowLat, double lowLng, double highLat, double highLng})>
      _sectorRects(double latitude, double longitude, double radius) {
    const double metersPerDegree = 111320.0;
    final half = radius / metersPerDegree;
    final step = (2 * half) / _sectorsPerSide;

    return [
      for (var row = 0; row < _sectorsPerSide; row++)
        for (var col = 0; col < _sectorsPerSide; col++)
          (
            lowLat: latitude - half + row * step,
            lowLng: longitude - half + col * step,
            highLat: latitude - half + (row + 1) * step,
            highLng: longitude - half + (col + 1) * step,
          ),
    ];
  }

  /// Computes the two locality signals consumed by `Restaurant.rankingScore`
  /// and stores them on each place map, so they ride along with the raw-map
  /// cache and survive `Restaurant.fromJson` round-trips:
  ///
  ///  * `frDestinationBonus` — how much more reviewed the place is than its
  ///    ~500m neighbors, in log-review units. Positive means people travel to
  ///    it despite its surroundings; negative means it mostly rides the foot
  ///    traffic of an already-busy strip.
  ///  * `frTouristPenalty` — 0..1 saturation of tourist attractions and
  ///    hotels within ~250m, i.e. how captive the audience is.
  Future<void> _applyLocalityScores(List<Map<String, dynamic>> restaurants,
      double latitude, double longitude, double searchRadius) async {
    if (restaurants.isEmpty) return;

    final pois = await Future.wait([
      _fetchPoiLocations(latitude, longitude, searchRadius,
          type: 'tourist_attraction'),
      _fetchPoiLocations(latitude, longitude, searchRadius, type: 'lodging'),
    ]);
    final attractions = pois[0];
    final hotels = pois[1];

    final positions = [
      for (final r in restaurants)
        (
          lat: ((r['location'] as Map<String, dynamic>?)?['latitude'] as num?)
                  ?.toDouble() ??
              double.nan,
          lng: ((r['location'] as Map<String, dynamic>?)?['longitude'] as num?)
                  ?.toDouble() ??
              double.nan,
        ),
    ];
    final logCounts = [
      for (final r in restaurants)
        log(((r['userRatingCount'] as num?)?.toInt() ?? 0) + 1),
    ];
    final poolMedian = _median(logCounts);

    for (var i = 0; i < restaurants.length; i++) {
      final neighborLogs = <double>[];
      for (var j = 0; j < restaurants.length; j++) {
        if (i == j) continue;
        final d = _calculateDistance(
            positions[i].lat, positions[i].lng, positions[j].lat, positions[j].lng);
        if (d <= _neighborhoodRadius) neighborLogs.add(logCounts[j]);
      }
      // With too few close neighbors the local median is noise; fall back to
      // the whole pool so the bonus is still "relative to this area".
      final baseline =
          neighborLogs.length >= 3 ? _median(neighborLogs) : poolMedian;
      final bonus = (logCounts[i] - baseline)
          .clamp(-_maxDestinationExcess, _maxDestinationExcess);

      var penalty = 0.0;
      for (final poi in attractions) {
        final d = _calculateDistance(
            positions[i].lat, positions[i].lng, poi.lat, poi.lng);
        if (d <= _poiPenaltyRadius) penalty += _attractionWeight;
      }
      for (final poi in hotels) {
        final d = _calculateDistance(
            positions[i].lat, positions[i].lng, poi.lat, poi.lng);
        if (d <= _poiPenaltyRadius) penalty += _hotelWeight;
      }

      restaurants[i]['frDestinationBonus'] = bonus;
      restaurants[i]['frTouristPenalty'] = min(1.0, penalty);
    }
  }

  /// Best-effort fetch of nearby POI coordinates of [type] via Nearby Search.
  /// Returns an empty list on any failure so ranking degrades to "no penalty"
  /// instead of failing the whole restaurant search.
  Future<List<({double lat, double lng})>> _fetchPoiLocations(
      double latitude, double longitude, double searchRadius,
      {required String type}) async {
    try {
      ApiUsageTracker.instance.incrementNearbySearch();
      final response = await ProxyService.placesApiGet(
        'places:searchNearby',
        {
          'includedTypes': [type],
          'maxResultCount': 20,
          'locationRestriction': {
            'circle': {
              'center': {'latitude': latitude, 'longitude': longitude},
              // Nearby Search caps the circle radius at 50km.
              'radius': searchRadius.clamp(_initialRadius, 50000),
            },
          },
        },
        fieldMask: 'places.location',
      );

      final places = (response['places'] as List<dynamic>?) ?? const [];
      return [
        for (final place in places)
          if (place['location']?['latitude'] != null &&
              place['location']?['longitude'] != null)
            (
              lat: (place['location']['latitude'] as num).toDouble(),
              lng: (place['location']['longitude'] as num).toDouble(),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = List.of(values)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  /// Whether a place with the given Places API opening-hours [periods] is open
  /// at [day] (`0 = Sunday … 6 = Saturday`) and [minutes] since local midnight.
  ///
  /// Handles the three shapes the API produces:
  ///   * **24-hour**: a single period whose `open` is `{0,0,0}` with no `close`.
  ///   * **overnight**: `close.day` is later than `open.day` (e.g. 22:00→02:00).
  ///   * **week wrap**: a Saturday-night period that closes on Sunday.
  ///
  /// Places with unknown hours (null/empty [periods]) are treated as closed,
  /// since the feature's promise is "open at this time".
  static bool isOpenAt(List<dynamic>? periods, int day, int minutes) {
    if (periods == null || periods.isEmpty) return false;

    const int week = 7 * 1440;
    final int target = day * 1440 + minutes;

    int pointToMinutes(Map<String, dynamic> point) =>
        ((point['day'] as num?)?.toInt() ?? 0) * 1440 +
        ((point['hour'] as num?)?.toInt() ?? 0) * 60 +
        ((point['minute'] as num?)?.toInt() ?? 0);

    for (final raw in periods) {
      final period = raw as Map<String, dynamic>?;
      if (period == null) continue;

      final open = period['open'] as Map<String, dynamic>?;
      if (open == null) continue;

      // No close → always-open (24h) per the API contract.
      if (period['close'] == null) return true;

      final openMin = pointToMinutes(open);
      var closeMin = pointToMinutes(period['close'] as Map<String, dynamic>);
      // Overnight / week-wrap: normalise close to be after open.
      if (closeMin <= openMin) closeMin += week;

      if (target >= openMin && target < closeMin) return true;
      // A period that wrapped past Saturday into Sunday also covers early-week
      // targets once shifted forward by a full week.
      if (target + week >= openMin && target + week < closeMin) return true;
    }
    return false;
  }

  Map<String, dynamic> _buildSearchParams(
      ({double lowLat, double lowLng, double highLat, double highLng}) rect,
      {String? cuisineType,
      List<String>? priceLevels,
      bool openNow = true,
      String? searchQuery}) {
    if (rect.lowLat.isNaN ||
        rect.lowLng.isNaN ||
        rect.highLat.isNaN ||
        rect.highLng.isNaN) {
      throw ArgumentError('Invalid parameters for search');
    }

    return {
      'textQuery': searchQuery?.isNotEmpty == true
          ? searchQuery
          : cuisineType != null && cuisineType != 'Other'
              ? '$cuisineType restaurant'
              : 'restaurant',
      'locationRestriction': {
        'rectangle': {
          'low': {
            'latitude': rect.lowLat,
            'longitude': rect.lowLng,
          },
          'high': {
            'latitude': rect.highLat,
            'longitude': rect.highLng,
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

  /// Warms the restaurant + photo caches used by the first screen. Decoding the
  /// fetched bytes into the widget tree is the caller's job (see
  /// `SplashScreen._warmCaches`) — this class stays free of Flutter imports so
  /// `bin/foodierank.dart` can reuse the search and ranking pipeline.
  ///
  /// Returns the photo refs that were fetched, in display order.
  Future<List<String>> warmCaches() async {
    if (_cachedRestaurants != null) return const [];

    final restaurants = await fetchRestaurants(37.785834, -122.406417);
    final headerPhotoRefs = restaurants
        .expand((r) => (r['photoRefs'] as List<dynamic>?)?.take(1) ?? [])
        .cast<String>()
        .toList();

    await prefetchHeaderPhotos(headerPhotoRefs);
    return headerPhotoRefs;
  }

  bool shouldRefreshData(double currentLat, double currentLng,
      {String? contextKey}) {
    if (_lastFetchTime == null ||
        _lastFetchLatitude == null ||
        _lastFetchLongitude == null) {
      return true;
    }

    // A different where/when context (custom location or time) never reuses the
    // cache from another context, and vice-versa.
    if (contextKey != _lastContextKey) {
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
