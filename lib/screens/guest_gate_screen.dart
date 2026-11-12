import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/guest_pass.dart';
import '../services/startup.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'splash_screen.dart';

/// The guest build's front door: the last four digits of the phone number on
/// the reservation. A guest holding a pass that is still valid goes straight
/// through; once checkout day ends they land back here.
///
/// The field takes up to six digits but shows four boxes. Four digits are
/// sent after a short pause; the owner keeps typing to six, which is sent at
/// once and never shown past the fourth digit.
class GuestGateScreen extends StatefulWidget {
  const GuestGateScreen({super.key});

  @override
  State<GuestGateScreen> createState() => _GuestGateScreenState();
}

class _GuestGateScreenState extends State<GuestGateScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _checking = true;
  String? _error;
  Timer? _pause;

  /// Long enough that the owner's fifth digit lands first; short enough that
  /// a guest barely notices.
  static const Duration _guestPause = Duration(milliseconds: 1200);

  @override
  void initState() {
    super.initState();
    _resume();
  }

  @override
  void dispose() {
    _pause?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _resume() async {
    await GuestPass.load();
    if (!mounted) return;
    if (GuestPass.isValid) return _enter();
    setState(() => _checking = false);
  }

  void _enter() {
    // Location, the permission prompt and the first search start only once the
    // guest is in.
    Startup.begin();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: AppMotion.medium,
        pageBuilder: (_, __, ___) => const SplashScreen(),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  void _onChanged(String value) {
    _pause?.cancel();
    if (_error != null) setState(() => _error = null);
    setState(() {}); // repaint the boxes
    if (value.length == 6) {
      _submit();
    } else if (value.length == 4) {
      _pause = Timer(_guestPause, _submit);
    }
  }

  Future<void> _submit() async {
    _pause?.cancel();
    final code = _controller.text.trim();
    if ((code.length != 4 && code.length != 6) || _checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    final error = await GuestPass.redeem(code);
    if (!mounted) return;
    if (error == null) return _enter();
    setState(() {
      _checking = false;
      _error = error;
      _controller.clear();
    });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final expired = GuestPass.hasExpired;
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/splash.jpg', fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black, Colors.black54, Colors.transparent],
                stops: [0, 0.55, 1],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'FoodieRank',
                    textAlign: TextAlign.center,
                    style: AppTypography.serifAt(34,
                            weight: FontWeight.w600, letterSpacing: -0.8)
                        .copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    expired
                        ? 'Your stay has ended. Staying with us again? Enter '
                            'the last 4 digits of the phone number on your new '
                            'reservation.'
                        : 'The best places to eat near your stay. Enter the '
                            'last 4 digits of the phone number on your '
                            'reservation.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 15, height: 1.4),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (_checking)
                    const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      ),
                    )
                  else ...[
                    _CodeBoxes(
                      text: _controller.text,
                      onTap: () => _focus.requestFocus(),
                    ),
                    // The real input: off-screen size, captures up to six
                    // digits for the boxes above.
                    SizedBox(
                      height: 0,
                      child: Opacity(
                        opacity: 0,
                        child: TextField(
                          controller: _controller,
                          focusNode: _focus,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          showCursor: false,
                          enableInteractiveSelection: false,
                          autocorrect: false,
                          enableSuggestions: false,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration: const InputDecoration(counterText: ''),
                          onChanged: _onChanged,
                          onSubmitted: (_) => _submit(),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Color(0xFFFFB4A1), fontSize: 14),
                      ),
                    ],
                  ],
                  const SizedBox(height: AppSpacing.xxl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Four boxes showing the first four digits typed. Digits past the fourth are
/// accepted by the field but never drawn.
class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 4; i++)
            Container(
              width: 56,
              height: 64,
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: i == text.length.clamp(0, 3) && text.length < 4
                      ? Colors.white70
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Text(
                i < text.length ? text[i] : '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
