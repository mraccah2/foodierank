class Config {
  static const bool useLocalProxy = false;

  static const String googleMapsApiKey = 'REDACTED_GOOGLE_API_KEY';

  static String get baseUrl {
    return useLocalProxy ? 'http://localhost:8080' : 'https://maps.googleapis.com/maps/api';
  }
} 