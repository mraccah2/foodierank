import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodierank/theme/app_theme.dart';
import 'package:foodierank/widgets/filter_rail.dart';

/// The rail shipped once with three chips that could never look selected —
/// type, price and sort were built without a `selected` value at all, so
/// choosing a cuisine changed the label and nothing else. And the two chips
/// that are *always* applied, "Near me" and "Open now", were made to look
/// selected only once customised, which read as two switched-off filters on a
/// cold start.
///
/// Both are invisible to a test that only checks behaviour, so these assert on
/// the rendered label colour — the thing that actually tells the user a filter
/// is on.
void main() {
  late ColorScheme scheme;

  Widget wrap({
    String typeLabel = 'All types',
    bool typeIsCustom = false,
    String priceLabel = r'$-$$$$',
    bool priceIsCustom = false,
    bool sortByRank = true,
  }) {
    final theme = AppTheme.light();
    scheme = theme.colorScheme;
    return MaterialApp(
      theme: theme,
      home: Scaffold(
        body: FilterRail(
          typeLabel: typeLabel,
          typeIsCustom: typeIsCustom,
          onType: () {},
          priceLabel: priceLabel,
          priceIsCustom: priceIsCustom,
          onPrice: () {},
          sortByRank: sortByRank,
          onToggleSort: () {},
          locationLabel: 'Near me',
          locationIsCustom: false,
          onLocation: () {},
          onClearLocation: null,
          timeLabel: 'Open now',
          timeIsCustom: false,
          onTime: () {},
          onClearTime: null,
          searchActive: false,
          onToggleSearch: () {},
          taggedOnly: false,
          onToggleTagged: () {},
          mapActive: false,
          onToggleMap: () {},
          cardView: false,
          onToggleView: () {},
        ),
      ),
    );
  }

  Color? labelColour(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style?.color;

  testWidgets('"Near me" and "Open now" read as on from a cold start',
      (tester) async {
    await tester.pumpWidget(wrap());

    // Always-applied filters: defaults, not the absence of a filter.
    expect(labelColour(tester, 'Near me'), scheme.onPrimary);
    expect(labelColour(tester, 'Open now'), scheme.onPrimary);
  });

  testWidgets('a default cuisine and price do not read as on', (tester) async {
    await tester.pumpWidget(wrap());

    expect(labelColour(tester, 'All types'), scheme.onSurface);
    expect(labelColour(tester, r'$-$$$$'), scheme.onSurface);
  });

  testWidgets('choosing a cuisine makes its chip read as on', (tester) async {
    await tester.pumpWidget(wrap(typeLabel: 'Italian', typeIsCustom: true));

    expect(labelColour(tester, 'Italian'), scheme.onPrimary);
  });

  testWidgets('narrowing the price range makes its chip read as on',
      (tester) async {
    await tester.pumpWidget(wrap(priceLabel: r'$$', priceIsCustom: true));

    expect(labelColour(tester, r'$$'), scheme.onPrimary);
  });

  testWidgets('sorting by distance reads as on, sorting by rank does not',
      (tester) async {
    await tester.pumpWidget(wrap(sortByRank: true));
    expect(labelColour(tester, 'Rank'), scheme.onSurface);

    await tester.pumpWidget(wrap(sortByRank: false));
    expect(labelColour(tester, 'Distance'), scheme.onPrimary);
  });
}
