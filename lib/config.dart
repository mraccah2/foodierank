class Config {
  static const bool useLocalProxy = false;

  static const String googleMapsApiKey = 'AIzaSyBl5mwMAHNMmDAq1now6jsnQzZAgxGm31s';

  static String get baseUrl {
    return useLocalProxy ? 'http://localhost:8080' : 'https://maps.googleapis.com/maps/api';
  }
} 