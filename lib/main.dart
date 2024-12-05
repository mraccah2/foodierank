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
      // Removed debug prints
    };

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    // Start location and restaurant fetch before showing splash screen
    try {
      // Removed debug print
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 10),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () async {
          // Removed debug print
          final lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null) return lastKnown;
          throw TimeoutException('Could not get location');
        },
      );

      // Removed debug prints
      await RestaurantService.instance.fetchInitialRestaurants(
        position.latitude,
        position.longitude,
      );
      // Removed debug print

    } catch (e) {
      // Removed debug print
    }

    runApp(const MyApp());
  }, (error, stack) {
    // Removed debug prints
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
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Removed debug print
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Removed debug print
        return null;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      // Removed debug print
      return null;
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
      timeLimit: const Duration(seconds: 5),
    ).timeout(
      const Duration(seconds: 5),
      onTimeout: () async {
        // Removed debug print
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) return lastKnown;
        throw TimeoutException('Could not get location');
      },
    );
  } catch (e) {
    // Removed debug print
    return null;
  }
}
