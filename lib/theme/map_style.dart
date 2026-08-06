/// A dark style for the Google Maps views, so the map stops being the one
/// blazing-white rectangle in an otherwise dark app.
///
/// Tuned to the app's warm neutrals rather than the stock blue-grey night mode:
/// the land is the same near-black as the page, roads are warm greys, and parks
/// and water are desaturated so the amber-red rank pins stay the brightest
/// thing on screen.
class MapStyle {
  const MapStyle._();

  static const String dark = '''
[
  {"elementType":"geometry","stylers":[{"color":"#14110e"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#b0a69a"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#14110e"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#332d26"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#9a9086"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#c9beb1"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#8f857a"}]},
  {"featureType":"poi.business","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#1e2419"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#6b7a5e"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#2a251f"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#1f1b17"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9a9086"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#332d26"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#463d33"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#2a251f"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#c9beb1"}]},
  {"featureType":"road.local","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#2a251f"}]},
  {"featureType":"transit.station","elementType":"labels.text.fill","stylers":[{"color":"#8f857a"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1418"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#4a5a63"}]}
]
''';
}
