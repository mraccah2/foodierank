import 'auth_service.dart';
import 'firestore_place_status_store.dart';
import 'place_status_store.dart';

/// Keeps the active [PlaceStatusStore] in step with who is signed in.
///
/// Signed out — or with Firebase unconfigured — the local store is used, and it
/// reports nothing, so no markers render. Signing in swaps in a Firestore store
/// scoped to that uid; signing out swaps back.
class SavedPlacesCoordinator {
  static final SavedPlacesCoordinator instance = SavedPlacesCoordinator._();

  SavedPlacesCoordinator._();

  FirestorePlaceStatusStore? _remote;
  String? _boundUid;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    AuthService.instance.addListener(_syncToAuthState);
    _syncToAuthState();
  }

  void _syncToAuthState() {
    final uid = AuthService.instance.uid;
    if (uid == _boundUid) return;
    _boundUid = uid;

    // Tear down the previous user's listeners before attaching new ones.
    _remote?.dispose();
    _remote = null;

    if (uid == null) {
      PlaceStatusController.instance.useLocal();
      LocalPlaceStatusStore.instance.setAccount(null);
      return;
    }

    final remote = FirestorePlaceStatusStore(uid: uid)..start();
    _remote = remote;
    PlaceStatusController.instance.useStore(remote);
    // Keep the local store pointed at the same account so it remains a usable
    // fallback if Firestore is ever unavailable.
    LocalPlaceStatusStore.instance.setAccount(uid);
  }
}
