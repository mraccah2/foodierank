/// Debug-only logging that works in the Flutter app *and* in the `bin/`
/// command-line entry points.
///
/// `debugPrint` lives in `package:flutter/foundation.dart`, which transitively
/// needs `dart:ui` — so anything importing it cannot be loaded by a plain
/// `dart run`. Wrapping the print in an `assert` is the pure-Dart equivalent:
/// the closure is evaluated in debug builds and stripped entirely from release
/// builds, so this costs nothing in production.
void debugLog(String message) {
  assert(() {
    // ignore: avoid_print
    print(message);
    return true;
  }());
}
