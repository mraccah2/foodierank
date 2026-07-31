import 'auth_service.dart';
import 'place_status_store.dart';
import 'saved_places_coordinator.dart';

/// Brings up the optional saved-places feature.
///
/// None of this gates the restaurant list: signed out, the stores report
/// nothing and no markers render. So it runs alongside the first search rather
/// than in front of it. It used to be awaited before `runApp`, which put a
/// `SharedPreferences` round trip, `Firebase.initializeApp` and the Google
/// Sign-In handshake between a cold launch and the first frame.
class Bootstrap {
  static Future<void>? _running;

  /// Idempotent — the first call starts the work, later ones await the same
  /// future.
  static Future<void> start() => _running ??= _run();

  static Future<void> _run() async {
    // Cached markers first, so a signed-in user's hearts and stars are already
    // in place when the first cards render rather than popping in a beat later.
    await LocalPlaceStatusStore.instance.load();
    // Never throws: an unconfigured build simply leaves the feature switched
    // off, and the coordinator keeps the active store in step with whoever is
    // signed in.
    await AuthService.instance.initialize();
    SavedPlacesCoordinator.instance.start();
  }
}
