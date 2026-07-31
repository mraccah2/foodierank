import 'dart:async';

import 'package:flutter/material.dart';

import '../services/bootstrap.dart';
import '../services/location_service.dart';
import '../services/restaurant_disk_cache.dart';
import '../services/restaurant_service.dart';
import 'restaurant_list_screen.dart';

/// The first screen: a brief, bounded warm-up before the list takes over.
///
/// It restores the last session's results, starts the saved-places feature and
/// resolves a position — none of which the list screen strictly needs, because
/// it resolves whatever is missing itself and has its own error and retry. So
/// this screen never blocks on any of it: whatever has not finished by
/// [_deadline] simply happens later.
///
/// It used to await a full Places search here — and before that, `main` awaited
/// one too — with no ceiling on either, which is how a slow network turned into
/// an app that never opened.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  /// Past this the user is better served by the list screen, which can show
  /// progress and offer a retry, than by a splash that might never end.
  static const Duration _deadline = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _prepare() async {
    // The saved-places feature is independent of the search, so it comes up
    // alongside rather than in front of it.
    unawaited(Bootstrap.start());

    // Whatever the last session left behind, so the list has something to draw
    // before the network answers. The list screen decides whether it is still
    // current (see RestaurantService.shouldRefreshData) and refreshes quietly
    // underneath if not.
    final cached = await RestaurantDiskCache.load();
    if (cached != null) RestaurantService.instance.hydrate(cached);

    // Warm the position so the list does not open on a GPS wait.
    await LocationService.instance.current();
  }

  Future<void> _start() async {
    try {
      await _prepare().timeout(_deadline);
    } catch (_) {
      // Every step here is an optimisation. The list screen resolves anything
      // that is missing and surfaces its own error if it cannot.
    }
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const RestaurantListScreen(
          key: ValueKey('restaurant_list'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Sized for a phone screen. This was a 3840x5760 PNG — 24 MB in the
          // bundle and an 88 MB RGBA decode on the raster thread, on the one
          // frame the app most needs to be cheap.
          Image.asset(
            'assets/splash.jpg',
            fit: BoxFit.cover,
          ),
          const Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: CircularProgressIndicator(),
            ),
          ),
        ],
      ),
    );
  }
}
