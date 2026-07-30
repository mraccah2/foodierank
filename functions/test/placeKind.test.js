const test = require('node:test');
const assert = require('node:assert');

const { isFoodPlace, shouldKeepPlace, rejectionReason } = require('../lib/placeKind');

test('restaurants are kept', () => {
  assert.ok(shouldKeepPlace(['sandwich_shop', 'restaurant', 'food'], 'OPERATIONAL'));
  assert.ok(shouldKeepPlace(['french_restaurant', 'food_store'], 'OPERATIONAL'));
});

test('cuisine-specific types are matched by suffix, not a hardcoded list', () => {
  // Google keeps adding these; enumerating them would silently drop new ones.
  assert.ok(isFoodPlace(['sushi_restaurant']));
  assert.ok(isFoodPlace(['vietnamese_restaurant']));
  assert.ok(isFoodPlace(['afghani_restaurant']));
});

test('streets and place names are dropped', () => {
  // Real entries from the export: "Rue de Bretagne", "Karol Bagh", "Psyri".
  assert.strictEqual(shouldKeepPlace(['route'], undefined), false);
  assert.strictEqual(shouldKeepPlace(['locality', 'political'], undefined), false);
  assert.strictEqual(shouldKeepPlace(['neighborhood', 'political'], undefined), false);
  assert.strictEqual(shouldKeepPlace(['premise', 'street_address'], undefined), false);
});

test('attractions and lodging are dropped', () => {
  assert.strictEqual(shouldKeepPlace(['beach', 'natural_feature'], 'OPERATIONAL'), false);
  assert.strictEqual(shouldKeepPlace(['buddhist_temple', 'place_of_worship'], 'OPERATIONAL'), false);
  assert.strictEqual(shouldKeepPlace(['lodging', 'point_of_interest'], 'OPERATIONAL'), false);
});

test('a permanently closed restaurant is dropped', () => {
  assert.strictEqual(shouldKeepPlace(['restaurant'], 'CLOSED_PERMANENTLY'), false);
  assert.match(rejectionReason(['restaurant'], 'CLOSED_PERMANENTLY'), /permanently closed/);
});

test('a temporarily closed restaurant is kept', () => {
  // Often seasonal, and it comes back — losing it would be irreversible.
  assert.ok(shouldKeepPlace(['restaurant'], 'CLOSED_TEMPORARILY'));
});

test('markets and producers are kept on purpose', () => {
  // Not restaurants, but places Moshik goes to eat — Marché Bastille, an
  // oyster farm. Keeping a questionable one costs a skippable suggestion;
  // deleting a wanted one loses it for good.
  assert.ok(shouldKeepPlace(['market', 'point_of_interest'], 'OPERATIONAL'));
  assert.ok(shouldKeepPlace(['farm', 'point_of_interest'], 'OPERATIONAL'));
  assert.ok(shouldKeepPlace(['winery'], 'OPERATIONAL'));
});

test('missing types are treated as not-a-restaurant', () => {
  assert.strictEqual(shouldKeepPlace(undefined, 'OPERATIONAL'), false);
  assert.strictEqual(shouldKeepPlace([], 'OPERATIONAL'), false);
});

test('rejectionReason is null for a place that is kept', () => {
  assert.strictEqual(rejectionReason(['restaurant'], 'OPERATIONAL'), null);
});
