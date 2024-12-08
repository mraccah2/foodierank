import 'dart:io' show Platform;

class Config {
  static const bool useLocalProxy = false;

  // Platform-specific API keys
  static const String _androidApiKey = 'AIzaSyBjwQIiRllZzygrwLJSluNJ__C_sRZGb8I';
  static const String _iosApiKey = 'AIzaSyBl5mwMAHNMmDAq1now6jsnQzZAgxGm31s';

  // Get the appropriate API key based on platform
  static String get googleMapsApiKey {
    if (Platform.isAndroid) {
      return _androidApiKey;
    } else if (Platform.isIOS) {
      return _iosApiKey;
    }
    throw UnsupportedError('Unsupported platform for Google Maps API');
  }

  static String get baseUrl {
    return useLocalProxy ? 'http://localhost:8080' : 'https://maps.googleapis.com/maps/api';
  }
} 