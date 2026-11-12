import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_log.dart';

/// The guest build's access pass: unlocked by the last four digits of the
/// phone number on a current reservation, valid until the end of checkout day.
/// Six digits are the App Review code, which works like a guest's, or the
/// owner code, which also unlocks Google sign-in. Every code is checked on the
/// server; none is in the app.
///
/// Nothing identifies the guest. The server answers a code with an expiry and
/// a role and nothing else, and only those two are kept on the device.
class GuestPass {
  GuestPass._();

  static const String _prefsKey = 'guest_pass_expires_at';
  static const String _roleKey = 'guest_pass_role';

  static DateTime? _expiresAt;
  static String? _role;
  static bool _loaded = false;

  /// When the current pass runs out, or null when there is none.
  static DateTime? get expiresAt => _expiresAt;

  /// True while a pass is held and has not run out.
  static bool get isValid {
    final e = _expiresAt;
    return e != null && DateTime.now().isBefore(e);
  }

  /// True for the owner's pass, which brings back Google sign-in and the
  /// saved-places screen.
  static bool get isOwner => isValid && _role == 'owner';

  /// True when a pass was held but has since run out — the stay is over.
  static bool get hasExpired => _expiresAt != null && !isValid;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_prefsKey);
      _expiresAt = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
      _role = prefs.getString(_roleKey);
    } catch (e) {
      debugLog('dBug/guest: could not read pass: $e');
    }
    _loaded = true;
  }

  /// Check [code] with the server. Returns null on success, else a message
  /// fit to show the guest.
  static Future<String?> redeem(String code) async {
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final result = await FirebaseFunctions.instance
          .httpsCallable('verifyGuestCode')
          .call<Map<String, dynamic>>({'code': code});
      final ms = (result.data['expiresAt'] as num?)?.toInt();
      if (ms == null) return 'Something went wrong. Please try again.';
      _expiresAt = DateTime.fromMillisecondsSinceEpoch(ms);
      _role = result.data['role'] as String?;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKey, ms);
      await prefs.setString(_roleKey, _role ?? 'guest');
      return null;
    } on FirebaseFunctionsException catch (e) {
      debugLog('dBug/guest: ${e.code} ${e.message}');
      switch (e.code) {
        case 'not-found':
          return "We couldn't find a current stay for that number. Use the "
              'last 4 digits of the phone number on your reservation.';
        case 'resource-exhausted':
          return 'Too many tries. Please wait an hour and try again.';
        case 'invalid-argument':
          return 'Enter the 4 digits.';
        default:
          return "We couldn't check your reservation just now. Please try "
              'again.';
      }
    } catch (e) {
      debugLog('dBug/guest: redeem failed: $e');
      return "We couldn't reach the server. Check your connection and try "
          'again.';
    }
  }
}
