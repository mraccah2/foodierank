import 'dart:math' show sqrt, sin, atan2, cos, pi;

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
    this.location = const Location(latitude: 0, longitude: 0, formattedAddress: ''),
    this.photos = const [],
    this.rank,
    required this.placeId,
  });

  factory Restaurant.fromJson(Map<String, dynamic> json) {
    // Debug check location data
    final locationData = json['location'];
    if (locationData != null) {
      final lat = locationData['latitude'];
      final lng = locationData['longitude'];
      if (lat == null || lng == null || lat is! double || lng is! double || lat.isNaN || lng.isNaN) {
        print('dBug/restaurant: Invalid location data');
        print('dBug/restaurant: latitude: $lat (${lat.runtimeType})');
        print('dBug/restaurant: longitude: $lng (${lng.runtimeType})');
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
      ),
      photos: [],
      rank: json['rank'] as int?,
      placeId: placeId,
    );
    
    // Debug check final location values
    if (restaurant.location.latitude.isNaN || restaurant.location.longitude.isNaN) {
      print('dBug/restaurant: NaN coordinates in final restaurant object');
      print('dBug/restaurant: ${restaurant.name}');
      print('dBug/restaurant: lat: ${restaurant.location.latitude}, lng: ${restaurant.location.longitude}');
    }
    
    return restaurant;
  }

  double calculateWilsonScore(double rating, int reviewCount) {
    if (reviewCount == 0) return 0;
    
    // Debug check input values
    if (rating.isNaN) {
      print('dBug/restaurant: NaN rating in Wilson score calculation');
      print('dBug/restaurant: rating: $rating, reviewCount: $reviewCount');
      return 0;
    }
    
    const z = 1.96;
    final p = rating / 5.0;
    final n = reviewCount.toDouble();
    
    final numerator = p + z * z / (2 * n) - z * sqrt((p * (1 - p) + z * z / (4 * n)) / n);
    final denominator = 1 + z * z / n;
    
    final score = numerator / denominator;
    
    // Debug check final score
    if (score.isNaN) {
      print('dBug/restaurant: NaN Wilson score calculated');
      print('dBug/restaurant: rating: $rating, reviewCount: $reviewCount');
      print('dBug/restaurant: numerator: $numerator, denominator: $denominator');
      return 0;
    }
    
    return score;
  }
}

class Location {
  final double latitude;
  final double longitude;
  final String formattedAddress;

  const Location({
    required this.latitude,
    required this.longitude,
    required this.formattedAddress,
  });

  String formatDistance(double currentLat, double currentLng) {
    // Debug check input coordinates
    if (currentLat.isNaN || currentLng.isNaN || latitude.isNaN || longitude.isNaN) {
      print('dBug/location: NaN coordinates in formatDistance');
      print('dBug/location: currentLat: $currentLat, currentLng: $currentLng');
      print('dBug/location: latitude: $latitude, longitude: $longitude');
      return 'Distance unavailable';
    }

    final distance = calculateDistance(currentLat, currentLng, latitude, longitude);
    
    // Debug check calculated distance
    if (distance.isNaN) {
      print('dBug/location: NaN distance calculated');
      print('dBug/location: distance: $distance');
      return 'Distance unavailable';
    }
    
    return distance < 1 
      ? '${(distance * 1000).round()}m'
      : '${distance.toStringAsFixed(1)}km';
  }

  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    // Debug check input coordinates
    if (lat1.isNaN || lon1.isNaN || lat2.isNaN || lon2.isNaN) {
      print('dBug/location: NaN coordinates in calculateDistance');
      print('dBug/location: lat1: $lat1, lon1: $lon1');
      print('dBug/location: lat2: $lat2, lon2: $lon2');
      return double.nan;
    }

    const r = 6371;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    
    // Debug check radians conversion
    if (dLat.isNaN || dLon.isNaN) {
      print('dBug/location: NaN in radians conversion');
      print('dBug/location: dLat: $dLat, dLon: $dLon');
      return double.nan;
    }

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    
    // Debug check sin/cos calculations
    if (a.isNaN) {
      print('dBug/location: NaN in trigonometric calculation');
      print('dBug/location: a: $a');
      return double.nan;
    }

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  double _toRadians(double degree) => degree * pi / 180;
}

class Photo {
  final String url;

  Photo.fromJson(Map<String, dynamic> json)
      : url = json['url'];
}