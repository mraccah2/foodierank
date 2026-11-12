import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'screens/guest_gate_screen.dart';
import 'screens/restaurant_list_screen.dart';
import 'screens/splash_screen.dart';
import 'services/api_usage_tracker.dart';
import 'services/guest_pass.dart';
import 'theme/app_theme.dart';
import 'services/navigation_service.dart';
import 'services/photo_disk_cache.dart';
import 'services/restaurant_disk_cache.dart';
import 'services/restaurant_service.dart';
import 'services/startup.dart';
import 'utils/debug_log.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

    // Debug-only, and stripped from release builds. These handlers used to be
    // silent, which is how a photo request that completed with an error — and
    // so left a placeholder on screen forever — produced not one line of
    // output to go on.
    FlutterError.onError = (FlutterErrorDetails details) {
      debugLog('dBug/flutter: ${details.exception}');
    };

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    // Let successful searches and their photos survive a relaunch. Installing
    // the hooks is synchronous; the reading and writing they enable is not.
    RestaurantDiskCache.install();
    PhotoDiskCache.install();
    RestaurantService.instance.warmPhotosDuringSearch = true;

    // Restore, locate and search from here, before the first frame, rather
    // than once the splash is up. Nothing is awaited: the splash and the list
    // screen pick up whatever has landed (see Startup).
    //
    // The guest build starts it from the code screen instead, once the guest
    // is in — no location prompt behind a locked door.
    if (!Config.guestMode) Startup.begin();

    // Nothing is awaited before this line, and that is the point.
    //
    // Saved-place markers, Firebase, Google Sign-In, a location fix — including
    // the OS permission dialog — and a full Places search all used to be
    // awaited here first. Until the last of them finished, the app rendered
    // nothing: no spinner, no error, no retry, just the native launch image.
    // With a stalled request that meant minutes of apparently frozen app.
    //
    // SplashScreen now owns that work, bounded and with something on screen.
    runApp(const MyApp());
  }, (error, stack) {
    debugLog('dBug/zone: uncaught $error\n$stack');
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // A guest whose stay ended while the app sat in the background goes back
    // to the code screen.
    if (state == AppLifecycleState.resumed &&
        Config.guestMode &&
        GuestPass.hasExpired) {
      NavigationService.navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const GuestGateScreen()),
        (_) => false,
      );
    }
    if (state == AppLifecycleState.paused) {
      // App is going to background, print stats
      ApiUsageTracker.instance.printUsageStats();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: NavigationService.navigatorKey,
      title: 'FoodieRank',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routes: {
        '/': (context) => Config.guestMode
            ? const GuestGateScreen()
            : const SplashScreen(),
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
