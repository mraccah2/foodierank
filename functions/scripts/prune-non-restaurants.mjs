#!/usr/bin/env node
/**
 * One-off backfill: drop saved places that aren't restaurants, or are gone.
 *
 * The 1775 places already in Firestore were resolved before the importer knew
 * how to ask for `types` / `businessStatus`, so they include streets
 * ("Rue de Bretagne"), neighbourhoods and permanently closed venues. Future
 * imports filter these at resolution time; this cleans up what is already there.
 *
 * Reads each place's types from Places API, then deletes the ones that fail
 * `shouldKeepPlace` and annotates the survivors.
 *
 * Dry run by default — pass --apply to actually write.
 *
 *   node scripts/prune-non-restaurants.mjs [--apply] [--uid <uid>]
 */
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { GoogleAuth } from 'google-auth-library';
import { shouldKeepPlace, rejectionReason } from '../lib/placeKind.js';

const APPLY = process.argv.includes('--apply');
const uidArg = process.argv.indexOf('--uid');
const UID = uidArg >= 0 ? process.argv[uidArg + 1] : 'akHezxWe7mOndRBXHiK0uET9gSx2';
const PROJECT = process.env.GCLOUD_PROJECT || 'foodierank-bb880';

initializeApp({ credential: applicationDefault(), projectId: PROJECT });
const db = getFirestore();

const auth = new GoogleAuth({
  scopes: ['https://www.googleapis.com/auth/cloud-platform'],
});
const client = await auth.getClient();
const { token } = await client.getAccessToken();

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Place Details enforces a per-minute rate limit, and an unthrottled sweep of
 * ~1800 ids trips it hard — a first pass left 503 of them unchecked on 429.
 * A small gap between calls plus backoff on 429 gets the whole set through.
 */
async function details(placeId, attempt = 0) {
  await sleep(60);

  const response = await fetch(`https://places.googleapis.com/v1/places/${placeId}`, {
    headers: {
      Authorization: `Bearer ${token}`,
      'X-Goog-User-Project': PROJECT,
      'X-Goog-FieldMask': 'id,displayName,types,businessStatus',
    },
  });

  if (response.status === 429 && attempt < 5) {
    await sleep(2000 * 2 ** attempt);
    return details(placeId, attempt + 1);
  }
  if (response.status === 404) return { gone: true };
  if (!response.ok) {
    throw new Error(`${response.status} ${(await response.text()).slice(0, 120)}`);
  }
  return response.json();
}

const snapshot = await db.collection('users').doc(UID).collection('savedPlaces').get();
console.log(`${snapshot.size} saved places for ${UID}\n`);

const drop = [];
const keep = [];
let failed = 0;

for (const doc of snapshot.docs) {
  const name = doc.data().name || '(unnamed)';
  try {
    const place = await details(doc.id);
    if (place.gone) {
      // A place_id Google no longer recognises is as useless as a street.
      drop.push({ id: doc.id, name, reason: 'place_id no longer exists' });
      continue;
    }
    if (shouldKeepPlace(place.types, place.businessStatus)) {
      keep.push({ id: doc.id, types: place.types, businessStatus: place.businessStatus });
    } else {
      drop.push({ id: doc.id, name, reason: rejectionReason(place.types, place.businessStatus) });
    }
  } catch (e) {
    // Leave anything we could not check alone — deleting on an API blip would
    // silently lose real places.
    failed++;
    console.warn(`  ? ${name}: ${e.message}`);
  }
}

console.log(`\nkeep   ${keep.length}`);
console.log(`drop   ${drop.length}`);
console.log(`unchecked ${failed} (left in place)\n`);

const byReason = {};
for (const d of drop) byReason[d.reason] = (byReason[d.reason] || 0) + 1;
for (const [reason, n] of Object.entries(byReason).sort((a, b) => b[1] - a[1])) {
  console.log(`  ${String(n).padStart(4)}  ${reason}`);
}
console.log('\nexamples to drop:');
for (const d of drop.slice(0, 15)) console.log(`  - ${d.name}  (${d.reason})`);

if (!APPLY) {
  console.log('\nDry run. Re-run with --apply to delete.');
  process.exit(0);
}

let batch = db.batch();
let ops = 0;
const flush = async () => {
  if (ops === 0) return;
  await batch.commit();
  batch = db.batch();
  ops = 0;
};

for (const d of drop) {
  batch.delete(db.collection('users').doc(UID).collection('savedPlaces').doc(d.id));
  if (++ops >= 400) await flush();
}
for (const k of keep) {
  batch.set(
    db.collection('users').doc(UID).collection('savedPlaces').doc(k.id),
    { types: k.types ?? [], businessStatus: k.businessStatus ?? null },
    { merge: true }
  );
  if (++ops >= 400) await flush();
}
await flush();

console.log(`\nDeleted ${drop.length}, annotated ${keep.length}.`);
