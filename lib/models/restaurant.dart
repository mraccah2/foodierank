import 'dart:math' show sqrt, sin, atan2, cos, pi;
import 'package:flutter/foundation.dart' show debugPrint;

class Restaurant {
  final String id;
  final String name;
  final String mainPhotoUrl;
  final List<String> photoRefs;
  final double rating;
  final int reviewCount;
  final List<String> types;
  final String priceLevel;
  final String description;
  final String address;
  final Location location;
  final List<Photo> photos;
  int? rank;
  final String placeId;

  /// Log-review excess over the place's ~500m neighbors, computed by
  /// `RestaurantService._applyLocalityScores`. Positive → people travel to it
  /// despite its quiet surroundings; negative → it rides a busy strip's foot
  /// traffic.
  final double destinationBonus;

  /// 0..1 density of tourist attractions and hotels within ~250m.
  final double touristPenalty;

  Restaurant({
    required this.id,
    required this.name,
    required this.mainPhotoUrl,
    this.photoRefs = const [],
    this.rating = 0.0,
    required this.reviewCount,
    this.types = const [],
    this.priceLevel = '',
    this.description = '',
    this.address = '',
    this.location = const Location(
        latitude: 0, longitude: 0, formattedAddress: '', country: ''),
    this.photos = const [],
    this.rank,
    required this.placeId,
    this.destinationBonus = 0.0,
    this.touristPenalty = 0.0,
  });

  factory Restaurant.fromJson(Map<String, dynamic> json) {
    // Debug check location data
    final locationData = json['location'];
    if (locationData != null) {
      final lat = locationData['latitude'];
      final lng = locationData['longitude'];
      if (lat == null ||
          lng == null ||
          lat is! double ||
          lng is! double ||
          lat.isNaN ||
          lng.isNaN) {
        debugPrint('dBug/restaurant: Invalid location data');
        debugPrint('dBug/restaurant: latitude: $lat (${lat.runtimeType})');
        debugPrint('dBug/restaurant: longitude: $lng (${lng.runtimeType})');
      }
    }

    final name = json['displayName']?['text'] ?? '';

    // Extract description with proper null checking
    String extractDescription(dynamic editorialSummary) {
      if (editorialSummary == null) return '';
      if (editorialSummary is Map<String, dynamic>) {
        return editorialSummary['text'] ?? '';
      }
      return '';
    }

    final description = extractDescription(json['editorialSummary']);

    // Helper function to safely convert various number formats
    int parseCount(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      if (value is double) return value.toInt();
      return 0;
    }

    // Helper function to safely extract photo references
    List<String> extractPhotoRefs(List<dynamic>? photos) {
      if (photos == null) return [];
      return photos
          .map((photo) => photo['name'] as String? ?? '')
          .where((ref) => ref.isNotEmpty)
          .toList();
    }

    String convertPriceLevel(String? level) {
      switch (level) {
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

    // Safely extract the placeId
    final placeId = json['id'] as String? ?? '';

    final restaurant = Restaurant(
      id: json['id'] as String? ?? '', // Ensure id is not null
      name: name,
      mainPhotoUrl: '',
      photoRefs: extractPhotoRefs(json['photos'] as List<dynamic>?),
      rating: (json['rating'] ?? 0.0).toDouble(),
      reviewCount: parseCount(json['userRatingCount']),
      types: (json['types'] as List<dynamic>?)?.cast<String>() ?? [],
      priceLevel: convertPriceLevel(json['priceLevel'] as String?),
      description: description,
      address: json['formattedAddress'] ?? '',
      location: Location(
        latitude: (json['location']?['latitude'] as num?)?.toDouble() ?? 0.0,
        longitude: (json['location']?['longitude'] as num?)?.toDouble() ?? 0.0,
        formattedAddress: json['formattedAddress'] ?? '',
        country: json['location']?['country'] ?? '',
      ),
      photos: [],
      rank: json['rank'] as int?,
      placeId: placeId,
      destinationBonus: (json['frDestinationBonus'] as num?)?.toDouble() ?? 0.0,
      touristPenalty: (json['frTouristPenalty'] as num?)?.toDouble() ?? 0.0,
    );

    // Debug check final location values
    if (restaurant.location.latitude.isNaN ||
        restaurant.location.longitude.isNaN) {
      debugPrint('dBug/restaurant: NaN coordinates in final restaurant object');
      debugPrint('dBug/restaurant: ${restaurant.name}');
      debugPrint(
          'dBug/restaurant: lat: ${restaurant.location.latitude}, lng: ${restaurant.location.longitude}');
    }

    return restaurant;
  }

  // Ranking constants. Quality is a Bayesian-shrunk rating in star units, and
  // the locality terms are expressed in star-equivalents so their reach is
  // easy to reason about: a maxed-out destination bonus is worth ±0.225 stars
  // and a fully tourist-saturated block costs 0.35 — enough to reorder good
  // places, never enough to lift a mediocre rating past a great one.
  static const double _priorMeanRating = 4.0;
  static const double _priorWeight = 40;
  static const double _destinationWeight = 0.15;
  static const double _touristWeight = 0.35;

  /// Bayesian-shrunk rating: pulled toward [_priorMeanRating] until enough
  /// reviews (~[_priorWeight]) accumulate. Unlike a Wilson lower bound, review
  /// volume saturates — 20,000 reviews confer almost no edge over 200, so
  /// sheer popularity can't outrank a genuinely better rating.
  double get qualityScore {
    if (reviewCount == 0 || rating.isNaN) return 0;
    return (reviewCount * rating + _priorWeight * _priorMeanRating) /
        (reviewCount + _priorWeight);
  }

  /// Final ranking score in star units: shrunk quality, plus a bonus for
  /// being heavily reviewed relative to its immediate surroundings ("worth
  /// the trip"), minus a penalty for sitting in an attraction/hotel pocket.
  double get rankingScore {
    if (reviewCount == 0) return 0;
    return qualityScore +
        _destinationWeight * destinationBonus -
        _touristWeight * touristPenalty;
  }
}

class Location {
  final double latitude;
  final double longitude;
  final String formattedAddress;
  final String country;

  const Location({
    required this.latitude,
    required this.longitude,
    required this.formattedAddress,
    required this.country,
  });

  String formatDistance(double currentLat, double currentLng) {
    // Debug check input coordinates
    if (currentLat.isNaN ||
        currentLng.isNaN ||
        latitude.isNaN ||
        longitude.isNaN) {
      debugPrint('dBug/location: NaN coordinates in formatDistance');
      debugPrint(
          'dBug/location: currentLat: $currentLat, currentLng: $currentLng');
      debugPrint('dBug/location: latitude: $latitude, longitude: $longitude');
      return 'Distance unavailable';
    }

    final distance =
        calculateDistance(currentLat, currentLng, latitude, longitude);

    // Debug check calculated distance
    if (distance.isNaN) {
      debugPrint('dBug/location: NaN distance calculated');
      debugPrint('dBug/location: distance: $distance');
      return 'Distance unavailable';
    }

    return distance < 1
        ? '${(distance * 1000).round()}m'
        : '${distance.toStringAsFixed(1)}km';
  }

  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    // Debug check input coordinates
    if (lat1.isNaN || lon1.isNaN || lat2.isNaN || lon2.isNaN) {
      debugPrint('dBug/location: NaN coordinates in calculateDistance');
      debugPrint('dBug/location: lat1: $lat1, lon1: $lon1');
      debugPrint('dBug/location: lat2: $lat2, lon2: $lon2');
      return double.nan;
    }

    const r = 6371;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    // Debug check radians conversion
    if (dLat.isNaN || dLon.isNaN) {
      debugPrint('dBug/location: NaN in radians conversion');
      debugPrint('dBug/location: dLat: $dLat, dLon: $dLon');
      return double.nan;
    }

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    // Debug check sin/cos calculations
    if (a.isNaN) {
      debugPrint('dBug/location: NaN in trigonometric calculation');
      debugPrint('dBug/location: a: $a');
      return double.nan;
    }

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  double _toRadians(double degree) => degree * pi / 180;
}

class Photo {
  final String url;

  Photo.fromJson(Map<String, dynamic> json) : url = json['url'];
}
