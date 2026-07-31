const test = require('node:test');
const assert = require('node:assert');
const AdmZip = require('adm-zip');

const {
  parseTakeoutArchive,
  parseSavedListCsv,
  coordsFromMapsUrl,
  stripPreamble,
  statusForList,
} = require('../lib/takeout');
const { parseStarredGeoJson } = require('../lib/dataportability');

test('lists that map to no marker are ignored entirely', () => {
  const csv =
    'Title,Note,URL,Tags,Comment\n' +
    'Reykjavik Kitchen,,https://www.google.com/maps/place/x/@64.1466,-21.9426,17z,,\n';

  assert.deepStrictEqual(parseSavedListCsv(csv, 'Iceland trip'), []);
  assert.deepStrictEqual(parseSavedListCsv(csv, 'Parked car'), []);
  assert.deepStrictEqual(parseSavedListCsv(csv, 'Airbnbs'), []);
});

test('"Favorite places" is the real export name and maps to loved', () => {
  // Regression: only "Favorites" was matched, so every heart in a real
  // export was silently demoted to an ordinary list.
  assert.strictEqual(statusForList('Favorite places'), 'loved');
  assert.strictEqual(statusForList('FAVORITE PLACES'), 'loved');

  const places = parseSavedListCsv(
    'Title,URL\nJoes Pizza,https://x\n',
    'Favorite places'
  );
  assert.deepStrictEqual(places[0].statuses, ['loved']);
  assert.deepStrictEqual(places[0].lists, []);
});

test('a description line above the header does not shift the columns', () => {
  // Real export: an "Iceland Trip" list began with a free-text plan name,
  // which the parser adopted as column names.
  const csv =
    "Aakash & Omri's Iceland Plan\n" +
    'Title,Note,URL,Tags,Comment\n' +
    'Braud og Co,cinnamon buns,https://maps.google.com/?q=x,bakery,\n';

  const places = parseSavedListCsv(csv, 'Want to go');

  assert.strictEqual(places.length, 1);
  assert.strictEqual(places[0].name, 'Braud og Co');
  assert.match(places[0].note, /cinnamon buns/);
});

test('stripPreamble leaves a well-formed file untouched', () => {
  const csv = 'Title,Note,URL,Tags,Comment\nA,,https://x,,\n';
  assert.strictEqual(stripPreamble(csv), csv);
});

test('Tags are captured alongside Note rather than dropped', () => {
  const places = parseSavedListCsv(
    'Title,Note,URL,Tags,Comment\nNoma,book ahead,https://x,fine dining,\n',
    'Want to go'
  );
  assert.match(places[0].note, /book ahead/);
  assert.match(places[0].note, /fine dining/);
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

test('a place in two marker lists merges into one record carrying both', () => {
  const zip = new AdmZip();
  const url = 'https://www.google.com/maps/place/x/@64.1,-21.9,17z';
  zip.addFile(
    'Takeout/Maps (your places)/Saved/Want to go.csv',
    Buffer.from(`Title,URL\nBraud & Co,${url}\n`)
  );
  zip.addFile(
    'Takeout/Maps (your places)/Saved/Favorite places.csv',
    Buffer.from(`Title,URL\nBraud & Co,${url}\n`)
  );

  const { places } = parseTakeoutArchive(zip.toBuffer());

  assert.strictEqual(places.length, 1);
  assert.deepStrictEqual(
    [...places[0].statuses].sort(),
    ['loved', 'want_to_go']
  );
  assert.deepStrictEqual(places[0].lists, []);
});

test('irrelevant lists are reported as skipped, not imported', () => {
  const zip = new AdmZip();
  zip.addFile('Takeout/Chrome/History.json', Buffer.from('{}'));
  zip.addFile(
    'Takeout/Maps (your places)/Saved/Parked car.csv',
    Buffer.from('Title,URL\nSpot A,https://x\n')
  );
  zip.addFile(
    'Takeout/Maps (your places)/Saved/Want to go.csv',
    Buffer.from('Title,URL\nNoma,https://y\n')
  );

  const { places, skipped } = parseTakeoutArchive(zip.toBuffer());

  assert.strictEqual(places.length, 1);
  assert.strictEqual(places[0].name, 'Noma');
  assert.ok(skipped.includes('Parked car'));
});

test('rows without a title are skipped', () => {
  const places = parseSavedListCsv(
    'Title,URL\n,https://x\nReal,https://y\n',
    'Want to go'
  );
  assert.strictEqual(places.length, 1);
  assert.strictEqual(places[0].name, 'Real');
});
