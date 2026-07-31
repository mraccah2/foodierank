import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodierank/services/photo_source.dart';
import 'package:foodierank/widgets/place_photo.dart';
import 'package:foodierank/widgets/shimmer.dart';

/// A photo source whose requests complete only when a test says so.
///
/// The bug these tests exist for was invisible from the service side: the
/// bytes reached the cache, so every service-level assertion passed while the
/// widget sat on a placeholder forever.
class FakePhotoSource implements PhotoSource {
  final Map<String, Uint8List> cached = {};
  final Map<String, Completer<Uint8List?>> _pending = {};
  final List<({String ref, bool priority})> requests = [];

  @override
  Uint8List? getCachedPhoto(String photoRef) => cached[photoRef];

  @override
  Future<Uint8List?> loadPhoto(
    String photoRef, {
    int maxWidth = 800,
    int maxHeight = 450,
    bool priority = false,
  }) {
    requests.add((ref: photoRef, priority: priority));
    return (_pending[photoRef] ??= Completer<Uint8List?>()).future;
  }

  void complete(String photoRef, Uint8List? bytes) {
    if (bytes != null) cached[photoRef] = bytes;
    _pending[photoRef]!.complete(bytes);
  }

  void fail(String photoRef, Object error) {
    _pending[photoRef]!.completeError(error);
  }

  bool isPending(String photoRef) =>
      _pending[photoRef]?.isCompleted == false;
}

/// A real 1x1 PNG, so `Image.memory` gets something it can actually decode.
final Uint8List _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0xDA, 0x63, 0xFC, 0xCF, 0xC0, 0x50,
  0x0F, 0x00, 0x04, 0x85, 0x01, 0x80, 0x84, 0xA9, 0x8C, 0x21, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  late FakePhotoSource source;

  setUp(() => source = FakePhotoSource());

  Future<void> pumpPhoto(
    WidgetTester tester, {
    required String ref,
    bool priority = false,
    bool reduceMotion = false,
  }) {
    return tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: PlacePhoto(
            photoRef: ref,
            width: 60,
            height: 60,
            priority: priority,
            source: source,
          ),
        ),
      ),
    );
  }

  // Nothing here uses pumpAndSettle: the shimmer animates forever by design,
  // so settling would never happen.

  testWidgets('renders straight away when the bytes are already in memory',
      (tester) async {
    source.cached['a'] = _png;
    await pumpPhoto(tester, ref: 'a');

    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(ShimmerBox), findsNothing);
    // A cache hit must not queue a request at all.
    expect(source.requests, isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shimmers first, then shows the photo when it arrives',
      (tester) async {
    // The regression test for the self-awaiting future: the widget must react
    // to a load that completes *after* it mounted. Before the fix this stayed
    // on the placeholder forever and only a remount revealed the photo.
    await pumpPhoto(tester, ref: 'b');

    expect(find.byType(ShimmerBox), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    source.complete('b', _png);
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(ShimmerBox), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows the failed state when the load yields nothing',
      (tester) async {
    await pumpPhoto(tester, ref: 'c');
    source.complete('c', null);
    await tester.pump();

    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    expect(find.byType(ShimmerBox), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows the failed state when the load throws', (tester) async {
    // A bare `.then` skips its callback on an error, which left the shimmer
    // running with nothing logged.
    await pumpPhoto(tester, ref: 'd');
    source.fail('d', StateError('boom'));
    await tester.pump();

    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    expect(find.byType(ShimmerBox), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('re-resolves when a recycled row is rebound to another photo',
      (tester) async {
    await pumpPhoto(tester, ref: 'e');
    expect(source.requests.map((r) => r.ref), ['e']);

    await pumpPhoto(tester, ref: 'f');
    expect(source.requests.map((r) => r.ref), ['e', 'f']);
    expect(find.byType(Image), findsNothing);

    source.complete('f', _png);
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ignores a late arrival for the photo it used to show',
      (tester) async {
    await pumpPhoto(tester, ref: 'g');
    await pumpPhoto(tester, ref: 'h');

    // 'g' lands after the row moved on. It must not paint over 'h'.
    source.complete('g', _png);
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.byType(ShimmerBox), findsOneWidget);

    source.complete('h', _png);
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('passes priority through to the source', (tester) async {
    await pumpPhoto(tester, ref: 'i', priority: true);
    expect(source.requests.single.priority, isTrue);
    await tester.pumpWidget(const SizedBox());

    source = FakePhotoSource();
    await pumpPhoto(tester, ref: 'j');
    expect(source.requests.single.priority, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a load still in flight when the widget goes does not throw',
      (tester) async {
    await pumpPhoto(tester, ref: 'k');
    expect(source.isPending('k'), isTrue);

    await tester.pumpWidget(const SizedBox());
    // setState on a disposed State would throw here.
    source.complete('k', _png);
    await tester.pump();
  });
}
