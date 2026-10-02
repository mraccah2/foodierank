#!/usr/bin/env node
/**
 * One-off backfill: drop saved places that aren't restaurants, or are gone.
 *
 * The 1775 places already in Firestore were resolved before the importer knew
 * how to ask for `types` / `businessStatus`, so they include streets
 * ("Rue de Bretagne"), neighbourhoods and permanently closed venues. Future
 * imports filter these at resolution time; this cleans up what is already there.
 *
 * Reads each place's types through the shared Places gateway (never Google
 * directly), then deletes the ones that fail `shouldKeepPlace` and annotates
 * the survivors. The gateway buys a place from Google once, ever, so a re-run
 * costs nothing.
 *
 * Dry run by default — pass --apply to actually write.
 *
 *   export PLACES_GATEWAY_KEY=$(op read "op://Dev/Places Gateway App Keys/foodierank")
 *   node scripts/prune-non-restaurants.mjs [--apply] [--uid <uid>]
 */
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { shouldKeepPlace, rejectionReason } from '../lib/placeKind.js';

const APPLY = process.argv.includes('--apply');
const uidArg = process.argv.indexOf('--uid');
const UID = uidArg >= 0 ? process.argv[uidArg + 1] : 'akHezxWe7mOndRBXHiK0uET9gSx2';
const PROJECT = process.env.GCLOUD_PROJECT || 'foodierank-bb880';

initializeApp({ credential: applicationDefault(), projectId: PROJECT });
const db = getFirestore();

const GATEWAY_URL = 'https://cndaivlyzonqndnvzilr.supabase.co/functions/v1/places';
const GATEWAY_KEY = process.env.PLACES_GATEWAY_KEY;
if (!GATEWAY_KEY) {
  console.error('PLACES_GATEWAY_KEY is not set.');
  process.exit(78);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Place Details through the gateway. Google's per-minute limit still applies
 * to whatever the gateway has not bought yet — a first direct pass left 503
 * ids unchecked on 429 — so keep a small gap between calls and back off on
 * 429, and on the gateway's 503 ("someone else is fetching this right now").
 */
async function details(placeId, attempt = 0) {
  await sleep(60);

  const response = await fetch(GATEWAY_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-app-key': GATEWAY_KEY },
    body: JSON.stringify({ op: 'details', placeId }),
  });

  if ((response.status === 429 || response.status === 503) && attempt < 5) {
    await sleep(response.status === 503 ? 1000 : 2000 * 2 ** attempt);
    return details(placeId, attempt + 1);
  }
  const text = await response.text();
  // A place_id Google no longer recognises comes back as notFound, or as
  // Google's 404 relayed through the gateway.
  if (/^\{"error":"Google 404/.test(text)) return { gone: true };
  if (!response.ok) {
    throw new Error(`${response.status} ${text.slice(0, 120)}`);
  }
  const { place, notFound } = JSON.parse(text);
  if (notFound || !place) return { gone: true };
  return place;
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
