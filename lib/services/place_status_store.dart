import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/place_status.dart';
import '../utils/debug_log.dart';

/// Read/write access to the signed-in user's saved-place markers.
///
/// The app is fully usable signed out — in that case [isAvailable] is false and
/// [stateFor] returns [PlaceSaveState.empty] for everything, so no markers
/// render.
///
/// Implementations notify listeners whenever the backing data changes, so
/// cards can rebuild without threading callbacks through the widget tree.
///
/// ## On clearing a marker
///
/// Clearing is **local to FoodieRank**. Google exposes no API for writing a
/// user's saved places, so a cleared heart/star/flag will reappear in Google
/// Maps and is re-applied on the next import unless we remember the clear.
/// Implementations therefore persist clears as tombstones rather than simply
/// deleting the row — see [LocalPlaceStatusStore._cleared].
abstract class PlaceStatusStore extends ChangeNotifier {
  /// True once a user is signed in and their data has loaded. When false,
  /// callers should render no markers at all.
  bool get isAvailable;

  PlaceSaveState stateFor(String placeId);

  /// Drop the highest-precedence marker on [placeId], revealing the next one
  /// if the place carries more than one.
  Future<void> clearTopStatus(String placeId);

  /// Mark [placeId] with [status] regardless of what Google knows.
  ///
  /// This is FoodieRank's own data: a place spotted in the rankings and saved
  /// for later. It survives re-imports, because imports only replace what came
  /// from Google, and it is never written back to Google Maps — there is no API
  /// for that.
  Future<void> addStatus(String placeId, PlaceStatus status);
}

/// The store the UI reads from.
PlaceStatusStore get placeStatusStore => PlaceStatusController.instance;

/// Forwards to whichever store is currently in play.
///
/// Widgets listen to this one object for the life of the app, so signing in or
/// out swaps the backing store underneath them without any rebuild plumbing:
/// [LocalPlaceStatusStore] when signed out, the Firestore-backed store when
/// signed in.
class PlaceStatusController extends PlaceStatusStore {
  static final PlaceStatusController instance = PlaceStatusController._();

  PlaceStatusController._() {
    _delegate.addListener(notifyListeners);
  }

  PlaceStatusStore _delegate = LocalPlaceStatusStore.instance;

  PlaceStatusStore get delegate => _delegate;

  void useStore(PlaceStatusStore store) {
    if (identical(_delegate, store)) return;
    _delegate.removeListener(notifyListeners);
    _delegate = store;
    _delegate.addListener(notifyListeners);
    notifyListeners();
  }

  /// Fall back to the on-device store — used on sign-out.
  void useLocal() => useStore(LocalPlaceStatusStore.instance);

  @override
  bool get isAvailable => _delegate.isAvailable;

  @override
  PlaceSaveState stateFor(String placeId) => _delegate.stateFor(placeId);

  @override
  Future<void> clearTopStatus(String placeId) =>
      _delegate.clearTopStatus(placeId);

  @override
  Future<void> addStatus(String placeId, PlaceStatus status) =>
      _delegate.addStatus(placeId, status);
}

/// A [PlaceStatusStore] that keeps everything on-device in `shared_preferences`.
///
/// This is the Phase 1 implementation: it holds imported markers and the user's
/// clears, but performs no import itself. The Supabase-backed store replaces it
/// without any change to the widgets, which depend only on [PlaceStatusStore].
class LocalPlaceStatusStore extends PlaceStatusStore {
  static final LocalPlaceStatusStore instance = LocalPlaceStatusStore._();

  LocalPlaceStatusStore._();

  /// A fresh, isolated instance. The app uses [instance]; tests need a store
  /// that does not carry state between cases.
  @visibleForTesting
  factory LocalPlaceStatusStore.forTesting() => LocalPlaceStatusStore._();

  static const _statesPrefix = 'place_save_states';
  static const _clearedPrefix = 'place_save_cleared';
  static const _addedPrefix = 'place_save_added';
  static const _accountKey = 'place_save_account';

  // Per-account keys: two Google accounts on one device must not see each
  // other's markers, and signing back in should restore what was cached.
  String get _statesKey => '$_statesPrefix:$_accountId';
  String get _clearedKey => '$_clearedPrefix:$_accountId';
  String get _addedKey => '$_addedPrefix:$_accountId';

  /// Markers as last imported from Google, keyed by `place_id`.
  final Map<String, PlaceSaveState> _states = {};

  /// Markers the user has tapped away, keyed by `place_id`. Kept separately so
  /// a re-import cannot resurrect them.
  final Map<String, Set<PlaceStatus>> _cleared = {};

  /// Markers the user added here rather than in Google Maps. Also separate, so
  /// an import that knows nothing about them cannot wipe them.
  final Map<String, Set<PlaceStatus>> _added = {};

  String? _accountId;
  bool _loaded = false;

  @override
  bool get isAvailable => _loaded && _accountId != null;

  /// Restore the cached markers for whoever was last signed in. Safe to call
  /// more than once.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _accountId = prefs.getString(_accountKey);
      if (_accountId != null) {
        _readStates(prefs);
        _readCleared(prefs);
        _readAdded(prefs);
      }
    } catch (e) {
      debugLog('dBug/place_status: load failed: $e');
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  /// Point the store at a signed-in Google account. Switching accounts drops
  /// the previous account's cached markers rather than blending them.
  Future<void> setAccount(String? accountId) async {
    if (_accountId == accountId) return;
    _accountId = accountId;
    _states.clear();
    _cleared.clear();
    _added.clear();

    final prefs = await SharedPreferences.getInstance();
    if (accountId == null) {
      // Signing out forgets *who* is signed in but keeps their cached markers,
      // so signing back in does not require a fresh import.
      await prefs.remove(_accountKey);
    } else {
      await prefs.setString(_accountKey, accountId);
      _readStates(prefs);
      _readCleared(prefs);
      _readAdded(prefs);
    }
    notifyListeners();
  }

  /// Replace the imported markers wholesale — the shape an import produces.
  /// Previously cleared markers stay cleared.
  Future<void> replaceAll(Map<String, PlaceSaveState> states) async {
    _states
      ..clear()
      ..addAll(states);
    await _persistStates();
    notifyListeners();
  }

  @override
  PlaceSaveState stateFor(String placeId) {
    if (!isAvailable) return PlaceSaveState.empty;
    final imported = _states[placeId] ?? PlaceSaveState.empty;
    final added = _added[placeId] ?? const <PlaceStatus>{};
    final cleared = _cleared[placeId] ?? const <PlaceStatus>{};

    final statuses = {...imported.statuses, ...added}
        .where((s) => !cleared.contains(s))
        .toSet();

    if (statuses.isEmpty && imported.lists.isEmpty) return PlaceSaveState.empty;
    return PlaceSaveState(statuses: statuses, lists: imported.lists);
  }

  @override
  Future<void> addStatus(String placeId, PlaceStatus status) async {
    // Adding after a clear has to lift the tombstone, or the marker would be
    // filtered straight back out.
    _cleared[placeId]?.remove(status);
    (_added[placeId] ??= <PlaceStatus>{}).add(status);
    notifyListeners();

    try {
      await _persistCleared();
      await _persistAdded();
    } catch (e) {
      debugLog('dBug/place_status: persist add failed: $e');
    }
  }

  @override
  Future<void> clearTopStatus(String placeId) async {
    final top = stateFor(placeId).displayStatus;
    if (top == null) return;

    (_cleared[placeId] ??= <PlaceStatus>{}).add(top);
    // A marker the user added here is simply forgotten rather than tombstoned.
    _added[placeId]?.remove(top);
    notifyListeners();

    try {
      await _persistCleared();
      await _persistAdded();
    } catch (e) {
      debugLog('dBug/place_status: persist clear failed: $e');
    }
  }

  void _readStates(SharedPreferences prefs) {
    final raw = prefs.getString(_statesKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded.forEach((placeId, value) {
        _states[placeId] =
            PlaceSaveState.fromJson(value as Map<String, dynamic>);
      });
    } catch (e) {
      debugLog('dBug/place_status: could not decode states: $e');
    }
  }

  void _readAdded(SharedPreferences prefs) {
    _readStatusMap(prefs.getString(_addedKey), _added, 'adds');
  }

  void _readCleared(SharedPreferences prefs) {
    _readStatusMap(prefs.getString(_clearedKey), _cleared, 'clears');
  }

  Future<void> _persistStates() async {
    if (_accountId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final encoded = <String, dynamic>{};
    _states.forEach((placeId, state) => encoded[placeId] = state.toJson());
    await prefs.setString(_statesKey, jsonEncode(encoded));
  }

  Future<void> _persistCleared() => _persistStatusMap(_clearedKey, _cleared);

  Future<void> _persistAdded() => _persistStatusMap(_addedKey, _added);

  Future<void> _persistStatusMap(
    String key,
    Map<String, Set<PlaceStatus>> source,
  ) async {
    if (_accountId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final encoded = <String, dynamic>{};
    source.forEach((placeId, statuses) {
      if (statuses.isEmpty) return;
      encoded[placeId] = statuses.map((s) => s.storageKey).toList();
    });
    await prefs.setString(key, jsonEncode(encoded));
  }

  void _readStatusMap(
    String? raw,
    Map<String, Set<PlaceStatus>> target,
    String label,
  ) {
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded.forEach((placeId, value) {
        target[placeId] = (value as List)
            .whereType<String>()
            .map(PlaceStatusDisplay.fromStorageKey)
            .whereType<PlaceStatus>()
            .toSet();
      });
    } catch (e) {
      debugLog('dBug/place_status: could not decode $label: $e');
    }
  }
}
