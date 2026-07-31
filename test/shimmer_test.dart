import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodierank/widgets/shimmer.dart';

/// The shimmer's whole justification is that a screenful of placeholders costs
/// one Ticker rather than one each. These check that the sharing holds and,
/// more importantly, that the ticker actually stops — a driver left running
/// with nothing on screen asks for a frame forever.
void main() {
  final driver = ShimmerDriver.instance;

  Widget wrap(Widget child, {bool reduceMotion = false}) => MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Directionality(textDirection: TextDirection.ltr, child: child),
      );

  tearDown(() {
    expect(driver.subscriberCount, 0,
        reason: 'a test left a shimmer subscribed');
  });

  testWidgets('one box starts the ticker', (tester) async {
    expect(driver.isRunning, isFalse);

    await tester.pumpWidget(wrap(const ShimmerBox(width: 40, height: 40)));
    expect(driver.isRunning, isTrue);
    expect(driver.subscriberCount, 1);

    await tester.pumpWidget(const SizedBox());
    expect(driver.isRunning, isFalse);
  });

  testWidgets('twenty boxes share a single ticker', (tester) async {
    await tester.pumpWidget(wrap(
      Column(
        children: [
          for (var i = 0; i < 20; i++)
            const ShimmerBox(width: 10, height: 10),
        ],
      ),
    ));

    expect(driver.subscriberCount, 20);
    expect(driver.isRunning, isTrue);

    await tester.pumpWidget(const SizedBox());
    expect(driver.isRunning, isFalse);
    expect(driver.subscriberCount, 0);
  });

  testWidgets('the ticker stops only once the last box goes', (tester) async {
    await tester.pumpWidget(wrap(
      Column(children: const [
        ShimmerBox(width: 10, height: 10),
        ShimmerBox(width: 10, height: 10),
      ]),
    ));
    expect(driver.subscriberCount, 2);

    await tester.pumpWidget(wrap(
      Column(children: const [ShimmerBox(width: 10, height: 10)]),
    ));
    expect(driver.subscriberCount, 1);
    expect(driver.isRunning, isTrue);

    await tester.pumpWidget(const SizedBox());
    expect(driver.isRunning, isFalse);
  });

  testWidgets('the phase advances as frames go by', (tester) async {
    await tester.pumpWidget(wrap(const ShimmerBox(width: 40, height: 40)));
    final start = driver.phase.value;

    await tester.pump(const Duration(milliseconds: 400));
    expect(driver.phase.value, isNot(start));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion asks for no frames at all', (tester) async {
    await tester.pumpWidget(
      wrap(const ShimmerBox(width: 40, height: 40), reduceMotion: true),
    );

    expect(driver.isRunning, isFalse);
    expect(driver.subscriberCount, 0);
    // Still occupies its space, just without animating.
    expect(find.byType(ShimmerBox), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
