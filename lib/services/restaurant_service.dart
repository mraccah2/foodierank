import 'package:foodierank/services/proxy_service.dart';
import 'package:foodierank/config.dart';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:async';
import 'dart:math';
import 'api_usage_tracker.dart';
import 'app_http.dart';
import 'photo_source.dart';

/// A result set together with the query it answers and where it was taken —
/// everything needed to decide, on the next launch, whether it can be shown
/// straight away instead of blocking on a network search.
class RestaurantSearchSnapshot {
  final List<Map<String, dynamic>> places;
  final double latitude;
  final double longitude;
  final String queryKey;
  final DateTime fetchedAt;

  const RestaurantSearchSnapshot({
    required this.places,
    required this.latitude,
    required this.longitude,
    required this.queryKey,
    required this.fetchedAt,
  });

  Map<String, dynamic> toJson() => {
        'places': places,
        'lat': latitude,
        'lng': longitude,
        'queryKey': queryKey,
        'fetchedAt': fetchedAt.millisecondsSinceEpoch,
      };

  static RestaurantSearchSnapshot? fromJson(Map<String, dynamic> json) {
    final places = (json['places'] as List<dynamic>?)
        ?.whereType<Map<String, dynamic>>()
        .toList();
    final lat = (json['lat'] as num?)?.toDouble();
    final lng = (json['lng'] as num?)?.toDouble();
    final fetchedAt = (json['fetchedAt'] as num?)?.toInt();
    if (places == null || lat == null || lng == null || fetchedAt == null) {
      return null;
    }
    return RestaurantSearchSnapshot(
      places: places,
      latitude: lat,
      longitude: lng,
      queryKey: json['queryKey'] as String? ?? '',
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedAt),
    );
  }
}

class RestaurantService implements PhotoSource {
  static final RestaurantService instance = RestaurantService._internal();
  List<Map<String, dynamic>>? _cachedRestaurants;
  DateTime? _lastFetchTime;
  double? _lastFetchLatitude;
  double? _lastFetchLongitude;
  String? _lastQueryKey;

  /// Fetched photo bytes, least-recently-used first.
  ///
  /// Bounded on purpose: this was an unbounded map retaining the bytes of every
  /// photo ever fetched for the life of the process, so a few changes of
  /// cuisine or city accumulated tens of megabytes nothing would look at again.
  final LinkedHashMap<String, Uint8List> _photoCache = LinkedHashMap();
  static const int _photoCacheLimit = 60;

  /// In-flight photo requests, so a list row, its card and any prefetch share
  /// one download of the same photo rather than racing three.
  final Map<String, Future<Uint8List?>> _photoRequests = {};

  /// Photos share one HTTP client with everything else. Letting twenty start at
  /// once defeats connection reuse and starves whatever the user is actually
  /// waiting on; six is the same ceiling browsers settle on per host.
  static const int _maxConcurrentPhotos = 6;
  int _photosInFlight = 0;

  /// Waiters split by priority. A place's first photo — the one its list row
  /// and card face show — is what makes the screen look finished, so those are
  /// served before any place's second photo.
  final Queue<Completer<void>> _firstPhotoQueue = Queue();
  final Queue<Completer<void>> _restPhotoQueue = Queue();

  /// Installed by the app so a result set survives a relaunch (see
  /// `RestaurantDiskCache`). Left null by `bin/foodierank.dart`, which is why
  /// it is a hook rather than a direct call — this class stays free of Flutter
  /// imports so the CLI can share the search and ranking pipeline.
  Future<void> Function(RestaurantSearchSnapshot snapshot)? onResults;

  /// The disk tier under [_photoCache], installed by `PhotoDiskCache` for the
  /// same reason [onResults] is a hook: it needs `path_provider`, which the CLI
  /// cannot load. Null simply means memory-only, which is what `bin/` gets.
  Future<Uint8List?> Function(String photoRef)? photoCacheRead;
  Future<void> Function(String photoRef, Uint8List bytes)? photoCacheWrite;

  factory RestaurantService() {
    return instance;
  }

  RestaurantService._internal();

  List<Map<String, dynamic>>? get cachedRestaurants => _cachedRestaurants;

  /// Everything that changes what a search returns, folded into one string.
  /// Two searches with equal keys are interchangeable; anything else has to go
  /// back to the network.
  ///
  /// [shouldRefreshData] used to compare only the where/when context, so a
  /// result set fetched under one cuisine or price filter could be served for a
  /// different one.
  static String queryKey({
    List<String>? priceLevels,
    String? cuisineType,
    bool openNow = true,
    String? searchQuery,
    int? targetDay,
    int? targetMinutes,
    String? contextKey,
  }) {
    final prices = (priceLevels?.toList()?..sort())?.join('|') ?? '';
    return [
      cuisineType ?? '',
      prices,
      openNow ? 'now' : 'any',
      searchQuery ?? '',
      targetDay?.toString() ?? '',
      targetMinutes?.toString() ?? '',
      contextKey ?? '',
    ].join('');
  }

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
    final places = await getNearbyRestaurants(
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

    // Only stamp the cache once the search has actually succeeded — recording
    // the position up front meant a thrown search left the service claiming a
    // fresh fetch for a result set it never got.
    _lastFetchTime = DateTime.now();
    _lastFetchLatitude = latitude;
    _lastFetchLongitude = longitude;
    _lastQueryKey = queryKey(
      priceLevels: priceLevels,
      cuisineType: cuisineType,
      openNow: openNow,
      searchQuery: searchQuery,
      targetDay: targetDay,
      targetMinutes: targetMinutes,
      contextKey: contextKey,
    );
    _cachedRestaurants = places;

    unawaited(_persist(RestaurantSearchSnapshot(
      places: places,
      latitude: latitude,
      longitude: longitude,
      queryKey: _lastQueryKey!,
      fetchedAt: _lastFetchTime!,
    )));
    // Pull the one photo each place displays, for all of them, but do not hold
    // the results back for it: the list is readable without pictures, and
    // awaiting twenty downloads here was seconds of spinner for decoration.
    // Additional gallery photos stay on demand — at twenty places by ten photos
    // they would be a hundredfold the requests for something nobody has asked
    // to see.
    unawaited(warmFirstPhotos());

    return places;
  }

  List<String> _firstPhotoRefs(List<Map<String, dynamic>> places) => places
      .expand((r) => (r['photoRefs'] as List<dynamic>?)?.take(1) ?? const [])
      .cast<String>()
      .toList();

  /// Takes the snapshot by argument rather than re-reading the fields, so a
  /// second search starting while this one is still writing cannot swap the
  /// result set out from under it.
  Future<void> _persist(RestaurantSearchSnapshot snapshot) async {
    final persist = onResults;
    if (persist == null) return;
    try {
      await persist(snapshot);
    } catch (_) {
      // Persistence is an optimisation; never fail a search over it.
    }
  }

  /// Adopt a previously persisted result set as though it had just been
  /// fetched, so a cold start can render from disk while it revalidates.
  void hydrate(RestaurantSearchSnapshot snapshot) {
    _cachedRestaurants = snapshot.places;
    _lastFetchLatitude = snapshot.latitude;
    _lastFetchLongitude = snapshot.longitude;
    _lastQueryKey = snapshot.queryKey;
    _lastFetchTime = snapshot.fetchedAt;

    // A restored result set needs its pictures as much as a fetched one does.
    // Without this, a cold start drew the list instantly and then filled its
    // photos in one row at a time as they scrolled into view.
    unawaited(warmFirstPhotos());
  }

  static const int _targetCount = 20;
  static const double _initialRadius = 1000; // start ~1km
  static const double _radiusGrowth = 2.0; // double the search radius each round
  static const double _emptyRoundGrowth = 4.0; // step out harder over empty country
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

  // A few cuisineTypes name a venue kind, not a food style, so the default
  // "$cuisineType restaurant" Text Search phrase is wrong for them: a coffee
  // shop is not a "Coffee restaurant", and Places Text Search returns almost
  // no cafés for that query (it falls back to generic restaurants — pizzerias,
  // chicken joints). Map those to the natural search phrase; every other
  // cuisine keeps "$cuisineType restaurant". See _cuisineQueryPhrase.
  static const Map<String, String> _cuisineQueryPhrases = {
    'Coffee': 'coffee shop',
    'Bakery': 'bakery',
    'Bar': 'bar',
    'Pub': 'pub',
    'Deli': 'deli',
    'Diner': 'diner',
  };

  // The Text Search phrase for a cuisine filter: a special-cased venue phrase
  // when one applies (see _cuisineQueryPhrases), else "<cuisine> restaurant".
  static String _cuisineQueryPhrase(String cuisineType) =>
      _cuisineQueryPhrases[cuisineType] ?? '$cuisineType restaurant';

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
      final countBefore = allRestaurants.length;

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
      // A round that turned up nothing at all means empty country, not a thin
      // result: stepping out by the usual factor just buys another four
      // requests over more of the same. Widening harder gets to the nearest
      // populated area in fewer sequential round trips, which is what the user
      // is actually waiting on.
      final growth = allRestaurants.length == countBefore
          ? _emptyRoundGrowth
          : _radiusGrowth;
      radius = (radius * growth).clamp(_initialRadius, maxRadius);
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
              ? _cuisineQueryPhrase(cuisineType)
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

  /// The bytes for [photoRef] if they are already in memory. Cheap enough for a
  /// `build`; returns null rather than starting a download, so callers that can
  /// render a placeholder are not forced to wait.
  @override
  Uint8List? getCachedPhoto(String photoRef) {
    // Re-inserting on read is what makes the bounded map an LRU rather than a
    // "first sixty photos of the session" cache.
    final bytes = _photoCache.remove(photoRef);
    if (bytes == null) return null;
    _photoCache[photoRef] = bytes;
    return bytes;
  }

  /// The bytes for [photoRef], fetching them if needed.
  ///
  /// Concurrent callers for the same photo share one request: a list row, the
  /// card behind it and any prefetch all used to issue their own.
  ///
  /// [priority] marks a place's *first* photo — the one the list row and the
  /// card header show. Those go to the front of the queue, so the second photo
  /// of a restaurant somebody swiped through cannot hold up the only photo
  /// twelve other restaurants have.
  @override
  Future<Uint8List?> loadPhoto(String photoRef,
      {int maxWidth = 800, int maxHeight = 450, bool priority = false}) {
    final cached = getCachedPhoto(photoRef);
    if (cached != null) return Future.value(cached);

    final existing = _photoRequests[photoRef];
    if (existing != null) return existing;

    final request = _fetchPhoto(photoRef, maxWidth, maxHeight, priority)
        .whenComplete(() {
      // A block body, deliberately. `=> _photoRequests.remove(photoRef)`
      // returns the removed value — and since this map's values *are* futures,
      // that value is this very request. `whenComplete` waits on any Future its
      // callback returns, so the request awaited itself and never completed.
      // The bytes still reached the cache, so a photo appeared if its widget
      // happened to mount after the fetch, and shimmered forever otherwise.
      _photoRequests.remove(photoRef);
    });
    _photoRequests[photoRef] = request;
    return request;
  }

  Future<Uint8List?> _fetchPhoto(
      String photoRef, int maxWidth, int maxHeight, bool priority) async {
    // Disk before network, and before taking a slot — a local read is orders of
    // magnitude cheaper and has no business queueing behind six downloads.
    try {
      final fromDisk = await photoCacheRead?.call(photoRef);
      if (fromDisk != null) {
        _cachePhoto(photoRef, fromDisk);
        return fromDisk;
      }
    } catch (e) {
      // A disk tier that misbehaves degrades to "not cached", and the request
      // carries on to the network. It must never fail the future: callers
      // attach a bare `.then`, which skips its callback on an error, so this
      // would leave a placeholder on screen forever with nothing logged.
    }

    await _acquirePhotoSlot(priority);
    try {
      ApiUsageTracker.instance.incrementPhoto();
      final uri = Uri.parse('${ProxyService.baseUrl}/$photoRef/media').replace(
        queryParameters: {
          'maxWidthPx': maxWidth.toString(),
          'maxHeightPx': maxHeight.toString(),
        },
      );

      final response = await appHttpClient.get(
        uri,
        headers: {
          // The key travels in the header only. It used to also be repeated as
          // a `key` query parameter, which put it in the URL of every photo
          // request and so into any intermediary's access log.
          'X-Goog-Api-Key': Config.googleMapsApiKey,
          ...Config.appAttestationHeaders,
          'Accept': 'image/*',
          'User-Agent': 'FoodieRank/1.0',
        },
      ).timeout(kPhotoTimeout);

      if (response.statusCode != 200) return null;
      _cachePhoto(photoRef, response.bodyBytes);
      // Nothing waits on the write: the bytes are already in memory for this
      // session, and persisting them is for the next one.
      unawaited(photoCacheWrite?.call(photoRef, response.bodyBytes) ??
          Future<void>.value());
      return response.bodyBytes;
    } catch (e) {
      return null;
    } finally {
      _releasePhotoSlot();
    }
  }

  void _cachePhoto(String photoRef, Uint8List bytes) {
    _photoCache[photoRef] = bytes;
    while (_photoCache.length > _photoCacheLimit) {
      _photoCache.remove(_photoCache.keys.first);
    }
  }

  Future<void> _acquirePhotoSlot(bool priority) {
    if (_photosInFlight < _maxConcurrentPhotos) {
      _photosInFlight++;
      return Future.value();
    }
    final waiter = Completer<void>();
    (priority ? _firstPhotoQueue : _restPhotoQueue).add(waiter);
    return waiter.future;
  }

  void _releasePhotoSlot() {
    // Drain first photos before anything else: every place should have its one
    // picture before any place gets a second.
    final queue =
        _firstPhotoQueue.isNotEmpty ? _firstPhotoQueue : _restPhotoQueue;
    // Hand the slot straight to whoever is queued rather than releasing and
    // re-taking it, so the in-flight count stays accurate.
    if (queue.isNotEmpty) {
      queue.removeFirst().complete();
      return;
    }
    _photosInFlight--;
  }

  /// Pull the one photo each place displays, for *every* place in the current
  /// result set — not just the first screenful.
  ///
  /// Nothing waits on this: [loadPhoto] already serves whatever has landed and
  /// fetches the rest on demand. It exists so that scrolling down does not
  /// arrive at a column of empty placeholders, and so a photo already on disk
  /// is in memory before its row is ever built.
  Future<void> warmFirstPhotos() async {
    try {
      await prefetchFirstPhotos(_firstPhotoRefs(_cachedRestaurants ?? const []));
    } catch (_) {
      // Warming is best effort, and both callers leave it unawaited — an
      // failure here must not surface as an unhandled async error.
    }
  }

  Future<void> prefetchFirstPhotos(List<String> photoRefs) =>
      Future.wait(photoRefs.map((ref) => loadPhoto(ref, priority: true)));

  bool shouldRefreshData(double currentLat, double currentLng,
      {List<String>? priceLevels,
      String? cuisineType,
      bool openNow = true,
      String? searchQuery,
      int? targetDay,
      int? targetMinutes,
      String? contextKey}) {
    if (_lastFetchTime == null ||
        _lastFetchLatitude == null ||
        _lastFetchLongitude == null) {
      return true;
    }

    // Anything that changes what the search returns — the where/when context,
    // but also the cuisine, price and keyword filters — invalidates the cache.
    // Only the context was compared before, so a result set fetched under one
    // cuisine filter could be served for another.
    if (queryKey(
          priceLevels: priceLevels,
          cuisineType: cuisineType,
          openNow: openNow,
          searchQuery: searchQuery,
          targetDay: targetDay,
          targetMinutes: targetMinutes,
          contextKey: contextKey,
        ) !=
        _lastQueryKey) {
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
}
