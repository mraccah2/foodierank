import 'dart:math' show sin, cos, sqrt, atan2, pi;
import 'package:intl/intl.dart';

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
    final distanceKm =
        calculateDistance(latitude, longitude, currentLat, currentLng);

    // Use system locale to determine units
    final useImperial = Intl.getCurrentLocale().startsWith('en_US');

    if (useImperial) {
      final distanceMiles = distanceKm * 0.621371;
      if (distanceMiles < 0.1) {
        return 'Distance: approx. ${(distanceMiles * 5280).round()}ft';
      }
      return 'Distance: approx. ${distanceMiles.toStringAsFixed(1)}mi';
    } else {
      if (distanceKm < 1) {
        return 'Distance: approx. ${(distanceKm * 1000).round()}m';
      }
      return 'Distance: approx. ${distanceKm.toStringAsFixed(1)}km';
    }
  }

  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371; // Earth's radius in km
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  double _toRadians(double degree) => degree * pi / 180;
}
