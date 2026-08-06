import 'package:flutter/material.dart';

/// Durations, curves, and the two transitions the app uses.
///
/// Hand-rolled rather than pulled from `package:animations` — these are two
/// specific effects, and a dependency for them would be more code to keep than
/// the code it replaces.
class AppMotion {
  const AppMotion._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);

  /// Material's standard easing: quick to leave, gentle to arrive.
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
  static const Curve standard = Curves.easeOutCubic;

  /// True when the platform asks for reduced motion. Every animation here is
  /// decoration, so all of them collapse to an instant swap when it is on.
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
}

/// Fades one view out and the next one in, for views that are peers with no
/// spatial relationship — the list, the card pager and the map.
///
/// Deliberately *not* an `AnimatedSwitcher`. A switcher keeps the outgoing
/// subtree mounted for the length of the transition, so toggling from the card
/// pager to the list and back inside that window would briefly mount two
/// `PageView`s against the screen's single `PageController` — which throws
/// ("ScrollController attached to multiple scroll views"). Sequencing the fade
/// keeps exactly one subtree alive at every instant.
///
/// [child] must carry a key identifying the view; a change of key is what
/// triggers the swap.
class FadeThrough extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const FadeThrough({
    super.key,
    required this.child,
    this.duration = AppMotion.fast,
  });

  @override
  State<FadeThrough> createState() => _FadeThroughState();
}

class _FadeThroughState extends State<FadeThrough>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );

  late Widget _shown = widget.child;

  /// True between starting the fade-out and having swapped in the replacement.
  bool _swapping = false;

  @override
  void didUpdateWidget(FadeThrough oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.child.key != _shown.key) {
      if (!_swapping) _beginSwap();
      return;
    }

    // Same view, new content (a re-filtered list, say) — take it immediately.
    if (!_swapping) _shown = widget.child;
  }

  Future<void> _beginSwap() async {
    _swapping = true;
    await _controller.reverse();
    if (!mounted) return;
    // Read `widget.child` now rather than capturing it: the mode may have
    // changed again while this was fading out, and the latest is what should
    // land.
    setState(() {
      _shown = widget.child;
      _swapping = false;
    });
    await _controller.forward();
    if (!mounted) return;
    // A change that arrived during the fade back in.
    if (widget.child.key != _shown.key) _beginSwap();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return widget.child;

    return FadeTransition(
      opacity: _controller.drive(CurveTween(curve: AppMotion.standard)),
      child: _shown,
    );
  }
}

/// Cross-fade between two sizes as well as two children — used by the header
/// when the search field expands in place of the filter rail.
class ExpandFade extends StatelessWidget {
  final Widget child;
  final Duration duration;

  const ExpandFade({
    super.key,
    required this.child,
    this.duration = AppMotion.fast,
  });

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return child;

    return AnimatedSize(
      duration: duration,
      curve: AppMotion.standard,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: AppMotion.standard,
        switchOutCurve: AppMotion.standard,
        child: child,
      ),
    );
  }
}

/// Slides and fades a route in along the horizontal axis. Applied app-wide so
/// pushing the account screen, the photo viewer or the map picker reads as
/// movement rather than a cut.
class SharedAxisPageTransitionsBuilder extends PageTransitionsBuilder {
  const SharedAxisPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (context != null && AppMotion.reduced(context)) return child;

    const begin = Offset(0.06, 0);
    final position = Tween<Offset>(begin: begin, end: Offset.zero).animate(
      CurvedAnimation(parent: animation, curve: AppMotion.emphasized),
    );
    final outgoing = Tween<Offset>(begin: Offset.zero, end: const Offset(-0.04, 0))
        .animate(
      CurvedAnimation(parent: secondaryAnimation, curve: AppMotion.emphasized),
    );

    return SlideTransition(
      position: outgoing,
      child: SlideTransition(
        position: position,
        child: FadeTransition(opacity: animation, child: child),
      ),
    );
  }
}
