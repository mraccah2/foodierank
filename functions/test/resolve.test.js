const test = require('node:test');
const assert = require('node:assert');

const { resolvePlaces, resolutionKey } = require('../lib/placeResolve');

const place = (name, extra = {}) => ({
  name,
  statuses: ['want_to_go'],
  lists: [],
  ...extra,
});

test('a cached hit is reused without an API call', async () => {
  const cache = new Map([[resolutionKey(place('Noma')), 'place-noma']]);

  const result = await resolvePlaces([place('Noma')], 'unused-key', {
    cache,
    deadline: Date.now() + 60_000,
  });

  assert.strictEqual(result.lookups, 0, 'should not call the API');
  assert.strictEqual(result.resolved.length, 1);
  assert.strictEqual(result.resolved[0].placeId, 'place-noma');
  assert.strictEqual(result.complete, true);
});

test('a cached miss stays a miss and costs nothing', async () => {
  // ~15% of entries never resolve. Without caching misses they would be
  // looked up again on every single run, forever.
  const cache = new Map([[resolutionKey(place('Long Gone Cafe')), null]]);

  const result = await resolvePlaces([place('Long Gone Cafe')], 'unused-key', {
    cache,
    deadline: Date.now() + 60_000,
  });

  assert.strictEqual(result.lookups, 0);
  assert.strictEqual(result.resolved.length, 0);
  assert.strictEqual(result.complete, true);
});

test('an expired deadline stops before any lookup and reports incomplete', async () => {
  const result = await resolvePlaces([place('Anything')], 'unused-key', {
    cache: new Map(),
    deadline: Date.now() - 1,
  });

  assert.strictEqual(result.lookups, 0);
  assert.strictEqual(result.complete, false, 'must not claim completeness');
  assert.strictEqual(result.resolved.length, 0);
});

test('cached work is done even when the deadline has passed', async () => {
  // Cache hits cost nothing, so a resumed run should still apply everything it
  // already knows rather than stalling at the first uncached entry.
  const cache = new Map([[resolutionKey(place('Known')), 'place-known']]);

  const result = await resolvePlaces(
    [place('Known'), place('Unknown')],
    'unused-key',
    { cache, deadline: Date.now() - 1 }
  );

  assert.strictEqual(result.resolved.length, 1);
  assert.strictEqual(result.resolved[0].placeId, 'place-known');
  assert.strictEqual(result.complete, false);
});

test('the same place in two lists resolves once and keeps both markers', async () => {
  const key = resolutionKey(place('Braud'));
  const cache = new Map([[key, 'place-braud']]);

  const result = await resolvePlaces(
    [
      { name: 'Braud', statuses: ['loved'], lists: [] },
      { name: 'Braud', statuses: ['want_to_go'], lists: [] },
    ],
    'unused-key',
    { cache, deadline: Date.now() + 60_000 }
  );

  assert.strictEqual(result.lookups, 0);
  assert.strictEqual(result.resolved.length, 2);
  assert.ok(result.resolved.every((r) => r.placeId === 'place-braud'));
});

test('resolutionKey ignores case and trailing whitespace', () => {
  assert.strictEqual(resolutionKey(place('  Noma ')), resolutionKey(place('noma')));
});

test('resolutionKey separates places sharing a name at different coordinates', () => {
  const a = resolutionKey(place('Joes Pizza', { lat: 40.73, lng: -74.0 }));
  const b = resolutionKey(place('Joes Pizza', { lat: 25.77, lng: -80.19 }));
  assert.notStrictEqual(a, b);
});
