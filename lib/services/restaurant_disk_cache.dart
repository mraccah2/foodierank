import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_log.dart';
import 'restaurant_service.dart';

/// Persists the last search result set, so a relaunch has something to show
/// before the network answers.
///
/// The in-memory cache lived and died with the process, which meant every cold
/// start paid the full pipeline — a location fix plus up to thirty Places
/// requests — even when it had run four minutes earlier.
///
/// Only the place JSON is stored, never the photo bytes: the JSON is a couple
/// of hundred kilobytes at most, which `shared_preferences` handles fine, while
/// the photos would be megabytes. Photos re-fetch lazily as rows scroll into
/// view, so the list still renders immediately.
class RestaurantDiskCache {
  static const String _key = 'cached_search_results_v1';

  /// Past this, a stored result set is not worth showing even briefly: "open
  /// now" will have moved on, and the user is more likely somewhere else.
  static const Duration maxAge = Duration(hours: 6);

  /// Wire the service up to persist every successful search.
  static void install() {
    RestaurantService.instance.onResults = save;
  }

  static Future<void> save(RestaurantSearchSnapshot snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(snapshot.toJson()));
    } catch (e) {
      debugLog('dBug/cache: could not persist results: $e');
    }
  }

  /// The stored result set, or null when there is none, it cannot be decoded,
  /// or it is older than [maxAge].
  static Future<RestaurantSearchSnapshot?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;

      final snapshot = RestaurantSearchSnapshot.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
      if (snapshot == null) return null;
      if (DateTime.now().difference(snapshot.fetchedAt) > maxAge) return null;
      return snapshot;
    } catch (e) {
      debugLog('dBug/cache: could not read results: $e');
      return null;
    }
  }
}
