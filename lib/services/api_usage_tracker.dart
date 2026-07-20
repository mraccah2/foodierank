import 'package:flutter/foundation.dart';

class ApiUsageTracker {
  static final ApiUsageTracker instance = ApiUsageTracker._internal();

  factory ApiUsageTracker() {
    return instance;
  }

  ApiUsageTracker._internal();

  // Call counters
  int _textSearchCalls = 0;
  int _nearbySearchCalls = 0;
  int _photoCalls = 0;
  int _placeDetailsCalls = 0;

  // Cost per call in USD
  static const double textSearchCost = 0.032;
  static const double nearbySearchCost = 0.032;
  static const double photoCost = 0.007;
  static const double placeDetailsCost = 0.017;

  // Track calls
  void incrementTextSearch() => _textSearchCalls++;
  void incrementNearbySearch() => _nearbySearchCalls++;
  void incrementPhoto() => _photoCalls++;
  void incrementPlaceDetails() => _placeDetailsCalls++;

  // Calculate total cost
  double get totalCost {
    return (_textSearchCalls * textSearchCost) +
        (_nearbySearchCalls * nearbySearchCost) +
        (_photoCalls * photoCost) +
        (_placeDetailsCalls * placeDetailsCost);
  }

  // Print usage stats
  void printUsageStats() {
    debugPrint('dBug/api_usage: API Usage Statistics:');
    debugPrint(
        'dBug/api_usage: Text Search Calls: $_textSearchCalls (Cost: \$${(_textSearchCalls * textSearchCost).toStringAsFixed(3)})');
    debugPrint(
        'dBug/api_usage: Nearby Search Calls: $_nearbySearchCalls (Cost: \$${(_nearbySearchCalls * nearbySearchCost).toStringAsFixed(3)})');
    debugPrint(
        'dBug/api_usage: Photo Calls: $_photoCalls (Cost: \$${(_photoCalls * photoCost).toStringAsFixed(3)})');
    debugPrint(
        'dBug/api_usage: Place Details Calls: $_placeDetailsCalls (Cost: \$${(_placeDetailsCalls * placeDetailsCost).toStringAsFixed(3)})');
    debugPrint('dBug/api_usage: Total Cost: \$${totalCost.toStringAsFixed(3)}');
  }

  // Reset counters
  void reset() {
    _textSearchCalls = 0;
    _nearbySearchCalls = 0;
    _photoCalls = 0;
    _placeDetailsCalls = 0;
  }
}
