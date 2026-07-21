/// FoodieRank on the command line.
///
/// Runs the same search and ranking pipeline as the app — `RestaurantService`
/// for the sector-grid search and locality scores, `Restaurant.rankingScore`
/// for the ordering — so a result here is the result the app would show.
///
/// Usage:
///   export GOOGLE_MAPS_API_KEY=...
///   dart run bin/foodierank.dart "Chartres, France"
///   dart run bin/foodierank.dart --at 40.7484,-73.9967 --cuisine Italian
///   dart run bin/foodierank.dart "Nantes" --any-time --limit 10 --json
library;

import 'dart:convert';
import 'dart:io';

import 'package:foodierank/models/restaurant.dart';
import 'package:foodierank/services/api_usage_tracker.dart';
import 'package:foodierank/services/proxy_service.dart';
import 'package:foodierank/services/restaurant_service.dart';

const String _usage = '''
FoodieRank — find the best-ranked restaurants near a place.

Usage:
  dart run bin/foodierank.dart <location> [options]
  dart run bin/foodierank.dart --at <lat>,<lng> [options]

Options:
  --at <lat>,<lng>     Search around explicit coordinates instead of a place name.
  --cuisine <name>     One of RestaurantService.cuisineTypes (e.g. Italian, Sushi).
  --query <text>       Free-text search, used instead of --cuisine.
  --price <1-4,...>    Price levels to include, comma separated (1 = \$ … 4 = \$\$\$\$).
  --limit <n>          How many results to print (default 20).
  --any-time           Do not restrict to places open right now.
  --json               Emit JSON instead of a table.
  --csv                Emit CSV instead of a table.
  --show-cost          Print the Places API call count and estimated cost.
  -h, --help           Show this message.

The GOOGLE_MAPS_API_KEY environment variable must be set.
''';

Future<void> main(List<String> argv) async {
  final Options options;
  try {
    options = Options.parse(argv);
  } on FormatException catch (e) {
    stderr.writeln('error: ${e.message}\n');
    stderr.writeln(_usage);
    exit(64); // EX_USAGE
  }

  if (options.help) {
    stdout.write(_usage);
    return;
  }

  if ((Platform.environment['GOOGLE_MAPS_API_KEY'] ?? '').isEmpty) {
    stderr.writeln('error: GOOGLE_MAPS_API_KEY is not set.');
    exit(78); // EX_CONFIG
  }

  try {
    final ({double lat, double lng, String label}) target =
        options.coordinates ?? await _geocode(options.location!);

    if (!options.machineReadable) {
      stderr.writeln('Searching near ${target.label}…');
    }

    final raw = await RestaurantService.instance.getNearbyRestaurants(
      target.lat,
      target.lng,
      cuisineType: options.cuisine,
      searchQuery: options.query,
      priceLevels: options.priceLevels,
      openNow: options.openNow,
    );

    final restaurants = raw.map(Restaurant.fromJson).toList()
      ..sort((a, b) => b.rankingScore.compareTo(a.rankingScore));
    for (var i = 0; i < restaurants.length; i++) {
      restaurants[i].rank = i + 1;
    }

    final shown = restaurants.take(options.limit).toList();
    if (shown.isEmpty) {
      stderr.writeln('No restaurants found.');
      exit(1);
    }

    switch (options.format) {
      case OutputFormat.json:
        stdout.writeln(_asJson(shown, target));
      case OutputFormat.csv:
        _writeCsv(shown);
      case OutputFormat.table:
        _writeTable(shown);
    }

    if (options.showCost) {
      stderr.writeln('\nPlaces API: '
          '\$${ApiUsageTracker.instance.totalCost.toStringAsFixed(3)} estimated.');
    }
  } on Exception catch (e) {
    stderr.writeln('error: $e');
    exit(70); // EX_SOFTWARE
  }
}

enum OutputFormat { table, json, csv }

class Options {
  Options({
    required this.location,
    required this.coordinates,
    required this.cuisine,
    required this.query,
    required this.priceLevels,
    required this.limit,
    required this.openNow,
    required this.format,
    required this.showCost,
    required this.help,
  });

  final String? location;
  final ({double lat, double lng, String label})? coordinates;
  final String? cuisine;
  final String? query;
  final List<String>? priceLevels;
  final int limit;
  final bool openNow;
  final OutputFormat format;
  final bool showCost;
  final bool help;

  bool get machineReadable => format != OutputFormat.table;

  static Options parse(List<String> argv) {
    String? location;
    ({double lat, double lng, String label})? coordinates;
    String? cuisine;
    String? query;
    List<String>? priceLevels;
    var limit = 20;
    var openNow = true;
    var format = OutputFormat.table;
    var showCost = false;
    var help = false;

    String valueFor(int i, String flag) {
      if (i + 1 >= argv.length) {
        throw FormatException('$flag needs a value');
      }
      return argv[i + 1];
    }

    for (var i = 0; i < argv.length; i++) {
      final arg = argv[i];
      switch (arg) {
        case '-h':
        case '--help':
          help = true;
        case '--at':
          coordinates = _parseCoordinates(valueFor(i, '--at'));
          i++;
        case '--cuisine':
          cuisine = valueFor(i, '--cuisine');
          i++;
        case '--query':
          query = valueFor(i, '--query');
          i++;
        case '--price':
          priceLevels = _parsePriceLevels(valueFor(i, '--price'));
          i++;
        case '--limit':
          limit = int.tryParse(valueFor(i, '--limit')) ??
              (throw FormatException('--limit must be a number'));
          if (limit < 1) throw const FormatException('--limit must be positive');
          i++;
        case '--any-time':
          openNow = false;
        case '--json':
          format = OutputFormat.json;
        case '--csv':
          format = OutputFormat.csv;
        case '--show-cost':
          showCost = true;
        default:
          if (arg.startsWith('-')) {
            throw FormatException('unknown option "$arg"');
          }
          if (location != null) {
            throw FormatException('unexpected extra argument "$arg"');
          }
          location = arg;
      }
    }

    if (!help && location == null && coordinates == null) {
      throw const FormatException('a location or --at <lat>,<lng> is required');
    }

    return Options(
      location: location,
      coordinates: coordinates,
      cuisine: cuisine,
      query: query,
      priceLevels: priceLevels,
      limit: limit,
      openNow: openNow,
      format: format,
      showCost: showCost,
      help: help,
    );
  }
}

({double lat, double lng, String label}) _parseCoordinates(String value) {
  final parts = value.split(',');
  if (parts.length != 2) {
    throw const FormatException('--at expects <lat>,<lng>');
  }
  final lat = double.tryParse(parts[0].trim());
  final lng = double.tryParse(parts[1].trim());
  if (lat == null || lng == null) {
    throw const FormatException('--at expects two numbers, e.g. 40.7484,-73.9967');
  }
  return (lat: lat, lng: lng, label: '$lat,$lng');
}

/// Places levels are named, not numeric, in the Places API (New).
const _priceLevelNames = {
  '1': 'PRICE_LEVEL_INEXPENSIVE',
  '2': 'PRICE_LEVEL_MODERATE',
  '3': 'PRICE_LEVEL_EXPENSIVE',
  '4': 'PRICE_LEVEL_VERY_EXPENSIVE',
};

List<String> _parsePriceLevels(String value) {
  return value.split(',').map((level) {
    final name = _priceLevelNames[level.trim()];
    if (name == null) {
      throw FormatException('--price takes 1-4, got "$level"');
    }
    return name;
  }).toList();
}

/// Resolves a place name to coordinates with a single Text Search call — the
/// CLI counterpart of the app's autocomplete-then-details flow.
Future<({double lat, double lng, String label})> _geocode(String location) async {
  ApiUsageTracker.instance.incrementTextSearch();
  final response = await ProxyService.placesApiGet(
    'places:searchText',
    {'textQuery': location, 'maxResultCount': 1},
    fieldMask: 'places.location,places.formattedAddress',
  );

  final places = response['places'] as List<dynamic>?;
  if (places == null || places.isEmpty) {
    throw Exception('could not find a place called "$location"');
  }

  final place = places.first as Map<String, dynamic>;
  final coordinates = place['location'] as Map<String, dynamic>;
  return (
    lat: (coordinates['latitude'] as num).toDouble(),
    lng: (coordinates['longitude'] as num).toDouble(),
    label: (place['formattedAddress'] as String?) ?? location,
  );
}

String _asJson(
  List<Restaurant> restaurants,
  ({double lat, double lng, String label}) target,
) {
  return const JsonEncoder.withIndent('  ').convert({
    'searchedNear': {
      'label': target.label,
      'latitude': target.lat,
      'longitude': target.lng,
    },
    'restaurants': [
      for (final r in restaurants)
        {
          'rank': r.rank,
          'name': r.name,
          'rating': r.rating,
          'reviewCount': r.reviewCount,
          'priceLevel': r.priceLevel,
          'address': r.address,
          'qualityScore': r.qualityScore,
          'destinationBonus': r.destinationBonus,
          'touristPenalty': r.touristPenalty,
          'rankingScore': r.rankingScore,
          'placeId': r.placeId,
          'mapsUrl': 'https://www.google.com/maps/place/?q=place_id:${r.placeId}',
        },
    ],
  });
}

void _writeCsv(List<Restaurant> restaurants) {
  String escape(Object? value) {
    final text = '$value';
    return text.contains(RegExp('[",\n]'))
        ? '"${text.replaceAll('"', '""')}"'
        : text;
  }

  stdout.writeln('Rank,Name,Rating,Reviews,Price,Quality,'
      'DestinationBonus,TouristPenalty,Score,Address,MapsUrl');
  for (final r in restaurants) {
    stdout.writeln([
      r.rank,
      r.name,
      r.rating,
      r.reviewCount,
      r.priceLevel,
      r.qualityScore.toStringAsFixed(3),
      r.destinationBonus.toStringAsFixed(3),
      r.touristPenalty.toStringAsFixed(3),
      r.rankingScore.toStringAsFixed(3),
      r.address,
      'https://www.google.com/maps/place/?q=place_id:${r.placeId}',
    ].map(escape).join(','));
  }
}

void _writeTable(List<Restaurant> restaurants) {
  final nameWidth = restaurants
      .map((r) => r.name.length)
      .fold(4, (widest, length) => length > widest ? length : widest)
      .clamp(4, 40);

  String cell(String text) => text.length > nameWidth
      ? '${text.substring(0, nameWidth - 1)}…'
      : text.padRight(nameWidth);

  stdout.writeln('  # ${cell('NAME')}  RATING  REVIEWS  PRICE  SCORE  SIGNALS');
  for (final r in restaurants) {
    final signals = <String>[
      if (r.destinationBonus > 0.3)
        'worth the trip (+${r.destinationBonus.toStringAsFixed(2)})',
      if (r.touristPenalty > 0.25)
        'touristy (${r.touristPenalty.toStringAsFixed(2)})',
    ];

    stdout.writeln('${r.rank.toString().padLeft(3)} '
        '${cell(r.name)}  '
        '${r.rating.toStringAsFixed(1).padLeft(6)}  '
        '${r.reviewCount.toString().padLeft(7)}  '
        '${r.priceLevel.padRight(5)}  '
        '${r.rankingScore.toStringAsFixed(2).padLeft(5)}  '
        '${signals.join(', ')}');
  }
}
