import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';
import '../utils/debug_log.dart';
import 'app_http.dart';
import 'proxy_service.dart';

/// The client half of the `placesSearch` / `placesPhoto` Cloud Functions.
///
/// Browse used to call places.googleapis.com from the device, which meant no
/// cache could ever be shared between two people looking at the same street,
/// and the only way to stop a runaway was to disable the API for the whole
/// project — an App Store outage rather than a pause. That is what happened on
/// 2026-08-10.
///
/// Going through the server buys a cache shared by every user, a kill switch
/// that needs no App Store release, and one place where the field mask (and so
/// the SKU tier) is decided.
class PlacesProxyClient {
  PlacesProxyClient._();
  static final PlacesProxyClient instance = PlacesProxyClient._();

  static const String _region = 'us-central1';

  Future<void>? _ready;

  /// Bring Firebase up before the first call.
  ///
  /// Browse now depends on Firebase, which it deliberately did not before —
  /// `Bootstrap` keeps `Firebase.initializeApp` off the cold-start path so the
  /// list is not held behind it. That reasoning still holds for *sign-in*; it
  /// cannot hold for a search that is now a callable. So initialisation is
  /// started here, once, and only the first search waits on it.
  ///
  /// Idempotent across both callers and the `Bootstrap` path: `initializeApp`
  /// with no name returns the existing default app rather than throwing.
  Future<void> _ensureReady() => _ready ??= () async {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        }
        // App Check is what makes these callables safe to expose.
        //
        // The direct Places calls were protected by the API key's *application*
        // restrictions — `Config.appAttestationHeaders` sends the bundle id and
        // Google refuses the key from anywhere else. A callable has no
        // equivalent, and browse works signed out, so there is no `req.auth`
        // either. Without this, moving browse server-side would trade a
        // bundle-locked key for an open endpoint that spends money on request.
        //
        // Failure is swallowed: an unregistered or misconfigured App Check must
        // leave the app working against an unenforced backend rather than
        // bricking browse. Enforcement is switched on server-side, once the
        // console registration is in place.
        try {
          await FirebaseAppCheck.instance.activate(
            // App Attest needs iOS 14+; the deployment target is 15.0, so
            // every device that can run this app can attest and the
            // DeviceCheck-fallback variant would never be reached.
            providerApple: const AppleAppAttestProvider(),
            providerAndroid: const AndroidPlayIntegrityProvider(),
          );
        } catch (e) {
          debugLog('dBug/places_proxy: App Check unavailable: $e');
        }
      }();

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: _region);

  /// Map a callable failure onto the same exception the direct path threw, so
  /// every caller's error handling — and the budget message on the list screen
  /// — keeps working unchanged.
  ///
  /// `resource-exhausted` is what the server returns when the kill switch is
  /// off, which is the budget stop; 429 is the status the rest of the app
  /// already understands as exactly that.
  Never _rethrowAsPlacesError(String endpoint, Object error) {
    if (error is FirebaseFunctionsException) {
      final status = switch (error.code) {
        'resource-exhausted' => 429,
        'unauthenticated' || 'permission-denied' => 403,
        'not-found' => 404,
        _ => 503,
      };
      throw PlacesApiException(endpoint, status);
    }
    throw PlacesApiException(endpoint, 503);
  }

  /// Text or nearby search.
  ///
  /// Returns the raw `places` list in Google's own shape, so `_mapPlace` and
  /// everything downstream of it are unchanged.
  Future<List<dynamic>> search({
    required ({double lowLat, double lowLng, double highLat, double highLng})
        rect,
    required String textQuery,
    required bool openNow,
    required bool wantHours,
    List<String>? priceLevels,
    int maxResultCount = 20,
  }) async {
    await _ensureReady();
    try {
      final result = await _functions.httpsCallable('placesSearch').call({
        'kind': 'text',
        'textQuery': textQuery,
        'rect': {
          'lowLat': rect.lowLat,
          'lowLng': rect.lowLng,
          'highLat': rect.highLat,
          'highLng': rect.highLng,
        },
        'maxResultCount': maxResultCount,
        'openNow': openNow,
        // Opening hours are a billable add-on, which is why the app only asks
        // for them on a custom-time search. The tier name carries that choice
        // to the server, where the field mask — and so the SKU — is decided.
        'fieldTier': wantHours ? 'browseHours' : 'browse',
        if (priceLevels != null && priceLevels.isNotEmpty)
          'priceLevels': priceLevels,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return (data['places'] as List<dynamic>?) ?? const [];
    } catch (e) {
      _rethrowAsPlacesError('placesSearch', e);
    }
  }

  /// Photo bytes for a place.
  ///
  /// The function answers with a URL rather than the bytes: base64 through a
  /// callable would inflate every image by a third and bill the egress twice.
  /// The download that follows is from Cloud Storage, not from Places, so a
  /// cache hit costs storage egress instead of $7 per thousand.
  Future<Uint8List?> photo({
    required String placeId,
    String? photoName,
    int index = 0,
    int maxWidthPx = 800,
    int maxHeightPx = 450,
  }) async {
    await _ensureReady();
    String url;
    try {
      final result = await _functions.httpsCallable('placesPhoto').call({
        'placeId': placeId,
        if (photoName != null) 'photoName': photoName,
        'index': index,
        'maxWidthPx': maxWidthPx,
        'maxHeightPx': maxHeightPx,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      url = (data['url'] as String?) ?? '';
      if (url.isEmpty) return null;
    } catch (e) {
      // A missing photo is not a budget stop and must not be reported as one,
      // or one place without pictures would tell the whole screen that search
      // is switched off.
      if (e is FirebaseFunctionsException && e.code == 'not-found') return null;
      _rethrowAsPlacesError('placesPhoto', e);
    }

    try {
      final response = await appHttpClient.get(Uri.parse(url));
      if (response.statusCode != 200) return null;
      return response.bodyBytes;
    } catch (e) {
      debugLog('dBug/places_proxy: photo download failed: $e');
      return null;
    }
  }
}
