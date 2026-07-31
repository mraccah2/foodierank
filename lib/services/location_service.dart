import 'package:geolocator/geolocator.dart';

/// The device's position, resolved once and shared.
///
/// A position used to be requested independently by `main`, the splash screen
/// and three separate paths in the list screen, each with its own accuracy and
/// timeout, each paying for its own fix. This keeps the most recent one and
/// hands it out.
class LocationService {
  static final LocationService instance = LocationService._();

  LocationService._();

  Position? _last;

  /// The most recent position resolved this session, if any.
  Position? get lastKnown => _last;

  /// How long a fix may take before falling back to whatever the OS already
  /// has. Ranking restaurants within a few hundred metres does not justify
  /// waiting on a cold GPS lock.
  static const Duration _fixTimeout = Duration(seconds: 8);

  /// A position for the user, or null when there is none to be had.
  ///
  /// Never throws. Every caller treats "no location" as a state to handle
  /// rather than an error — and the exception geolocator throws on its own
  /// `timeLimit` used to escape into a bare `catch` in `main`, which silently
  /// skipped the entire first search and left the app showing San Francisco.
  ///
  /// [accuracy] defaults to medium rather than best: the coarse network fix
  /// returns in a fraction of the time and is far inside the 300m granularity
  /// anything here cares about.
  Future<Position?> current({
    LocationAccuracy accuracy = LocationAccuracy.medium,
    Duration? timeout,
  }) async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // On a first launch this shows the OS dialog. It is deliberately no
        // longer on the pre-`runApp` path, where the app rendered nothing at
        // all until the user had answered it.
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return _last ?? await _fromOs();
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: accuracy,
        timeLimit: timeout ?? _fixTimeout,
      );
      _last = position;
      return position;
    } catch (e) {
      // A timeout, location services switched off, a revoked permission — to
      // callers these all mean the same thing: use the best position available.
      return _last ?? await _fromOs();
    }
  }

  Future<Position?> _fromOs() async {
    try {
      final position = await Geolocator.getLastKnownPosition();
      if (position != null) _last = position;
      return position;
    } catch (_) {
      return null;
    }
  }
}
