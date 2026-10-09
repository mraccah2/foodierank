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

  // Wide enough that every chip is laid out at once; the chips scroll between
  // the pinned controls, so on a narrow surface the later ones are not built.
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1600, 600);
    view.devicePixelRatio = 1;
  });
  tearDown(() => TestWidgetsFlutterBinding
      .instance.platformDispatcher.views.first
      .reset());

  Widget wrap({
    String typeLabel = 'All types',
    bool typeIsCustom = false,
    String priceLabel = r'$-$$$$',
    bool priceIsCustom = false,
    bool sortByRank = true,
    ViewMode view = ViewMode.list,
    ValueChanged<ViewMode>? onSelectView,
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
          view: view,
          onSelectView: onSelectView ?? (_) {},
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

  testWidgets('search and the view switcher stay put while the chips scroll',
      (tester) async {
    tester.view.physicalSize = const Size(375, 800);
    await tester.pumpWidget(wrap());

    final search = tester.getTopLeft(find.byIcon(Icons.search_rounded));
    final cards = tester.getTopLeft(find.byTooltip('Cards view'));

    await tester.drag(find.text('Near me'), const Offset(-120, 0));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.byIcon(Icons.search_rounded)), search);
    expect(tester.getTopLeft(find.byTooltip('Cards view')), cards);
    final chips = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(chips.position.pixels, greaterThan(0));
  });

  testWidgets('the view switcher fills the current view and selects others',
      (tester) async {
    ViewMode? picked;
    await tester
        .pumpWidget(wrap(view: ViewMode.card, onSelectView: (v) => picked = v));

    Color? iconColour(IconData icon) =>
        tester.widget<Icon>(find.byIcon(icon)).color;
    expect(iconColour(Icons.crop_portrait_rounded), scheme.onPrimary);
    expect(iconColour(Icons.view_list_rounded), scheme.onSurfaceVariant);

    await tester.tap(find.byTooltip('Map view'));
    expect(picked, ViewMode.map);
  });
}
