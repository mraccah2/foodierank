import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/place_status.dart';
import '../utils/debug_log.dart';
import 'place_status_store.dart';

/// A [PlaceStatusStore] backed by the Firestore mirror the Cloud Functions
/// write into.
///
/// Two collections are watched:
///  * `savedPlaces` — markers imported from Google. Read-only here; the client
///    cannot write back, because Google exposes no write API.
///  * `clears` — markers the user tapped away. Client-owned, and the reason a
///    re-import cannot resurrect something the user removed.
///
/// Firestore's offline cache means markers still render without a connection.
class FirestorePlaceStatusStore extends PlaceStatusStore {
  final String uid;
  final FirebaseFirestore _firestore;

  final Map<String, PlaceSaveState> _saved = {};
  final Map<String, Set<PlaceStatus>> _cleared = {};
  final Map<String, Set<PlaceStatus>> _marks = {};

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _savedSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _clearedSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _marksSub;

  bool _savedLoaded = false;

  FirestorePlaceStatusStore({
    required this.uid,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  bool get isAvailable => _savedLoaded;

  CollectionReference<Map<String, dynamic>> get _savedRef =>
      _firestore.collection('users').doc(uid).collection('savedPlaces');

  CollectionReference<Map<String, dynamic>> get _clearsRef =>
      _firestore.collection('users').doc(uid).collection('clears');

  /// Markers the user added in FoodieRank rather than in Google Maps.
  CollectionReference<Map<String, dynamic>> get _marksRef =>
      _firestore.collection('users').doc(uid).collection('marks');

  /// Start listening. Safe to call once per instance.
  void start() {
    _savedSub ??= _savedRef.snapshots().listen(
      (snapshot) {
        _saved.clear();
        for (final doc in snapshot.docs) {
          _saved[doc.id] = _stateFromDoc(doc.data());
        }
        _savedLoaded = true;
        notifyListeners();
      },
      onError: (Object e) => debugLog('dBug/place_status: savedPlaces: $e'),
    );

    _clearedSub ??= _clearsRef.snapshots().listen(
      (snapshot) {
        _cleared.clear();
        for (final doc in snapshot.docs) {
          _cleared[doc.id] = _statusesFrom(doc.data()['statuses']);
        }
        notifyListeners();
      },
      onError: (Object e) => debugLog('dBug/place_status: clears: $e'),
    );

    _marksSub ??= _marksRef.snapshots().listen(
      (snapshot) {
        _marks.clear();
        for (final doc in snapshot.docs) {
          _marks[doc.id] = _statusesFrom(doc.data()['statuses']);
        }
        notifyListeners();
      },
      onError: (Object e) => debugLog('dBug/place_status: marks: $e'),
    );
  }

  @override
  PlaceSaveState stateFor(String placeId) {
    if (!isAvailable) return PlaceSaveState.empty;

    final imported = _saved[placeId] ?? PlaceSaveState.empty;
    final marks = _marks[placeId] ?? const <PlaceStatus>{};
    final cleared = _cleared[placeId] ?? const <PlaceStatus>{};

    final statuses = {...imported.statuses, ...marks}
        .where((s) => !cleared.contains(s))
        .toSet();

    if (statuses.isEmpty && imported.lists.isEmpty) return PlaceSaveState.empty;
    return PlaceSaveState(statuses: statuses, lists: imported.lists);
  }

  @override
  Future<void> addStatus(String placeId, PlaceStatus status) async {
    final marks = {...(_marks[placeId] ?? const <PlaceStatus>{}), status};
    final cleared = {...(_cleared[placeId] ?? const <PlaceStatus>{})}
      ..remove(status);

    _marks[placeId] = marks;
    _cleared[placeId] = cleared;
    notifyListeners();

    try {
      await _marksRef.doc(placeId).set({
        'statuses': marks.map((s) => s.storageKey).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // Adding after a clear must lift the tombstone, or the import merge
      // would filter the marker straight back out.
      await _clearsRef.doc(placeId).set({
        'statuses': cleared.map((s) => s.storageKey).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugLog('dBug/place_status: could not persist mark: $e');
    }
  }

  @override
  Future<void> clearTopStatus(String placeId) async {
    final top = stateFor(placeId).displayStatus;
    if (top == null) return;

    // Optimistic: the snapshot listener will confirm, but the icon should
    // change under the user's finger rather than after a round trip.
    (_cleared[placeId] ??= <PlaceStatus>{}).add(top);
    final marks = {...(_marks[placeId] ?? const <PlaceStatus>{})}..remove(top);
    _marks[placeId] = marks;
    notifyListeners();

    try {
      await _clearsRef.doc(placeId).set({
        'statuses': _cleared[placeId]!.map((s) => s.storageKey).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // A marker the user added here is dropped outright rather than
      // tombstoned — there is no import that would bring it back.
      await _marksRef.doc(placeId).set({
        'statuses': marks.map((s) => s.storageKey).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugLog('dBug/place_status: could not persist clear: $e');
      // Roll back so the UI keeps matching what is actually stored.
      _cleared[placeId]?.remove(top);
      notifyListeners();
    }
  }

  PlaceSaveState _stateFromDoc(Map<String, dynamic> data) => PlaceSaveState(
        statuses: _statusesFrom(data['statuses']),
        lists: (data['lists'] as List?)?.whereType<String>().toSet() ?? {},
      );

  Set<PlaceStatus> _statusesFrom(Object? raw) =>
      (raw as List?)
          ?.whereType<String>()
          .map(PlaceStatusDisplay.fromStorageKey)
          .whereType<PlaceStatus>()
          .toSet() ??
      {};

  @override
  void dispose() {
    _savedSub?.cancel();
    _clearedSub?.cancel();
    _marksSub?.cancel();
    super.dispose();
  }
}
