/**
 * Whether a resolved place is somewhere you can actually eat, and still open.
 *
 * Google's saved lists hold more than venues — a "Want to go" list picks up
 * streets ("Rue de Bretagne"), neighbourhoods and other map pins alongside
 * restaurants. Those resolve perfectly well to a `place_id`, so nothing
 * upstream catches them; they only show up as a marker on something that
 * cannot be eaten at.
 *
 * Places API separates them cleanly: a street is `types: ["route"]` with no
 * `businessStatus`, while a venue carries a food type and `OPERATIONAL`.
 */

/**
 * Food-serving place types.
 *
 * Deliberately generous — a bakery or a wine bar is a legitimate "want to go".
 * Cuisine-specific types (`french_restaurant`, `sushi_restaurant`, …) are
 * matched by suffix rather than enumerated, since Google keeps adding them.
 */
const FOOD_TYPES = new Set([
  'restaurant',
  'food',
  'cafe',
  'coffee_shop',
  'bakery',
  'bar',
  'wine_bar',
  'pub',
  'bar_and_grill',
  'meal_takeaway',
  'meal_delivery',
  'ice_cream_shop',
  'sandwich_shop',
  'dessert_shop',
  'dessert_restaurant',
  'tea_house',
  'juice_shop',
  'donut_shop',
  'bagel_shop',
  'candy_store',
  'food_court',
  'deli',
  'delicatessen',
  // Markets and producers are kept deliberately. They are not restaurants,
  // but they are somewhere Moshik goes *to eat* — Marché Bastille, an oyster
  // farm — and dropping them is irreversible, since the importer now filters
  // the same way. Keeping a questionable place costs one skippable
  // suggestion; deleting a wanted one loses it for good.
  'market',
  'food_court',
  'farmers_market',
  'farm',
  'winery',
  'brewery',
  'distillery',
]);

export function isFoodPlace(types: string[] | undefined): boolean {
  if (!types || types.length === 0) return false;
  return types.some(
    (t) => FOOD_TYPES.has(t) || t.endsWith('_restaurant') || t.endsWith('_shop_restaurant')
  );
}

/**
 * True when the place should be kept.
 *
 * A permanently closed restaurant is worse than useless in a suggestion — it
 * sends you somewhere that no longer exists. Temporary closure is left in:
 * it is often seasonal, and it comes back.
 */
export function shouldKeepPlace(
  types: string[] | undefined,
  businessStatus: string | undefined
): boolean {
  if (!isFoodPlace(types)) return false;
  if (businessStatus === 'CLOSED_PERMANENTLY') return false;
  return true;
}

/** Why a place was dropped, for logging. */
export function rejectionReason(
  types: string[] | undefined,
  businessStatus: string | undefined
): string | null {
  if (!isFoodPlace(types)) {
    return `not a food place (types: ${(types ?? []).slice(0, 3).join(',') || 'none'})`;
  }
  if (businessStatus === 'CLOSED_PERMANENTLY') return 'permanently closed';
  return null;
}
