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

  void _initRestaurantScreen() async {
    try {
      // Attempt to load and cache restaurants and photos
      final dataFuture = RestaurantService.instance.loadAndCacheRestaurants();
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
