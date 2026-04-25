import 'dart:io' show Platform;

class Config {
  static const bool useLocalProxy = false;

  // Platform-specific API keys
  static const String _androidApiKey = 'REDACTED_GOOGLE_API_KEY';
  static const String _iosApiKey = 'REDACTED_GOOGLE_API_KEY';

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

  static const String _androidPackageName = 'com.foodierank.foodierank';
  static const String _androidSha1 = '6F36B6864C200D65C27D924F60AD4BDDB2BC1FBE';
  static const String _iosBundleId = 'com.foodierank.foodierank';

  static Map<String, String> get appAttestationHeaders {
    if (Platform.isAndroid) {
      return {
        'X-Android-Package': _androidPackageName,
        'X-Android-Cert': _androidSha1,
      };
    } else if (Platform.isIOS) {
      return {
        'X-Ios-Bundle-Identifier': _iosBundleId,
      };
    }
    return const {};
  }
}
