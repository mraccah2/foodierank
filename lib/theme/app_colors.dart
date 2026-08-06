import 'package:flutter/material.dart';

/// The colour foundation: one seed, two schemes, and the handful of brand
/// colours that must stay literal because they carry meaning rather than
/// hierarchy.
///
/// Every other colour in the app comes from `Theme.of(context).colorScheme`.
/// There were 111 hardcoded `Colors.*` literals before this file existed, which
/// is why there was no dark mode: each one would have had to be found.
class AppColors {
  const AppColors._();

  /// Terracotta. Warm enough to sit with food photography without competing
  /// with it, and dark enough at full chroma to carry white text.
  static const Color seed = Color(0xFFB4541E);

  // --- Light -----------------------------------------------------------------

  /// The page is a definite sand, not an off-white. White cards have to read as
  /// sitting *on* it — at the near-white this started as, a card and its
  /// background were the same colour with extra steps.
  static const Color _lightSurface = Color(0xFFF3EDE3); // warm sand
  static const Color _lightSurfaceContainer = Color(0xFFEBE3D6);
  static const Color _lightSurfaceContainerHigh = Color(0xFFE3DACA);
  static const Color _lightOnSurface = Color(0xFF1C1917);
  static const Color _lightOnSurfaceVariant = Color(0xFF6B6259);
  static const Color _lightOutlineVariant = Color(0xFFDDD3C4);

  // --- Dark ------------------------------------------------------------------

  static const Color _darkSurface = Color(0xFF14110E);
  static const Color _darkSurfaceContainer = Color(0xFF1F1B17);
  static const Color _darkSurfaceContainerHigh = Color(0xFF2A251F);
  static const Color _darkOnSurface = Color(0xFFF0E9E0);
  static const Color _darkOnSurfaceVariant = Color(0xFFB0A69A);
  static const Color _darkOutlineVariant = Color(0xFF332D26);

  /// Seeded for the accent ramps, then overridden across the surface family.
  ///
  /// Material's generated neutrals are near-grey even from a warm seed; the
  /// whole point of this palette is that the paper is warm, so those are the
  /// tones worth naming by hand.
  static ColorScheme light() {
    final base = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );
    return base.copyWith(
      surface: _lightSurface,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFFAF6F0),
      surfaceContainer: _lightSurfaceContainer,
      surfaceContainerHigh: _lightSurfaceContainerHigh,
      surfaceContainerHighest: const Color(0xFFDACFBC),
      onSurface: _lightOnSurface,
      onSurfaceVariant: _lightOnSurfaceVariant,
      outlineVariant: _lightOutlineVariant,
      outline: const Color(0xFFA89C8D),

      // Named rather than generated. Left to `fromSeed`, these come out as a
      // low-chroma tint at the seed's own hue — and a pale, desaturated
      // terracotta is pink, which is how cuisine chips ended up looking like
      // bubblegum. Tertiary fared worse: a chartreuse nobody picked.
      secondary: const Color(0xFF6E5B4B),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFE8DFD0), // warm sand
      onSecondaryContainer: const Color(0xFF4A4239),
      tertiary: const Color(0xFF8A6A2E),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFF5E3C4), // amber, for cautions
      onTertiaryContainer: const Color(0xFF5A4526),
    );
  }

  static ColorScheme dark() {
    final base = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    return base.copyWith(
      surface: _darkSurface,
      surfaceContainerLowest: const Color(0xFF0E0C0A),
      surfaceContainerLow: const Color(0xFF1A1714),
      surfaceContainer: _darkSurfaceContainer,
      surfaceContainerHigh: _darkSurfaceContainerHigh,
      surfaceContainerHighest: const Color(0xFF362F28),
      onSurface: _darkOnSurface,
      onSurfaceVariant: _darkOnSurfaceVariant,
      outlineVariant: _darkOutlineVariant,
      outline: const Color(0xFF6E655B),

      // Deliberately a step lighter than `surfaceContainerHigh`, which is what
      // a Card is set to in this scheme — a chip that matched its card would be
      // invisible.
      secondary: const Color(0xFFCFC0AE),
      onSecondary: const Color(0xFF3A2E24),
      secondaryContainer: const Color(0xFF3A332B),
      onSecondaryContainer: const Color(0xFFE6DDD2),
      tertiary: const Color(0xFFD9B978),
      onTertiary: const Color(0xFF3D2E10),
      tertiaryContainer: const Color(0xFF3D3220),
      onTertiaryContainer: const Color(0xFFF0DDBB),
    );
  }

  // --- Meaning-carrying colours ----------------------------------------------
  //
  // These stay literal on purpose. A rating star that took its colour from the
  // theme would stop reading as a rating star.

  /// The Google rating star. Amber in both schemes, lifted slightly in dark so
  /// it does not go muddy against a near-black card.
  static Color ratingStar(Brightness brightness) =>
      brightness == Brightness.dark
          ? const Color(0xFFF0B657)
          : const Color(0xFFE0A02E);

  /// Fill for the numbered map pin. Uses the accent rather than the old amber
  /// so a pin and its card read as the same object.
  static const Color mapPin = seed;
  static const Color onMapPin = Colors.white;
}
