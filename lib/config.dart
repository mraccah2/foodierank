import 'dart:io' show Platform;

/// Application configuration.
///
/// All secrets and app-identity values are injected at **build time** via
/// `--dart-define` (or a `--dart-define-from-file` JSON file). Nothing
/// sensitive is committed to source control. See the "Configuration" section
/// of the README for the full list of keys and how to obtain them.
///
/// Example:
/// ```
/// flutter run \
///   --dart-define=IOS_MAPS_API_KEY=YOUR_IOS_KEY \
///   --dart-define=ANDROID_MAPS_API_KEY=YOUR_ANDROID_KEY
/// ```
class Config {
  /// When true, requests are routed through a local proxy (see [baseUrl])
  /// instead of hitting Google's endpoints directly. Useful for debugging.
  static const bool useLocalProxy = false;

  // ---------------------------------------------------------------------------
  // Google Maps / Places API keys (per platform).
  //
  // Create these in the Google Cloud console (Places API + Maps SDK enabled)
  // and — for production — restrict each key to your app's bundle id / SHA-1.
  // ---------------------------------------------------------------------------
  static const String _androidApiKey =
      String.fromEnvironment('ANDROID_MAPS_API_KEY');
  static const String _iosApiKey = String.fromEnvironment('IOS_MAPS_API_KEY');

  /// The Google Maps/Places API key for the current platform.
  ///
  /// On desktop — which in practice means the `bin/foodierank.dart` command-line
  /// entry point — there is no build-time `--dart-define`, so the key comes from
  /// the `GOOGLE_MAPS_API_KEY` environment variable instead. That key needs no
  /// app restrictions, so it should be a separate, IP- or user-restricted key
  /// rather than either mobile key.
  static String get googleMapsApiKey {
    if (Platform.isAndroid) {
      return _androidApiKey;
    } else if (Platform.isIOS) {
      return _iosApiKey;
    }

    final fromEnvironment = Platform.environment['GOOGLE_MAPS_API_KEY'] ?? '';
    if (fromEnvironment.isNotEmpty) {
      return fromEnvironment;
    }
    throw UnsupportedError(
      'No Google Maps API key: set GOOGLE_MAPS_API_KEY in the environment '
      '(or run on Android/iOS, where the key is supplied via --dart-define).',
    );
  }

  static String get baseUrl {
    return useLocalProxy
        ? 'http://localhost:8080'
        : 'https://maps.googleapis.com/maps/api';
  }

  // ---------------------------------------------------------------------------
  // App-attestation identifiers.
  //
  // These must match the application restrictions configured on your API keys
  // in the Google Cloud console. Provide them at build time so a fork can point
  // at its own app identity without editing source.
  // ---------------------------------------------------------------------------
  static const String _androidPackageName =
      String.fromEnvironment('ANDROID_PACKAGE_NAME');
  static const String _androidSha1 =
      String.fromEnvironment('ANDROID_CERT_SHA1');
  static const String _iosBundleId = String.fromEnvironment('IOS_BUNDLE_ID');

  /// Headers that identify the calling app to Google's API key restrictions.
  /// Only non-empty values are sent, so unrestricted (development) keys work
  /// with no extra configuration.
  static Map<String, String> get appAttestationHeaders {
    if (Platform.isAndroid) {
      return {
        if (_androidPackageName.isNotEmpty)
          'X-Android-Package': _androidPackageName,
        if (_androidSha1.isNotEmpty) 'X-Android-Cert': _androidSha1,
      };
    } else if (Platform.isIOS) {
      return {
        if (_iosBundleId.isNotEmpty) 'X-Ios-Bundle-Identifier': _iosBundleId,
      };
    }
    return const {};
  }
}
