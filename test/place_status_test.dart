import 'package:flutter_test/flutter_test.dart';
import 'package:foodierank/models/place_status.dart';
import 'package:foodierank/services/place_status_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PlaceSaveState precedence', () {
    test('heart wins over star and flag', () {
      const state = PlaceSaveState(statuses: {
        PlaceStatus.starred,
        PlaceStatus.wantToGo,
        PlaceStatus.loved,
      });
      expect(state.displayStatus, PlaceStatus.loved);
    });

    test('star wins over flag', () {
      const state = PlaceSaveState(
        statuses: {PlaceStatus.wantToGo, PlaceStatus.starred},
      );
      expect(state.displayStatus, PlaceStatus.starred);
    });

    test('nextStatus is what surfaces after clearing the top marker', () {
      const state = PlaceSaveState(statuses: {
        PlaceStatus.loved,
        PlaceStatus.wantToGo,
      });
      expect(state.nextStatus, PlaceStatus.wantToGo);
      expect(state.without(PlaceStatus.loved).displayStatus,
          PlaceStatus.wantToGo);
    });

    test('nextStatus is null when only one marker is present', () {
      const state = PlaceSaveState(statuses: {PlaceStatus.starred});
      expect(state.nextStatus, isNull);
    });

    test('a place in a list but carrying no marker is still not empty', () {
      const state = PlaceSaveState(lists: {'Iceland trip'});
      expect(state.displayStatus, isNull);
      expect(state.isNotEmpty, isTrue);
    });

    test('round-trips through JSON', () {
      const state = PlaceSaveState(
        statuses: {PlaceStatus.loved, PlaceStatus.starred},
        lists: {'Iceland trip', 'Tokyo'},
      );
      expect(PlaceSaveState.fromJson(state.toJson()), state);
    });
  });

  group('LocalPlaceStatusStore', () {
    late LocalPlaceStatusStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = LocalPlaceStatusStore.forTesting();
      await store.load();
      await store.setAccount('google-user-1');
      await store.replaceAll({
        'place-a': const PlaceSaveState(statuses: {
          PlaceStatus.loved,
          PlaceStatus.starred,
        }),
        'place-b': const PlaceSaveState(lists: {'Iceland trip'}),
      });
    });

    test('renders nothing when signed out', () async {
      await store.setAccount(null);
      expect(store.isAvailable, isFalse);
      expect(store.stateFor('place-a'), PlaceSaveState.empty);
    });

    test('tapping clears the top marker and reveals the next', () async {
      expect(store.stateFor('place-a').displayStatus, PlaceStatus.loved);

      await store.clearTopStatus('place-a');
      expect(store.stateFor('place-a').displayStatus, PlaceStatus.starred);

      await store.clearTopStatus('place-a');
      expect(store.stateFor('place-a').displayStatus, isNull);
    });

    test('clearing a marker does not disturb list membership', () async {
      await store.clearTopStatus('place-a');
      expect(store.stateFor('place-b').lists, {'Iceland trip'});
    });

    test('a re-import does not resurrect a cleared marker', () async {
      await store.clearTopStatus('place-a');
      expect(store.stateFor('place-a').displayStatus, PlaceStatus.starred);

      // Google still reports the heart — it was only ever cleared locally,
      // since there is no API to write the change back to Maps.
      await store.replaceAll({
        'place-a': const PlaceSaveState(statuses: {
          PlaceStatus.loved,
          PlaceStatus.starred,
        }),
      });

      expect(store.stateFor('place-a').displayStatus, PlaceStatus.starred);
    });

    test('notifies listeners so cards rebuild on a clear', () async {
      var notifications = 0;
      store.addListener(() => notifications++);
      await store.clearTopStatus('place-a');
      expect(notifications, greaterThan(0));
    });

    test('switching accounts drops the previous account markers', () async {
      await store.setAccount('google-user-2');
      expect(store.stateFor('place-a'), PlaceSaveState.empty);
    });
  });

  group('PlaceStatusController', () {
    test('forwards reads to whichever store is active', () {
      final controller = PlaceStatusController.instance;
      final remote = _FakeStore({
        'place-a': const PlaceSaveState(statuses: {PlaceStatus.loved}),
      });

      controller.useStore(remote);
      expect(controller.stateFor('place-a').displayStatus, PlaceStatus.loved);

      controller.useLocal();
      expect(controller.stateFor('place-a'), PlaceSaveState.empty);
    });

    test('a swap notifies listeners so cards rebuild', () {
      final controller = PlaceStatusController.instance;
      controller.useLocal();

      var notifications = 0;
      void listener() => notifications++;
      controller.addListener(listener);

      controller.useStore(_FakeStore(const {}));
      expect(notifications, 1);

      controller.removeListener(listener);
      controller.useLocal();
    });

    test('changes in the active store reach the controller', () {
      final controller = PlaceStatusController.instance;
      final remote = _FakeStore({
        'place-a': const PlaceSaveState(statuses: {PlaceStatus.starred}),
      });
      controller.useStore(remote);

      var notifications = 0;
      void listener() => notifications++;
      controller.addListener(listener);

      remote.clearTopStatus('place-a');
      expect(notifications, greaterThan(0));
      expect(controller.stateFor('place-a').displayStatus, isNull);

      controller.removeListener(listener);
      controller.useLocal();
    });

    test('a detached store no longer notifies the controller', () {
      final controller = PlaceStatusController.instance;
      final first = _FakeStore({
        'place-a': const PlaceSaveState(statuses: {PlaceStatus.loved}),
      });
      controller.useStore(first);
      controller.useStore(_FakeStore(const {}));

      var notifications = 0;
      void listener() => notifications++;
      controller.addListener(listener);

      first.clearTopStatus('place-a');
      expect(notifications, 0);

      controller.removeListener(listener);
      controller.useLocal();
    });
  });
}

/// Minimal in-memory store, standing in for the Firestore-backed one.
class _FakeStore extends PlaceStatusStore {
  final Map<String, PlaceSaveState> _states;

  _FakeStore(Map<String, PlaceSaveState> states)
      : _states = Map.of(states);

  @override
  bool get isAvailable => true;

  @override
  PlaceSaveState stateFor(String placeId) =>
      _states[placeId] ?? PlaceSaveState.empty;

  @override
  Future<void> clearTopStatus(String placeId) async {
    final top = stateFor(placeId).displayStatus;
    if (top == null) return;
    _states[placeId] = stateFor(placeId).without(top);
    notifyListeners();
  }
}
