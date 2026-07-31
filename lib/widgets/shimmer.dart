import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Drives every shimmer on screen from a single [Ticker].
///
/// A placeholder per list row is normal; an animation controller per row is
/// not — twenty independent tickers is exactly why the spinner placeholders
/// these replaced were worth removing. Each [ShimmerBox] listens to the one
/// [phase] notifier here, and the ticker only runs while at least one of them
/// is mounted.
class ShimmerDriver {
  ShimmerDriver._();

  static final ShimmerDriver instance = ShimmerDriver._();

  /// One full sweep of the highlight across a placeholder.
  static const Duration period = Duration(milliseconds: 1400);

  /// 0..1, where the highlight currently sits.
  final ValueNotifier<double> phase = ValueNotifier<double>(0);

  Ticker? _ticker;
  int _subscribers = 0;

  void acquire() {
    _subscribers++;
    _ticker ??= Ticker(_tick)..start();
  }

  void release() {
    _subscribers--;
    if (_subscribers <= 0) {
      _subscribers = 0;
      // Nothing is shimmering, so stop asking for frames entirely.
      _ticker?.dispose();
      _ticker = null;
    }
  }

  void _tick(Duration elapsed) {
    final ms = period.inMilliseconds;
    phase.value = (elapsed.inMilliseconds % ms) / ms;
  }
}

/// A shimmering block, used while a photo is still being fetched.
///
/// Falls back to a flat fill when the platform asks for reduced motion.
class ShimmerBox extends StatefulWidget {
  final double? width;
  final double height;
  final Widget? child;

  const ShimmerBox({
    super.key,
    required this.height,
    this.width,
    this.child,
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox> {
  static const Color _base = Color(0xFFE0E0E0); // grey 300
  static const Color _highlight = Color(0xFFF5F5F5); // grey 100

  bool _subscribed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read here rather than in initState: MediaQuery is not available yet in
    // initState, and the setting can change while the widget is alive.
    _setSubscribed(!MediaQuery.disableAnimationsOf(context));
  }

  void _setSubscribed(bool wanted) {
    if (wanted == _subscribed) return;
    _subscribed = wanted;
    if (wanted) {
      ShimmerDriver.instance.acquire();
    } else {
      ShimmerDriver.instance.release();
    }
  }

  @override
  void dispose() {
    _setSubscribed(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_subscribed) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: _base,
        child: widget.child,
      );
    }

    return ValueListenableBuilder<double>(
      valueListenable: ShimmerDriver.instance.phase,
      builder: (context, t, child) {
        // Travel from fully off one edge to fully off the other, so the
        // highlight enters and leaves rather than popping at the boundary.
        final x = -1.5 + 3.5 * t;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(x - 0.7, -0.3),
              end: Alignment(x + 0.7, 0.3),
              colors: const [_base, _highlight, _base],
            ),
          ),
          child: child,
        );
      },
      // Built once and handed to every frame — only the gradient changes.
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: widget.child,
      ),
    );
  }
}
