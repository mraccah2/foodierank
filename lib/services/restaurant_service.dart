import 'package:foodierank/services/proxy_service.dart';
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

/// One remembered answer, with enough context to know when it stops applying.
class _MemoisedSearch {
  final List<Map<String, dynamic>> places;
  final double latitude;
  final double longitude;
  final DateTime fetchedAt;

  const _MemoisedSearch({
    required this.places,
    required this.latitude,
    required this.longitude,
    required this.fetchedAt,
  });
}

/// Tourist attractions and hotels around a search, for the locality scores.
typedef _Pois = ({
  List<({double lat, double lng})> attractions,
  List<({double lat, double lng})> hotels,
});

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
  ///
  /// Both take the [photoCacheKey], never a photo reference — a reference is a
  /// per-response nonce, so a disk file named after one is never read again.
  Future<Uint8List?> Function(String key)? photoCacheRead;
  Future<void> Function(String key, Uint8List bytes)? photoCacheWrite;

  /// Recent result sets, keyed by query and rounded location.
  ///
  /// Only ONE result set used to be remembered, in [_lastQueryKey]. Every
  /// filter change therefore threw the previous one away, so going Italian →
  /// Sushi → Italian paid for Italian twice: four to twelve Text Search calls
  /// at $35–40 per thousand, plus a fresh round of photo prefetching. Trying
  /// filters is the single most common thing anyone does in this app, and it
  /// was the most expensive.
  ///
  /// Deliberately in memory only. The on-disk snapshot answers "what should a
  /// cold start show"; this answers "has this exact question been asked in the
  /// last few minutes", which is a different question with a much shorter
  /// useful life.
  final LinkedHashMap<String, _MemoisedSearch> _resultMemo = LinkedHashMap();
  static const int _resultMemoLimit = 12;

  /// Short enough that "open now" cannot drift far, long enough to cover a
  /// session of trying filters against one place on the map.
  static const Duration _resultMemoMaxAge = Duration(minutes: 20);

  /// Past this the map has moved enough to be a different question.
  static const double _resultMemoMaxDriftM = 250;

  factory RestaurantService() {
    return instance;
  }

  RestaurantService._internal();

  List<Map<String, dynamic>>? get cachedRestaurants => _cachedRestaurants;

  /// Why the last search could not reach Places, or null if it did.
  ///
  /// Read by the list screen to tell "the service refused us" apart from "there
  /// is genuinely nothing open here" — two states that looked identical to a
  /// user until now, and which call for opposite reactions.
  String? lastSearchFailure;

  /// Record a sector failure, keeping the most explanatory one.
  ///
  /// A search fans out over sectors and rounds, so several failures can arrive
  /// per search. An "unavailable" beats a transient one: if any sector was
  /// refused outright, that is the thing worth saying.
  void _noteSearchFailure(Object error) {
    if (error is! PlacesApiException) return;
    if (error.isUnavailable || lastSearchFailure == null) {
      lastSearchFailure = error.userMessage;
    }
  }

  /// A remembered answer for [key], if one still applies here and now.
  ///
  /// Both conditions matter and neither is sufficient. Age alone would serve a
  /// Rome result set to someone who has since landed in Naples; distance alone
  /// would keep serving "open now" long after the kitchens shut.
  _MemoisedSearch? _memoHit(String key, double latitude, double longitude) {
    final entry = _resultMemo.remove(key);
    if (entry == null) return null;
    if (DateTime.now().difference(entry.fetchedAt) > _resultMemoMaxAge) {
      return null; // dropped: removed above and not put back
    }
    if (_calculateDistance(
            entry.latitude, entry.longitude, latitude, longitude) >
        _resultMemoMaxDriftM) {
      // Kept, not dropped — the same question from somewhere else is still a
      // good answer for wherever it was asked from.
      _resultMemo[key] = entry;
      return null;
    }
    _resultMemo[key] = entry; // re-inserting on read is what makes it an LRU
    return entry;
  }

  void _memoRemember(String key, List<Map<String, dynamic>> places,
      double latitude, double longitude) {
    _resultMemo.remove(key);
    _resultMemo[key] = _MemoisedSearch(
      places: places,
      latitude: latitude,
      longitude: longitude,
      fetchedAt: DateTime.now(),
    );
    while (_resultMemo.length > _resultMemoLimit) {
      _resultMemo.remove(_resultMemo.keys.first);
    }
  }

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
    final key = queryKey(
      priceLevels: priceLevels,
      cuisineType: cuisineType,
      openNow: openNow,
      searchQuery: searchQuery,
      targetDay: targetDay,
      targetMinutes: targetMinutes,
      contextKey: contextKey,
    );

    // Asked this already, recently, from about here? Then it is the same
    // question and Google has already been paid for the answer.
    final memo = _memoHit(key, latitude, longitude);
    if (memo != null) {
      _lastFetchTime = memo.fetchedAt;
      _lastFetchLatitude = latitude;
      _lastFetchLongitude = longitude;
      _lastQueryKey = key;
      _cachedRestaurants = memo.places;
      // Warmed anyway: those photos are already in memory or on disk, so it
      // costs nothing and stops the list redrawing without its pictures.
      unawaited(warmFirstPhotos());
      return memo.places;
    }

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
    _lastQueryKey = key;
    _cachedRestaurants = places;
    _memoRemember(key, places, latitude, longitude);

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

  /// The one photo each place displays, paired with the stable key to cache it
  /// under. The pairing has to happen here: by the time a bare list of refs
  /// reaches [prefetchFirstPhotos] the place id that makes them cacheable is
  /// gone, and the warm would write twenty files nothing could ever look up.
  List<({String ref, String cacheId})> _firstPhotoRefs(
          List<Map<String, dynamic>> places) =>
      places
          .map((r) {
            final refs = r['photoRefs'] as List<dynamic>?;
            if (refs == null || refs.isEmpty) return null;
            final id = r['id'] as String?;
            return (
              ref: refs.first as String,
              cacheId: id == null ? refs.first as String : '$id:0',
            );
          })
          .whereType<({String ref, String cacheId})>()
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
  /// The first ring. 500 m, not 1 km, because the dense case is the common one
  /// and a city block has far more than 20 restaurants inside 500 m — a 1 km
  /// first ring bought a wider net than [_targetCount] ever needed and pulled
  /// in places a user would not walk to when better ones sat closer. Moshik,
  /// 2026-08-21: *"we should only get 20 results - and use a widening perimiter
  /// beginning with 500m (for urban density) and expanding only if needed."*
  ///
  /// This costs nothing in the urban case (still one round, still
  /// [_sectorsPerSide]² requests) and buys tighter, more walkable results. It
  /// only adds a round where 500 m genuinely is not enough, which is exactly
  /// the "expanding only if needed" half of the instruction.
  static const double _initialRadius = 500; // start 500m — urban density
  static const double _radiusGrowth = 2.0; // double the search radius each round
  static const double _emptyRoundGrowth = 4.0; // step out harder over empty country
  /// How far out the widening loop will go before giving up.
  ///
  /// Was 100 km, which is not a distance anyone travels for lunch. Doubling
  /// from the old 1 km first ring, that allowed eight rounds — and every round is
  /// [_sectorsPerSide]² billed Text Search requests, so a filtered search that
  /// could never reach [_targetCount] (say vegan + $$ + open now in a quiet
  /// town) spent up to **32 requests** discovering that, then offered results
  /// an hour's drive away. 25 km caps it at five rounds and still reaches the
  /// next town from anywhere suburban.
  static const double maxRadius = 25000;

  /// A hard ceiling on rounds, independent of the radius maths.
  ///
  /// Belt and braces: the growth factors and the clamp interact (an empty round
  /// multiplies by four, a thin one by two, and both clamp to [maxRadius]), and
  /// once radius pins at the cap a loop that keeps finding nothing new would
  /// otherwise re-query the same box until the result count moved. It cannot,
  /// if the places genuinely are not there.
  ///
  /// Six, not five, since [_initialRadius] dropped to 500 m: the thin-area
  /// ladder doubles, so five rounds from 500 m would top out at 8 km where five
  /// from 1 km reached 16 km. Halving the first ring must not halve how far a
  /// suburban search can see. Worst case is [_sectorsPerSide]² × 6 = 24 billed
  /// requests, against 32 before this file was touched — and the urban case,
  /// which is nearly all of them, still finishes in one round.
  static const int _maxSearchRounds = 6;
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
    // Cleared per search, not per sector: a stale reason outliving the outage
    // that caused it would keep blaming the budget for an empty street.
    lastSearchFailure = null;

    // "Custom time" means the user asked for a specific day/time-of-day rather
    // than "open now", and is evaluated client-side from opening hours.
    final bool customTime = targetDay != null && targetMinutes != null;

    // "Open now" is evaluated client-side too, never sent as Google's
    // `openNow` filter. The Places gateway caches a search forever on its
    // canonical request, so an `openNow: true` answer captured at lunchtime
    // would be served unchanged at midnight. Opening hours come back on every
    // place anyway (the gateway always returns all fields), so filtering here
    // costs nothing, stays correct at any hour, and lets the open-now and
    // custom-time searches share one cached request.
    final bool filterOpenNow = openNow && !customTime;
    final DateTime nowUtc = DateTime.now().toUtc();

    double radius = _initialRadius;
    final Set<String> foundIds = {};
    final List<Map<String, dynamic>> allRestaurants = [];

    // The locality lookups only need a centre and a radius, and in a dense area
    // the first round's radius is the final one. Started here, they run
    // alongside the first round instead of after the last — they used to add
    // 1-2 s, in series, before the list or any photo could appear.
    var pois = _fetchPois(latitude, longitude, radius);
    final poisRadius = radius;

    // Keep widening the search until we have enough places or we hit the
    // safety cap. Dense areas are satisfied on the first (smallest) round;
    // rural areas keep doubling the radius outward until they reach the
    // nearest populated towns. With a custom time we count only the places that
    // are open at that time toward the target.
    var rounds = 0;
    while (allRestaurants.length < _targetCount) {
      if (radius.isNaN) break;
      if (rounds++ >= _maxSearchRounds) break;
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
          return ProxyService.searchText(
            _buildSearchParams(
              rect,
              cuisineType: cuisineType,
              priceLevels: priceLevels,
              searchQuery: searchQuery,
            ),
            fields: _searchFields,
            heldPhotos: true,
          ).catchError((Object e) {
            // Was `(_) => {}`, which flattened every failure into "no places
            // found" — so an API that had been switched off read as an empty
            // neighbourhood. A sector that fails is still skipped, but the
            // reason is kept so the screen can say what actually happened.
            _noteSearchFailure(e);
            return <String, dynamic>{};
          });
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

            final periods = (mappedPlace['regularOpeningHours']
                as Map<String, dynamic>?)?['periods'] as List<dynamic>?;
            if (customTime) {
              if (!isOpenAt(periods, targetDay, targetMinutes)) continue;
            } else if (filterOpenNow) {
              final local = placeLocalTime(
                  nowUtc, (mappedPlace['utcOffsetMinutes'] as num?)?.toInt());
              if (!isOpenAt(periods, local.day, local.minutes)) continue;
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

    // The search had to widen, so the POIs fetched for the first ring cover
    // too little of it.
    if (radius != poisRadius) pois = _fetchPois(latitude, longitude, radius);
    _applyLocalityScores(allRestaurants, await pois);

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
  void _applyLocalityScores(
      List<Map<String, dynamic>> restaurants, _Pois pois) {
    if (restaurants.isEmpty) return;

    final attractions = pois.attractions;
    final hotels = pois.hotels;

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

  /// Tourist attractions and hotels within [searchRadius], for
  /// [_applyLocalityScores]. Never throws: each half degrades to empty.
  Future<_Pois> _fetchPois(
      double latitude, double longitude, double searchRadius) async {
    final pois = await Future.wait([
      _fetchPoiLocations(latitude, longitude, searchRadius,
          type: 'tourist_attraction'),
      _fetchPoiLocations(latitude, longitude, searchRadius, type: 'lodging'),
    ]);
    return (attractions: pois[0], hotels: pois[1]);
  }

  /// Best-effort fetch of nearby POI coordinates of [type] via Nearby Search.
  /// Returns an empty list on any failure so ranking degrades to "no penalty"
  /// instead of failing the whole restaurant search.
  Future<List<({double lat, double lng})>> _fetchPoiLocations(
      double latitude, double longitude, double searchRadius,
      {required String type}) async {
    try {
      ApiUsageTracker.instance.incrementNearbySearch();
      final response = await ProxyService.searchNearby(
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
        // Only the coordinates are read; a full hotel is ~30 KB.
        fields: const ['location'],
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

  /// The weekday (`0 = Sunday … 6 = Saturday`) and minutes since midnight at a
  /// place whose clock is [utcOffsetMinutes] from UTC, at [nowUtc] — the
  /// arguments [isOpenAt] wants for "open now". A place with no offset falls
  /// back to the device's own clock, which is right for the common case of
  /// searching where you are.
  static ({int day, int minutes}) placeLocalTime(
      DateTime nowUtc, int? utcOffsetMinutes) {
    final local = utcOffsetMinutes == null
        ? nowUtc.toLocal()
        : nowUtc.toUtc().add(Duration(minutes: utcOffsetMinutes));
    return (day: local.weekday % 7, minutes: local.hour * 60 + local.minute);
  }

  /// The only fields a place keeps once mapped.
  ///
  /// The gateway returns every field Google has — reviews, address components,
  /// entrances, the lot — and a result set rides along in the in-memory memo
  /// and the on-disk snapshot. These are what [Restaurant.fromJson] and the
  /// filters actually read; the old request field mask, in effect, applied on
  /// arrival instead of on request.
  static const Set<String> _keptPlaceFields = {
    'id',
    'displayName',
    'rating',
    'userRatingCount',
    'photos',
    'priceLevel',
    'types',
    'formattedAddress',
    'location',
    'editorialSummary',
    'regularOpeningHours',
    'utcOffsetMinutes',
  };

  /// What a search asks the gateway for: [_keptPlaceFields], with each photo
  /// cut to its `name` — the only part [_mapPlace] keeps.
  static final List<String> _searchFields = [
    for (final f in _keptPlaceFields) f == 'photos' ? 'photos.name' : f,
  ];

  Map<String, dynamic> _buildSearchParams(
      ({double lowLat, double lowLng, double highLat, double highLng}) rect,
      {String? cuisineType,
      List<String>? priceLevels,
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
      if (priceLevels != null) ...{
        'priceLevels': priceLevels,
      },
    };
  }

  Map<String, dynamic>? _mapPlace(
      Map<String, dynamic> place, List<String>? targetPriceLevels) {
    final photos = (place['photos'] as List<dynamic>?)
        ?.map((photo) => {'name': photo['name'] as String})
        .toList();
    final photoRefs = photos?.map((photo) => photo['name']!).toList() ?? [];

    // Extract country from formatted address
    final formattedAddress = place['formattedAddress'] as String;
    final country = formattedAddress.split(',').last.trim();

    return {
      for (final entry in place.entries)
        if (_keptPlaceFields.contains(entry.key)) entry.key: entry.value,
      // Only the resource name: a slot is the photo's index, and nothing
      // reads the attributions or dimensions Google sends alongside.
      if (photos != null) 'photos': photos,
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

  /// The key every cache tier remembers a picture under.
  ///
  /// Deliberately *not* the photo reference. Google rotates `photos[i].name`
  /// on every search response, so a reference-keyed cache misses on everything
  /// but a re-read of the same response — see [PhotoSource.loadPhoto]. The
  /// place id and the photo's index within that place both survive, and the
  /// size is folded in so a thumbnail and a card header cannot collide.
  static String photoCacheKey(String photoRef, String? cacheId, int maxWidth,
          int maxHeight) =>
      '${cacheId ?? photoRef}@${maxWidth}x$maxHeight';

  /// The bytes for [photoRef] if they are already in memory. Cheap enough for a
  /// `build`; returns null rather than starting a download, so callers that can
  /// render a placeholder are not forced to wait.
  @override
  Uint8List? getCachedPhoto(String photoRef,
      {String? cacheId, int maxWidth = 800, int maxHeight = 450}) {
    final key = photoCacheKey(photoRef, cacheId, maxWidth, maxHeight);
    // Re-inserting on read is what makes the bounded map an LRU rather than a
    // "first sixty photos of the session" cache.
    final bytes = _photoCache.remove(key);
    if (bytes == null) return null;
    _photoCache[key] = bytes;
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
      {String? cacheId,
      int maxWidth = 800,
      int maxHeight = 450,
      bool priority = false}) {
    final key = photoCacheKey(photoRef, cacheId, maxWidth, maxHeight);

    final cached = getCachedPhoto(photoRef,
        cacheId: cacheId, maxWidth: maxWidth, maxHeight: maxHeight);
    if (cached != null) return Future.value(cached);

    // Keyed by cache key, not reference: two widgets showing the same picture
    // from different search responses hold different references, and used to
    // issue two downloads of identical bytes.
    final existing = _photoRequests[key];
    if (existing != null) return existing;

    final request =
        _fetchPhoto(photoRef, cacheId, key, priority).whenComplete(() {
      // A block body, deliberately. `=> _photoRequests.remove(key)` returns the
      // removed value — and since this map's values *are* futures, that value
      // is this very request. `whenComplete` waits on any Future its callback
      // returns, so the request awaited itself and never completed. The bytes
      // still reached the cache, so a photo appeared if its widget happened to
      // mount after the fetch, and shimmered forever otherwise.
      _photoRequests.remove(key);
    });
    _photoRequests[key] = request;
    return request;
  }

  /// Which gateway photo [photoRef] / [cacheId] names: the place id and the
  /// photo's slot (its index in the place's `photos`), or null.
  ///
  /// [cacheId] is `'<placeId>:<index>'` from every app caller and carries both.
  /// A bare Google resource name (`places/<id>/photos/<nonce>`) carries the
  /// place but not the slot, and guessing slot 0 would show a place's first
  /// photo in place of whichever one was asked for — so that is a miss.
  static ({String placeId, int slot})? gatewayPhotoTarget(
      String photoRef, String? cacheId) {
    if (cacheId == null) return null;
    final split = cacheId.lastIndexOf(':');
    if (split <= 0) return null;
    final slot = int.tryParse(cacheId.substring(split + 1));
    if (slot == null || slot < 0) return null;
    return (placeId: cacheId.substring(0, split), slot: slot);
  }

  Future<Uint8List?> _fetchPhoto(
      String photoRef, String? cacheId, String key, bool priority) async {
    // Disk before network, and before taking a slot — a local read is orders of
    // magnitude cheaper and has no business queueing behind six downloads.
    try {
      final fromDisk = await photoCacheRead?.call(key);
      if (fromDisk != null) {
        _cachePhoto(key, fromDisk);
        return fromDisk;
      }
    } catch (e) {
      // A disk tier that misbehaves degrades to "not cached", and the request
      // carries on to the network. It must never fail the future: callers
      // attach a bare `.then`, which skips its callback on an error, so this
      // would leave a placeholder on screen forever with nothing logged.
    }

    // The gateway knows a photo by place id and slot, never by Google's
    // rotating resource name, so without both there is nothing to ask for.
    final target = gatewayPhotoTarget(photoRef, cacheId);
    if (target == null) return null;

    // Straight from Storage when the photo is, or may be, held: the gateway
    // keeps it at a fixed path, so there is nothing to ask it. When the search
    // already said it is not held, that probe could only answer 400, so go
    // straight to the gateway.
    final held = ProxyService.isPhotoHeld(target.placeId, target.slot);
    var download = held == false
        ? (bytes: null, missing: true)
        : await _downloadPhoto(
            ProxyService.storedPhotoUrl(target.placeId, target.slot), priority);

    // Not stored yet (Storage says 400), or stored under another extension:
    // the gateway buys and stores it, and says where. Done without holding a
    // download slot — it is a lookup, and could take seconds on a first buy.
    if (download.missing) {
      ApiUsageTracker.instance.incrementPhoto();
      final url = await ProxyService.photoUrl(target.placeId, target.slot);
      if (url == null) return null;
      ProxyService.notePhotoHeld(target.placeId, target.slot);
      download = await _downloadPhoto(Uri.parse(url), priority);
    }

    final bytes = download.bytes;
    if (bytes == null) return null;
    _cachePhoto(key, bytes);
    // Nothing waits on the write: the bytes are already in memory for this
    // session, and persisting them is for the next one.
    unawaited(photoCacheWrite?.call(key, bytes) ?? Future<void>.value());
    return bytes;
  }

  /// One photo download, holding a slot only for the transfer itself.
  ///
  /// [missing] means the server answered that nothing is there (Storage uses
  /// 400 for that, not 404) — worth asking the gateway about. A timeout or a
  /// server fault is not: the photo may well exist, so it is just a failure.
  Future<({Uint8List? bytes, bool missing})> _downloadPhoto(
      Uri url, bool priority) async {
    await _acquirePhotoSlot(priority);
    try {
      final response = await appHttpClient.get(
        url,
        headers: const {
          'Accept': 'image/*',
          'User-Agent': 'FoodieRank/1.0',
        },
      ).timeout(kPhotoTimeout);
      final status = response.statusCode;
      if (status == 200) return (bytes: response.bodyBytes, missing: false);
      return (bytes: null, missing: status == 400 || status == 404);
    } catch (e) {
      return (bytes: null, missing: false);
    } finally {
      _releasePhotoSlot();
    }
  }

  void _cachePhoto(String key, Uint8List bytes) {
    _photoCache[key] = bytes;
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

  /// How many photos are pulled before anyone has scrolled.
  ///
  /// This used to be every place in the result set, on the reasoning that
  /// arriving at a column of empty placeholders looks broken. The billing
  /// disagreed: Place Details Photos is **72% of this app's Google spend**
  /// ($89.33 of $124 since 1 July, 14,183 calls), at 7.2 photos per search —
  /// and a phone shows about five rows, so most of what was prefetched was
  /// paid for and never looked at.
  ///
  /// Prefetching the rest is only free when the cache can absorb it, which
  /// needs the same places to come back. That happens for someone re-browsing
  /// one neighbourhood; it does not happen for this app's actual use, which is
  /// a single person browsing a different city each time.
  ///
  /// Rows past this still get their photo — [PlacePhoto] fetches on build, and
  /// those requests jump the queue via `priority` — they just get it when the
  /// row is about to be seen rather than in advance.
  static const int _eagerPhotoCount = 5;

  /// Pull the one photo each place displays, for the first screenful.
  ///
  /// Nothing waits on this: [loadPhoto] already serves whatever has landed and
  /// fetches the rest on demand. It exists so the list does not open on a
  /// column of empty placeholders, and so a photo already on disk is in memory
  /// before its row is ever built.
  Future<void> warmFirstPhotos() async {
    try {
      final refs = _firstPhotoRefs(_cachedRestaurants ?? const []);
      await prefetchFirstPhotos(refs.take(_eagerPhotoCount).toList());
    } catch (_) {
      // Warming is best effort, and both callers leave it unawaited — an
      // failure here must not surface as an unhandled async error.
    }
  }

  Future<void> prefetchFirstPhotos(
          List<({String ref, String cacheId})> photos) =>
      Future.wait(photos.map(
          (p) => loadPhoto(p.ref, cacheId: p.cacheId, priority: true)));

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
