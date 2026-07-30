import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';
import '../utils/debug_log.dart';

/// The Data Portability scope for Starred places.
///
/// The only Maps saved-place scope Google publishes — there is none for
/// Favorites, Want to go, or custom lists, which is why those can only arrive
/// via a Takeout upload. Classified `restricted`, so until the OAuth client
/// clears Google's security assessment this works only for accounts on the
/// project's test-user list.
const String kStarredPlacesScope =
    'https://www.googleapis.com/auth/dataportability.maps.starred_places';

/// Optional Google sign-in.
///
/// Everything here degrades to "signed out" rather than throwing: FoodieRank
/// is fully usable without an account, and a build with no Firebase config or
/// no OAuth client ids simply never offers the option.
class AuthService extends ChangeNotifier {
  static final AuthService instance = AuthService._();

  AuthService._();

  bool _firebaseReady = false;
  bool _initialized = false;
  User? _user;

  /// True when Firebase initialised *and* the build carries OAuth client ids.
  bool get isAvailable => _firebaseReady && Config.googleSignInConfigured;

  bool get isSignedIn => _user != null;
  User? get user => _user;
  String? get uid => _user?.uid;
  String? get email => _user?.email;
  String? get displayName => _user?.displayName;
  String? get photoUrl => _user?.photoURL;

  /// True once the user has granted the Data Portability scope and the backend
  /// holds a refresh token for them.
  bool _hasStarredGrant = false;
  bool get hasStarredPlacesGrant => _hasStarredGrant;

  /// Bring up Firebase and Google Sign-In. Never throws — on failure the
  /// feature is simply unavailable.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (e) {
      // No google-services.json / GoogleService-Info.plist yet, or the project
      // is not configured. Leave the feature switched off.
      debugLog('dBug/auth: Firebase unavailable: $e');
      notifyListeners();
      return;
    }

    if (!Config.googleSignInConfigured) {
      debugLog('dBug/auth: no GOOGLE_SERVER_CLIENT_ID; sign-in disabled');
      notifyListeners();
      return;
    }

    try {
      await GoogleSignIn.instance.initialize(
        clientId: Config.googleIosClientId.isEmpty
            ? null
            : Config.googleIosClientId,
        serverClientId: Config.googleServerClientId,
      );
    } catch (e) {
      debugLog('dBug/auth: Google Sign-In init failed: $e');
      _firebaseReady = false;
      notifyListeners();
      return;
    }

    FirebaseAuth.instance.authStateChanges().listen((user) {
      _user = user;
      notifyListeners();
    });
    _user = FirebaseAuth.instance.currentUser;

    notifyListeners();
  }

  /// Interactive sign-in. Returns true when a user ends up signed in.
  ///
  /// The Data Portability grant is deliberately *not* requested here — see
  /// [connectGoogleMapsData]. Signing in should not demand a restricted scope
  /// the user may not want, and the app is useful without it.
  Future<bool> signIn() async {
    if (!isAvailable) return false;

    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        debugLog('dBug/auth: no idToken from Google');
        return false;
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      await FirebaseAuth.instance.signInWithCredential(credential);
      return true;
    } on GoogleSignInException catch (e) {
      // A cancelled sign-in is a normal outcome, not an error worth surfacing.
      if (e.code != GoogleSignInExceptionCode.canceled) {
        debugLog('dBug/auth: sign-in failed: ${e.code} ${e.description}');
      }
      return false;
    } catch (e) {
      debugLog('dBug/auth: sign-in failed: $e');
      return false;
    }
  }

  /// Ask for the Data Portability scope and hand the resulting auth code to the
  /// backend, which exchanges it for a refresh token.
  ///
  /// A refresh token — not the access token this client holds — is what the
  /// backend needs: archives can take days to build, long outliving the
  /// one-hour access token, and polling happens with no user present.
  ///
  /// Returns a human-readable error, or null on success.
  Future<String?> connectGoogleMapsData() async {
    if (!isSignedIn) return 'Sign in first.';

    try {
      final authorization = await GoogleSignIn.instance.authorizationClient
          .authorizeServer([kStarredPlacesScope]);

      if (authorization == null) {
        return 'Google did not grant access to Starred places.';
      }

      await FirebaseFunctions.instance
          .httpsCallable('linkGoogleAccount')
          .call<Map<String, dynamic>>({
        'serverAuthCode': authorization.serverAuthCode,
      });

      _hasStarredGrant = true;
      notifyListeners();
      return null;
    } on FirebaseFunctionsException catch (e) {
      debugLog('dBug/auth: link failed: ${e.code} ${e.message}');
      return e.message ?? 'Could not connect your Google Maps data.';
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      return e.description ?? 'Authorization was not granted.';
    } catch (e) {
      debugLog('dBug/auth: link failed: $e');
      return 'Could not connect your Google Maps data.';
    }
  }

  /// Revoke the backend's stored grant, leaving the user signed in.
  Future<void> disconnectGoogleMapsData() async {
    if (!isSignedIn) return;
    try {
      await FirebaseFunctions.instance.httpsCallable('unlinkGoogleAccount').call();
    } catch (e) {
      debugLog('dBug/auth: unlink failed: $e');
    }
    _hasStarredGrant = false;
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (e) {
      debugLog('dBug/auth: google signOut failed: $e');
    }
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugLog('dBug/auth: firebase signOut failed: $e');
    }
    _hasStarredGrant = false;
    notifyListeners();
  }
}
