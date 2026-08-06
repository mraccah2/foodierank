import 'package:flutter/widgets.dart';

/// A 4pt spacing scale and a radius scale, replacing the magic numbers the
/// layouts were built from — `5.0`, `3`, `18`, `30` and a dozen bare `8`s that
/// meant different things in different places.
class AppSpacing {
  const AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Horizontal inset for anything that should line up with the screen's
  /// content column: list rows, headers, sheet bodies.
  static const double gutter = lg;

  /// Minimum comfortable hit target. The header pills were 32.
  static const double minTouch = 44;

  static const EdgeInsets pageHorizontal =
      EdgeInsets.symmetric(horizontal: gutter);
}

class AppRadius {
  const AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  /// Large enough to always render as a stadium at control heights.
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}
