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

  /// The Google Maps API key for the current platform.
  ///
  /// No longer used for Places — that goes through the gateway, see
  /// [placesGatewayKey]. What remains is the legacy reverse-geocode call in
  /// `PlaceLookupService`; the map tiles read the same key natively.
  ///
  /// On desktop there is no build-time `--dart-define`, so the key comes from
  /// the `GOOGLE_MAPS_API_KEY` environment variable instead.
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

  // ---------------------------------------------------------------------------
  // Places gateway.
  //
  // Every Places call — Text/Nearby Search, Autocomplete, Place Details and
  // photos — goes through our shared Places gateway rather than to Google.
  // The gateway buys each place and photo from Google once, ever, and caches
  // searches on the canonical request, so a street one user has browsed costs
  // the next user nothing. The Maps keys above stay for map tiles and the
  // legacy reverse-geocode call, neither of which the gateway serves.
  //
  // The key identifies FoodieRank to the gateway. It is injected the same way
  // as the Maps keys: `--dart-define=PLACES_GATEWAY_KEY=...` on mobile, the
  // `PLACES_GATEWAY_KEY` environment variable for `bin/foodierank.dart`.
  // ---------------------------------------------------------------------------
  static const String placesGatewayUrl = String.fromEnvironment(
    'PLACES_GATEWAY_URL',
    defaultValue:
        'https://cndaivlyzonqndnvzilr.supabase.co/functions/v1/places',
  );

  static const String _placesGatewayKey =
      String.fromEnvironment('PLACES_GATEWAY_KEY');

  /// The gateway key: the build-time define when there is one, else the
  /// `PLACES_GATEWAY_KEY` environment variable (the CLI's path). Empty when
  /// neither is set — the gateway then answers 401, which surfaces as "search
  /// unavailable" rather than a crash.
  static String get placesGatewayKey {
    if (_placesGatewayKey.isNotEmpty) return _placesGatewayKey;
    if (Platform.isAndroid || Platform.isIOS) return '';
    return Platform.environment['PLACES_GATEWAY_KEY'] ?? '';
  }

  // ---------------------------------------------------------------------------
  // Google Sign-In (optional feature).
  //
  // Signing in is never required: the app works fully signed out, and these
  // being empty simply keeps the saved-places feature switched off.
  //
  // [googleServerClientId] must be the **Web** OAuth client id, even on mobile.
  // It is what makes `authorizeServer` return a `serverAuthCode`, which the
  // backend exchanges for the long-lived refresh token it needs to poll
  // multi-day Data Portability archives.
  // ---------------------------------------------------------------------------
  static const String googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// iOS OAuth client id. Android resolves its client from the signing SHA-1
  /// registered in the Firebase console, so it needs no equivalent here.
  static const String googleIosClientId =
      String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// True when the build carries enough configuration to offer Google sign-in.
  static bool get googleSignInConfigured => googleServerClientId.isNotEmpty;

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
