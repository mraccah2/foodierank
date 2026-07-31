import 'package:http/http.dart' as http;

/// The single HTTP client every outbound request goes through.
///
/// Requests used to be issued by throwaway clients — `http.post` builds one per
/// call and closes it, and the photo fetch constructed its own — so a cold
/// start paid a fresh TCP + TLS handshake for each of its ~50 requests to two
/// hosts. Sharing one client keeps those connections alive and reuses them,
/// which on a high-latency mobile link is worth seconds.
final http.Client appHttpClient = http.Client();

/// How long a single request may take before it is retried or abandoned.
///
/// Nothing enforced this before, so a half-open socket — a captive portal, a
/// cell/wifi handoff — hung until the OS gave up, around 75 seconds on iOS, and
/// the retry loop then did it twice more.
const Duration kRequestTimeout = Duration(seconds: 8);

/// The budget for a photo, which is larger than a JSON response and less
/// urgent — nothing is blocked waiting for one.
const Duration kPhotoTimeout = Duration(seconds: 12);
