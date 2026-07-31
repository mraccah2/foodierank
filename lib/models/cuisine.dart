/// Working out what a place serves, from its Google Places `types` and — when
/// those say nothing useful — from the country it sits in.
///
/// Both card layouts used to carry their own copy of this: a seventy-entry
/// keyword set and a fifty-entry country map, allocated fresh inside `build`,
/// and on the detail card walked twice per frame — once to test for null, again
/// to render. The two copies had also drifted, since only one of them ever got
/// the full country map. It lives here now and is resolved once per restaurant
/// at parse time.
///
/// Pure Dart, so `bin/foodierank.dart` can share it.
library;

class Cuisine {
  const Cuisine._();

  /// Cuisine keywords as they appear in Google Places types.
  static const Set<String> keywords = {
    'afghani',
    'african',
    'american',
    'arabic',
    'argentinian',
    'asian',
    'australian',
    'austrian',
    'bbq',
    'barbeque',
    'belgian',
    'brazilian',
    'british',
    'caribbean',
    'chinese',
    'colombian',
    'croatian',
    'cuban',
    'czech',
    'danish',
    'ethiopian',
    'filipino',
    'finnish',
    'french',
    'georgian',
    'german',
    'greek',
    'hungarian',
    'indian',
    'indonesian',
    'irish',
    'israeli',
    'italian',
    'jamaican',
    'japanese',
    'korean',
    'latin',
    'lebanese',
    'malaysian',
    'malay',
    'mediterranean',
    'mexican',
    'middle_eastern',
    'moroccan',
    'nepalese',
    'nigerian',
    'norwegian',
    'pakistani',
    'peruvian',
    'persian',
    'pizza',
    'polish',
    'portuguese',
    'romanian',
    'russian',
    'scandinavian',
    'scottish',
    'seafood',
    'singaporean',
    'south_african',
    'sushi',
    'spanish',
    'swedish',
    'swiss',
    'taiwanese',
    'thai',
    'turkish',
    'ukrainian',
    'uruguayan',
    'vegetarian',
    'venezuelan',
    'vietnamese',
    'welsh',
  };

  /// The cuisine to assume from a country when the types give nothing away.
  static const Map<String, String> byCountry = {
    'Afghanistan': 'afghan',
    'Argentina': 'argentinian',
    'Australia': 'australian',
    'Austria': 'austrian',
    'Belgium': 'belgian',
    'Brazil': 'brazilian',
    'China': 'chinese',
    'Colombia': 'colombian',
    'Croatia': 'croatian',
    'Cuba': 'cuban',
    'Czech Republic': 'czech',
    'Denmark': 'danish',
    'Ethiopia': 'ethiopian',
    'Philippines': 'filipino',
    'Finland': 'finnish',
    'France': 'french',
    'Georgia': 'georgian',
    'Germany': 'german',
    'Greece': 'greek',
    'Hungary': 'hungarian',
    'India': 'indian',
    'Indonesia': 'indonesian',
    'Ireland': 'irish',
    'Israel': 'israeli',
    'Italy': 'italian',
    'Jamaica': 'jamaican',
    'Japan': 'japanese',
    'Korea': 'korean',
    'Lebanon': 'lebanese',
    'Malaysia': 'malaysian',
    'Mexico': 'mexican',
    'Morocco': 'moroccan',
    'Nepal': 'nepalese',
    'Nigeria': 'nigerian',
    'Norway': 'norwegian',
    'Pakistan': 'pakistani',
    'Peru': 'peruvian',
    'Iran': 'persian',
    'Poland': 'polish',
    'Portugal': 'portuguese',
    'Romania': 'romanian',
    'Russia': 'russian',
    'Singapore': 'singaporean',
    'South Africa': 'south_african',
    'Spain': 'spanish',
    'Sweden': 'swedish',
    'Switzerland': 'swiss',
    'Taiwan': 'taiwanese',
    'Thailand': 'thai',
    'Turkey': 'turkish',
    'Ukraine': 'ukrainian',
    'Uruguay': 'uruguayan',
    'Venezuela': 'venezuelan',
    'Vietnam': 'vietnamese',
    'Wales': 'welsh',
  };

  /// The primary cuisine for [types]; failing that a guess from [country],
  /// suffixed with `?` to mark it as inferred from the address rather than
  /// from the place itself. Null when neither says anything.
  static String? resolve(List<String> types, {String? country}) {
    // First pass: compound types such as `vegetarian_restaurant`.
    for (final type in types) {
      final base = type.toLowerCase().split('_').first;
      if (keywords.contains(base)) return base;
    }

    // Second pass: an exact match, which is what catches the underscored
    // keywords the first pass splits apart.
    for (final type in types) {
      final normalised = type.toLowerCase();
      if (keywords.contains(normalised)) return normalised;
    }

    if (country != null) {
      final guess = byCountry[country];
      if (guess != null) return '$guess?';
    }
    return null;
  }

  /// `middle_eastern` → `Middle Eastern`.
  static String format(String cuisine) => cuisine
      .split('_')
      .map((word) => word.isEmpty
          ? word
          : word[0].toUpperCase() + word.substring(1).toLowerCase())
      .join(' ');

  /// [resolve] and [format] in one step — what the cards actually want.
  static String? label(List<String> types, {String? country}) {
    final cuisine = resolve(types, country: country);
    return cuisine == null ? null : format(cuisine);
  }
}
