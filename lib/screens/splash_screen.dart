import 'package:flutter/material.dart';
import 'restaurant_list_screen.dart';
import '../services/restaurant_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _dataLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _navigateToNextScreen();
  }

  Future<void> _loadData() async {
    // Start loading restaurants and caching photos
    await RestaurantService.instance.loadAndCacheRestaurants();
    setState(() {
      _dataLoaded = true;
    });
  }

  void _navigateToNextScreen() async {
    await Future.delayed(const Duration(seconds: 2));
    if (_dataLoaded) {
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
        ],
      ),
    );
  }
} 