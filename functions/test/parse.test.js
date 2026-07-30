const test = require('node:test');
const assert = require('node:assert');
const AdmZip = require('adm-zip');

const {
  parseTakeoutArchive,
  parseSavedListCsv,
  coordsFromMapsUrl,
} = require('../lib/takeout');
const { parseStarredGeoJson } = require('../lib/dataportability');

test('a custom list becomes a list, not a marker', () => {
  const csv =
    'Title,Note,URL,Comment\n' +
    'Reykjavik Kitchen,,https://www.google.com/maps/place/x/@64.1466,-21.9426,17z,\n';

  const places = parseSavedListCsv(csv, 'Iceland trip');

  assert.strictEqual(places.length, 1);
  assert.strictEqual(places[0].name, 'Reykjavik Kitchen');
  assert.deepStrictEqual(places[0].lists, ['Iceland trip']);
  assert.deepStrictEqual(places[0].statuses, []);
});

test('Favorites maps onto the loved marker rather than a list', () => {
  const places = parseSavedListCsv('Title,URL\nJoes Pizza,https://x\n', 'Favorites');
  assert.deepStrictEqual(places[0].statuses, ['loved']);
  assert.deepStrictEqual(places[0].lists, []);
});

test('Want to go maps onto the flag marker', () => {
  const places = parseSavedListCsv('Title,URL\nNoma,https://x\n', 'Want to go');
  assert.deepStrictEqual(places[0].statuses, ['want_to_go']);
});

test('list-name matching ignores case', () => {
  const places = parseSavedListCsv('Title,URL\nA,https://x\n', 'FAVORITES');
  assert.deepStrictEqual(places[0].statuses, ['loved']);
});

test('coordinates are pulled from either Maps URL form', () => {
  assert.deepStrictEqual(
    coordsFromMapsUrl('https://www.google.com/maps/place/x/@64.1466,-21.9426,17z'),
    { lat: 64.1466, lng: -21.9426 }
  );
  assert.deepStrictEqual(
    coordsFromMapsUrl('https://maps.google.com/?q=x!3d40.7128!4d-74.0060'),
    { lat: 40.7128, lng: -74.006 }
  );
  assert.strictEqual(coordsFromMapsUrl('https://maps.app.goo.gl/abc123'), undefined);
});

test('starred GeoJSON reads coordinates in lng,lat order', () => {
  const geojson = JSON.stringify({
    type: 'FeatureCollection',
    features: [
      {
        geometry: { type: 'Point', coordinates: [-21.9426, 64.1466] },
        properties: {
          google_maps_url: 'https://maps.google.com/?cid=1',
          location: { name: 'Braud & Co', address: 'Frakkastigur 16' },
        },
      },
    ],
  });

  const places = parseStarredGeoJson(geojson);

  assert.strictEqual(places.length, 1);
  assert.strictEqual(places[0].lat, 64.1466);
  assert.strictEqual(places[0].lng, -21.9426);
  assert.deepStrictEqual(places[0].statuses, ['starred']);
});

test('malformed GeoJSON yields nothing instead of throwing', () => {
  assert.deepStrictEqual(parseStarredGeoJson('not json'), []);
  assert.deepStrictEqual(parseStarredGeoJson('{}'), []);
});

test('a place in two lists merges into one record carrying both', () => {
  const zip = new AdmZip();
  const url = 'https://www.google.com/maps/place/x/@64.1,-21.9,17z';
  zip.addFile(
    'Takeout/Maps (your places)/Saved/Iceland trip.csv',
    Buffer.from(`Title,URL\nBraud & Co,${url}\n`)
  );
  zip.addFile(
    'Takeout/Maps (your places)/Saved/Favorites.csv',
    Buffer.from(`Title,URL\nBraud & Co,${url}\n`)
  );

  const { places, listsFound } = parseTakeoutArchive(zip.toBuffer());

  assert.strictEqual(places.length, 1);
  assert.deepStrictEqual(places[0].statuses, ['loved']);
  assert.deepStrictEqual(places[0].lists, ['Iceland trip']);
  assert.strictEqual(listsFound.length, 2);
});

test('unrelated archive entries are ignored', () => {
  const zip = new AdmZip();
  zip.addFile('Takeout/Chrome/History.json', Buffer.from('{}'));
  zip.addFile('Takeout/Maps (your places)/Saved/Trip.csv', Buffer.from('Title\nA\n'));

  const { places } = parseTakeoutArchive(zip.toBuffer());

  assert.strictEqual(places.length, 1);
  assert.strictEqual(places[0].name, 'A');
});

test('rows without a title are skipped', () => {
  const places = parseSavedListCsv('Title,URL\n,https://x\nReal,https://y\n', 'Trip');
  assert.strictEqual(places.length, 1);
  assert.strictEqual(places[0].name, 'Real');
});
