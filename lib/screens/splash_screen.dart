import 'package:flutter/material.dart';
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
    _initRestaurantScreen();
  }

  void _initRestaurantScreen() async {
    await Future.delayed(const Duration(seconds: 1));
    
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const RestaurantListScreen()),
    );
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