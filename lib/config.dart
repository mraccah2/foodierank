class Config {
  static const bool useLocalProxy = false;

  static const String googleMapsApiKey = 'AIzaSyACv9RKhgt9rhe-rdVhEaxniJAEyejOE1E';

  static String get baseUrl {
    return useLocalProxy ? 'http://localhost:8080' : 'https://maps.googleapis.com/maps/api';
  }
} 