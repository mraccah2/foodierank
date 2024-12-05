import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'services/restaurant_service.dart';
import 'dart:async';
import 'services/navigation_service.dart';
import 'screens/restaurant_list_screen.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    FlutterError.onError = (FlutterErrorDetails details) {
      print('dBug/main: Flutter error: ${details.exception}');
      print('dBug/main: Stack trace: ${details.stack}');
    };

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    // Start location and restaurant fetch before showing splash screen
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      // Try to get location with lower accuracy first
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,  // Changed from best to low
        timeLimit: const Duration(seconds: 10),  // Increased from 5 to 10 seconds
      ).timeout(
        const Duration(seconds: 10),  // Increased timeout
        onTimeout: () async {
          print('dBug/main: Location timeout, trying last known position');
          final lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null) return lastKnown;
          
          // If no last known position, use a default location
          return Position(
            latitude: 0,
            longitude: 0,
            timestamp: DateTime.now(),
            accuracy: 0,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          );
        },
      );

      // Start fetching restaurants
      await RestaurantService.instance.fetchInitialRestaurants(
        position.latitude,
        position.longitude,
      );
    } catch (e) {
      print('dBug/main: Error in initial fetch: $e');
      // Handle error gracefully
    }

    runApp(const MyApp());
  }, (error, stack) {
    print('dBug/main: Uncaught error: $error');
    print('dBug/main: Stack trace: $stack');
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: NavigationService.navigatorKey,
      title: 'FoodieRank',
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
        ),
        colorScheme: const ColorScheme.light(
          primary: Colors.black,
          secondary: Colors.black,
          surface: Colors.white,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.black,
        ),
        useMaterial3: true,
      ),
      routes: {
        '/': (context) => const SplashScreen(),
        '/restaurant_list': (context) => const RestaurantListScreen(),
      },
      builder: (context, widget) {
        Widget error = const Text('...rendering error...');
        if (widget is Scaffold || widget is Navigator) {
          error = Scaffold(body: Center(child: error));
        }
        ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
          return error;
        };
        return widget ?? error;
      },
    );
  }
}

Future<Position?> _getLocation() async {
  try {
    // First check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('dBug/location: Location services are disabled');
      return null;
    }

    // Check permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('dBug/location: Location permissions are denied');
        return null;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      print('dBug/location: Location permissions are permanently denied');
      return null;
    }

    // Get position with timeout
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,  // Lower accuracy, faster response
      timeLimit: const Duration(seconds: 5),
    ).timeout(
      const Duration(seconds: 5),
      onTimeout: () async {
        print('dBug/location: Getting current position timed out, trying last known position');
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) return lastKnown;
        throw TimeoutException('Could not get location');
      },
    );
  } catch (e) {
    print('dBug/location: Error getting location: $e');
    return null;
  }
}
