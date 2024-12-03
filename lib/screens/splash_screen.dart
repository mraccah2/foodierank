import 'package:flutter/material.dart';
import 'restaurant_list_screen.dart'; // Import the RestaurantListScreen

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Navigate to RestaurantListScreen after a delay
    Future.delayed(const Duration(seconds: 3), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const RestaurantListScreen()),
      );
    });

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