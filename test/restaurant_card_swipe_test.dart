import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodierank/models/restaurant.dart';
import 'package:foodierank/theme/app_theme.dart';
import 'package:foodierank/widgets/restaurant_card.dart';

/// Swiping a full-page card sideways returns to the list.
///
/// The gesture deliberately lives on the card *body* rather than the whole
/// card, because the photo header is a horizontal pager in its own right — a
/// back-swipe mounted over the top of it would eat the drag you use to look
/// through a restaurant's pictures.
///
/// Built with no `photoRefs` so no photo is requested: this is about the
/// gesture, and PlacePhoto would otherwise reach for the network.
void main() {
  Restaurant restaurant() => Restaurant(
        id: 'r1',
        name: 'Bar Primi',
        mainPhotoUrl: '',
        reviewCount: 1204,
        rating: 4.6,
        priceLevel: r'$$',
        placeId: 'place-1',
        location: const Location(
          latitude: 40.0,
          longitude: -73.0,
          formattedAddress: '325 Bowery, New York',
          country: 'US',
        ),
      );

  Future<int> swipe(WidgetTester tester, Offset offset) async {
    var backs = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: RestaurantCard(
          restaurant: restaurant(),
          onPhotoTap: (_) {},
          ranking: 1,
          currentLat: 40.0,
          currentLng: -73.0,
          onSwipeBack: () => backs++,
        ),
      ),
    ));

    await tester.drag(find.text('Bar Primi'), offset);
    await tester.pumpAndSettle();
    return backs;
  }

  testWidgets('swiping right on the card body goes back', (tester) async {
    expect(await swipe(tester, const Offset(160, 0)), 1);
  });

  testWidgets('swiping left goes back too — the card is a detour off the '
      'list, so there is no "forward"', (tester) async {
    expect(await swipe(tester, const Offset(-160, 0)), 1);
  });

  testWidgets('a small horizontal twitch does not go back', (tester) async {
    expect(await swipe(tester, const Offset(12, 0)), 0);
  });

  testWidgets('scrolling the card vertically does not go back', (tester) async {
    expect(await swipe(tester, const Offset(0, -200)), 0);
  });
}
