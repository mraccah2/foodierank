import 'dart:async';
import 'package:flutter/material.dart';
import '../services/restaurant_service.dart';
import 'restaurant_list_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initRestaurantScreen();
  }

  /// Fetches the first screen's restaurants and photos, then decodes those
  /// photos into the image cache. The decode lives here rather than in
  /// [RestaurantService] because `precacheImage` needs a BuildContext, and the
  /// service is kept Flutter-free so `bin/foodierank.dart` can share it.
  Future<void> _warmCaches() async {
    final photoRefs = await RestaurantService.instance.warmCaches();

    for (final photoRef in photoRefs) {
      if (!mounted) return;
      final photoBytes = RestaurantService.instance.getCachedPhoto(photoRef);
      if (photoBytes != null) {
        await precacheImage(MemoryImage(photoBytes), context);
      }
    }
  }

  void _initRestaurantScreen() async {
    try {
      // Attempt to load and cache restaurants and photos
      final dataFuture = _warmCaches();
      final timerFuture = Future.delayed(const Duration(seconds: 1));

      // Wait for both the data loading and minimum time
      await Future.wait([dataFuture, timerFuture]);

      if (!mounted) {
        return;
      }

      // Pre-build the restaurant list screen
      final restaurantScreen = RestaurantListScreen(
        key: const ValueKey('restaurant_list'),
      );

      // Allow some time for the screen to initialize
      await Future.microtask(() {});

      if (!mounted) {
        return;
      }

      // Navigate to pre-built RestaurantListScreen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => restaurantScreen,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      // Navigate to RestaurantListScreen with error
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const RestaurantListScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/splash.png',
            fit: BoxFit.cover,
          ),
          // Add a loading indicator
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
