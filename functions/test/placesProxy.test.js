const test = require('node:test');
const assert = require('node:assert');

const { searchCacheKey, photoObjectPath } = require('../lib/placesProxy');

/**
 * These cover the two claims the proxy exists to make: that a cache entry is
 * shared rather than per-user, and that a photo is remembered under something
 * stable. Both were got wrong once already — the client cached photos under
 * Google's photo resource name, which is minted fresh on every search
 * response, so the cache never hit and photos became the largest line on the
 * bill.
 */

test('photo keys ignore the photo resource name entirely', () => {
  // Two searches, seconds apart, for the same restaurant. Google returns the
  // same place and the same photos under completely different names.
  const fromSearchOne = photoObjectPath('ChIJt7fMLIlZwokRCRtM9bNDg78', 0, 800, 450);
  const fromSearchTwo = photoObjectPath('ChIJt7fMLIlZwokRCRtM9bNDg78', 0, 800, 450);
  assert.equal(fromSearchOne, fromSearchTwo);
  assert.equal(
    fromSearchOne,
    'places-photos/ChIJt7fMLIlZwokRCRtM9bNDg78/0_800x450.jpg'
  );
});

test('a place\'s photos do not collide with each other, or across sizes', () => {
  const first = photoObjectPath('PLACE_A', 0, 800, 450);
  const second = photoObjectPath('PLACE_A', 1, 800, 450);
  const thumbnail = photoObjectPath('PLACE_A', 0, 96, 96);
  assert.notEqual(first, second);
  assert.notEqual(first, thumbnail);
});

test('two people on the same street share one cached search', () => {
  // ~40m apart: inside the 3-decimal (~100m) rounding, so one entry serves both.
  const a = searchCacheKey({ textQuery: 'sushi', latitude: 40.72812, longitude: -73.99761 });
  const b = searchCacheKey({ textQuery: 'sushi', latitude: 40.72809, longitude: -73.99764 });
  assert.equal(a, b);
});

test('a different neighbourhood is a different entry', () => {
  const soho = searchCacheKey({ textQuery: 'sushi', latitude: 40.7281, longitude: -73.9976 });
  const uptown = searchCacheKey({ textQuery: 'sushi', latitude: 40.7851, longitude: -73.9683 });
  assert.notEqual(soho, uptown);
});

test('the query is normalised, so casing and stray spaces still share a hit', () => {
  const typed = searchCacheKey({ textQuery: '  Sushi ', latitude: 40.7281, longitude: -73.9976 });
  const clean = searchCacheKey({ textQuery: 'sushi', latitude: 40.7281, longitude: -73.9976 });
  assert.equal(typed, clean);
});

test('anything that changes what Google returns changes the key', () => {
  const base = { textQuery: 'sushi', latitude: 40.7281, longitude: -73.9976 };
  const baseline = searchCacheKey(base);

  // Each of these alters the result set, so serving the baseline entry for it
  // would hand back the wrong restaurants — or claim a closed kitchen is open.
  assert.notEqual(searchCacheKey({ ...base, openNow: true }), baseline);
  assert.notEqual(searchCacheKey({ ...base, priceLevels: ['PRICE_LEVEL_MODERATE'] }), baseline);
  assert.notEqual(searchCacheKey({ ...base, kind: 'nearby' }), baseline);
  assert.notEqual(searchCacheKey({ ...base, radius: 5000 }), baseline);
  assert.notEqual(searchCacheKey({ ...base, maxResultCount: 5 }), baseline);
  // The field tier selects the SKU ($5 / $35 / $40 per 1000), so a cheap-tier
  // answer must never be served to a caller that asked for the rich one.
  assert.notEqual(searchCacheKey({ ...base, fieldTier: 'essentials' }), baseline);
});

test('each sector of the map is its own cache entry', () => {
  // Browse splits the search box into sectors and queries each separately, so
  // every quarter contributes its own local best instead of the whole box
  // returning the same famous places. Sharing one entry between sectors would
  // undo that.
  const base = { textQuery: 'restaurant' };
  const northWest = searchCacheKey({
    ...base,
    rect: { lowLat: 40.72, lowLng: -74.00, highLat: 40.73, highLng: -73.99 },
  });
  const southEast = searchCacheKey({
    ...base,
    rect: { lowLat: 40.71, lowLng: -73.99, highLat: 40.72, highLng: -73.98 },
  });
  assert.notEqual(northWest, southEast);
});

test('the same sector, asked for twice, is one entry', () => {
  const rect = { lowLat: 40.72, lowLng: -74.0, highLat: 40.73, highLng: -73.99 };
  assert.equal(
    searchCacheKey({ textQuery: 'restaurant', rect }),
    searchCacheKey({ textQuery: 'restaurant', rect })
  );
});

test('a rectangle search never collides with a circle one', () => {
  // Different Places semantics — a rectangle restricts, a circle only biases —
  // so the two must not share an answer even over the same ground.
  const rect = searchCacheKey({
    textQuery: 'restaurant',
    rect: { lowLat: 40.72, lowLng: -74.0, highLat: 40.73, highLng: -73.99 },
  });
  const circle = searchCacheKey({
    textQuery: 'restaurant',
    latitude: 40.725,
    longitude: -73.995,
    radius: 1000,
  });
  assert.notEqual(rect, circle);
});

test('asking for opening hours is a different entry, because it is a different price', () => {
  const rect = { lowLat: 40.72, lowLng: -74.0, highLat: 40.73, highLng: -73.99 };
  assert.notEqual(
    searchCacheKey({ textQuery: 'restaurant', rect, fieldTier: 'browse' }),
    searchCacheKey({ textQuery: 'restaurant', rect, fieldTier: 'browseHours' })
  );
});

test('price filters match regardless of the order they arrive in', () => {
  const one = searchCacheKey({
    textQuery: 'sushi',
    latitude: 40.7281,
    longitude: -73.9976,
    priceLevels: ['PRICE_LEVEL_MODERATE', 'PRICE_LEVEL_INEXPENSIVE'],
  });
  const other = searchCacheKey({
    textQuery: 'sushi',
    latitude: 40.7281,
    longitude: -73.9976,
    priceLevels: ['PRICE_LEVEL_INEXPENSIVE', 'PRICE_LEVEL_MODERATE'],
  });
  assert.equal(one, other);
});
