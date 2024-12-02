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
  });

  factory Restaurant.fromJson(Map<String, dynamic> json) {
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

    final restaurant = Restaurant(
      id: json['id'] as String,
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
        latitude: json['location']['latitude'],
        longitude: json['location']['longitude'],
        formattedAddress: json['formattedAddress'],
      ),
      photos: [],
      rank: json['rank'] as int?,
    );
    
    return restaurant;
  }

  double calculateWilsonScore(double rating, int reviewCount) {
    if (reviewCount == 0) return 0;
    
    const z = 1.96; // 95% confidence interval
    final p = rating / 5.0; // Convert 5-star rating to probability
    final n = reviewCount.toDouble();
    
    final numerator = p + z * z / (2 * n) - z * sqrt((p * (1 - p) + z * z / (4 * n)) / n);
    final denominator = 1 + z * z / n;
    
    return numerator / denominator;
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
    final distance = calculateDistance(latitude, longitude, currentLat, currentLng);
    return distance < 1 
      ? '${(distance * 1000).round()}m'
      : '${distance.toStringAsFixed(1)}km';
  }

  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2);
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