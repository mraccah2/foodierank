import 'dart:async';
import 'package:flutter/material.dart';
import '../services/restaurant_service.dart';
import 'restaurant_list_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    print('dBug/splash_screen: initState called');
    _initRestaurantScreen();
  }

  void _initRestaurantScreen() async {
    print('dBug/splash_screen: Starting _initRestaurantScreen');
    try {
      print('dBug/splash_screen: Attempting to load and cache restaurants and photos');
      
      // Create a minimum display duration of 1 second
      final dataFuture = RestaurantService.instance.loadAndCacheRestaurants();
      final timerFuture = Future.delayed(const Duration(seconds: 1));
      
      // Wait for both the data loading and minimum time
      await Future.wait([dataFuture, timerFuture]);
      
      print('dBug/splash_screen: Restaurant data and photos loaded successfully');
      if (!mounted) {
        print('dBug/splash_screen: Widget no longer mounted after data load');
        return;
      }

      // Pre-build the restaurant list screen
      print('dBug/splash_screen: Pre-building RestaurantListScreen');
      final restaurantScreen = RestaurantListScreen(
        key: const ValueKey('restaurant_list'),
      );
      
      // Allow some time for the screen to initialize
      await Future.microtask(() {});

      print('dBug/splash_screen: Navigating to pre-built RestaurantListScreen');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => restaurantScreen,
        ),
      );
    } catch (e) {
      print('dBug/splash_screen: Error loading restaurants or photos - $e');
      if (!mounted) {
        print('dBug/splash_screen: Widget no longer mounted after error');
        return;
      }

      print('dBug/splash_screen: Navigating to RestaurantListScreen with error');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const RestaurantListScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    print('dBug/splash_screen: Building splash screen');
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