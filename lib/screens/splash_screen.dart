import 'dart:async';

import 'package:flutter/material.dart';

import '../services/bootstrap.dart';
import '../services/startup.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'restaurant_list_screen.dart';

/// The first screen: a brief, bounded warm-up before the list takes over.
///
/// It starts the saved-places feature and holds until `Startup` — begun in
/// `main`, before this screen existed — has content for the list: the last
/// session's results, or the launch search's first places and their photos.
/// Opening the list any earlier only swapped one waiting screen for another, a
/// skeleton. None of it is strictly needed by the list screen, which resolves
/// whatever is missing itself and has its own error and retry, so this screen
/// still never blocks past [_deadline]: on a slow network the list's own
/// progress is the better thing to be looking at.
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

    // Content for the list — restored results, or the launch search's first
    // places with their photos — all begun in `main`, so this only waits on
    // what is still outstanding.
    await Startup.ready;
  }

  Future<void> _start() async {
    try {
      await _prepare().timeout(_deadline);
    } catch (_) {
      // Every step here is an optimisation. The list screen resolves anything
      // that is missing and surfaces its own error if it cannot.
    }
    if (!mounted) return;

    // A fade rather than a push: the list is not somewhere you navigated to
    // from the splash, it is what the splash was standing in for.
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: AppMotion.slow,
        pageBuilder: (_, __, ___) => const RestaurantListScreen(
          key: ValueKey('restaurant_list'),
        ),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
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
          // The wordmark and spinner sit on a photograph, so they are white in
          // both schemes — and the scrim is what guarantees they are legible
          // whatever the photograph is doing underneath them.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
          ),
          Positioned(
            bottom: 64,
            left: AppSpacing.xxl,
            right: AppSpacing.xxl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'FoodieRank',
                  style: AppTypography.serifAt(
                    34,
                    weight: FontWeight.w600,
                    letterSpacing: -0.8,
                  ).copyWith(color: Colors.white),
                ),
                const SizedBox(height: AppSpacing.xl),
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
