import 'package:flutter/material.dart';

/// The type scale: a serif for names and headlines, a geometric sans for
/// everything that is read rather than looked at.
///
/// Both faces are variable fonts, so weight is selected on the `wght` axis via
/// [TextStyle.fontVariations] rather than by shipping a file per weight.
/// [TextStyle.fontWeight] is set alongside it — the axis is what actually
/// renders, the weight is what synthetic-bolding and accessibility tooling
/// read — and the two must agree.
class AppTypography {
  const AppTypography._();

  static const String serif = 'Fraunces';
  static const String sans = 'PlusJakartaSans';

  /// Fraunces exposes an optical-size axis. Pointing it at the size the text is
  /// actually rendered at is the whole reason to pick this face: the letterforms
  /// thin out and open up for a headline, and stay sturdy for a list row.
  static TextStyle _serif(
    double size, {
    required FontWeight weight,
    double? height,
    double? letterSpacing,
    double? softness,
  }) {
    return TextStyle(
      fontFamily: serif,
      fontSize: size,
      height: height,
      letterSpacing: letterSpacing,
      fontWeight: weight,
      fontVariations: [
        FontVariation('wght', weight.value.toDouble()),
        FontVariation('opsz', size.clamp(9.0, 144.0)),
        // A touch of softness rounds the terminals — the difference between
        // "editorial" and "legal document".
        FontVariation('SOFT', softness ?? 12),
      ],
    );
  }

  static TextStyle _sans(
    double size, {
    required FontWeight weight,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: sans,
      fontSize: size,
      height: height,
      letterSpacing: letterSpacing,
      fontWeight: weight,
      fontVariations: [FontVariation('wght', weight.value.toDouble())],
    );
  }

  /// A serif style at an arbitrary size, for the few places that need one
  /// outside the scale (the wordmark, the rank numeral).
  static TextStyle serifAt(
    double size, {
    FontWeight weight = FontWeight.w600,
    double? height,
    double? letterSpacing,
    double? softness,
  }) =>
      _serif(size,
          weight: weight,
          height: height,
          letterSpacing: letterSpacing,
          softness: softness);

  /// Built as a method rather than a const so the optical-size and weight axes
  /// can be derived from each style's own size.
  static TextTheme build() {
    return TextTheme(
      displayLarge:
          _serif(48, weight: FontWeight.w600, height: 1.08, letterSpacing: -1),
      displayMedium:
          _serif(38, weight: FontWeight.w600, height: 1.10, letterSpacing: -0.8),
      displaySmall:
          _serif(30, weight: FontWeight.w600, height: 1.14, letterSpacing: -0.5),

      headlineLarge:
          _serif(28, weight: FontWeight.w600, height: 1.18, letterSpacing: -0.4),
      headlineMedium:
          _serif(24, weight: FontWeight.w600, height: 1.20, letterSpacing: -0.3),
      headlineSmall:
          _serif(20, weight: FontWeight.w600, height: 1.24, letterSpacing: -0.2),

      // Restaurant names live here — titleLarge on a card face, titleMedium on
      // a list row.
      titleLarge:
          _serif(22, weight: FontWeight.w600, height: 1.22, letterSpacing: -0.3),
      titleMedium:
          _serif(16, weight: FontWeight.w600, height: 1.28, letterSpacing: -0.1),
      titleSmall: _sans(14, weight: FontWeight.w600, height: 1.30),

      bodyLarge: _sans(16, weight: FontWeight.w400, height: 1.45),
      bodyMedium: _sans(14, weight: FontWeight.w400, height: 1.45),
      bodySmall: _sans(12, weight: FontWeight.w400, height: 1.40),

      labelLarge:
          _sans(14, weight: FontWeight.w600, height: 1.20, letterSpacing: 0.1),
      labelMedium:
          _sans(12, weight: FontWeight.w600, height: 1.20, letterSpacing: 0.2),
      labelSmall:
          _sans(11, weight: FontWeight.w600, height: 1.20, letterSpacing: 0.3),
    );
  }
}
