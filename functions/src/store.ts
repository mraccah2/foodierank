import { createHash } from 'crypto';
import { FieldValue } from 'firebase-admin/firestore';
import { db } from './firebase';
import type {
  ImportJobDoc,
  ImportJobState,
  ImportSource,
  PlaceStatus,
  ResolvedPlace,
  SavedPlaceDoc,
} from './types';

/** Firestore caps a batched write at 500 operations. */
const BATCH_LIMIT = 450;

const savedPlaces = (uid: string) =>
  db.collection('users').doc(uid).collection('savedPlaces');

const importJobs = (uid: string) =>
  db.collection('users').doc(uid).collection('importJobs');

/**
 * Replace one source's contribution to a user's saved places.
 *
 * Each source owns a slice of every place (`sources.<source>`), and the
 * top-level `statuses`/`lists` are the union across slices. That keeps the two
 * ingest paths independent: re-running the Data Portability import refreshes
 * stars without touching the Loved/Want-to-go/list data that only a Takeout
 * upload can provide, and vice versa.
 */
export async function applyImport(
  uid: string,
  source: ImportSource,
  places: ResolvedPlace[],
  options: { prune?: boolean } = {}
): Promise<number> {
  // Pruning is only safe when `places` is the complete picture. A run cut
  // short by its deadline holds a fraction of the export, and pruning against
  // it would delete every place it had not reached yet.
  const prune = options.prune ?? true;
  const incoming = new Map<string, ResolvedPlace>();
  for (const place of places) {
    const existing = incoming.get(place.placeId);
    if (existing) {
      // Two archive entries resolved to the same place — union them.
      existing.statuses = unique([...existing.statuses, ...place.statuses]);
      existing.lists = unique([...existing.lists, ...place.lists]);
    } else {
      incoming.set(place.placeId, { ...place });
    }
  }

  const existingSnap = await savedPlaces(uid).get();
  const existingDocs = new Map(
    existingSnap.docs.map((doc) => [doc.id, doc.data() as SavedPlaceDoc])
  );

  let batch = db.batch();
  let opCount = 0;

  const flushIfNeeded = async () => {
    if (opCount >= BATCH_LIMIT) {
      await batch.commit();
      batch = db.batch();
      opCount = 0;
    }
  };

  // Upsert everything the import found.
  for (const [placeId, place] of incoming) {
    const prior = existingDocs.get(placeId);
    const sources = { ...(prior?.sources ?? {}) };
    sources[source] = { statuses: place.statuses, lists: place.lists };

    const doc: SavedPlaceDoc = {
      statuses: unionStatuses(sources),
      lists: unionLists(sources),
      sources,
      name: place.name,
      mapsUrl: place.mapsUrl,
      lat: place.lat,
      lng: place.lng,
      address: place.address,
      matchConfidence: place.matchConfidence,
      updatedAt: FieldValue.serverTimestamp(),
    };

    batch.set(savedPlaces(uid).doc(placeId), stripUndefined(doc), {
      merge: true,
    });
    opCount++;
    await flushIfNeeded();
  }

  // Drop this source's slice from places it no longer covers — the user
  // un-starred them in Google Maps since the last import.
  for (const [placeId, prior] of prune ? existingDocs : []) {
    if (incoming.has(placeId)) continue;
    if (!prior.sources?.[source]) continue;

    const sources = { ...prior.sources };
    delete sources[source];

    if (Object.keys(sources).length === 0) {
      batch.delete(savedPlaces(uid).doc(placeId));
    } else {
      batch.update(savedPlaces(uid).doc(placeId), {
        sources,
        statuses: unionStatuses(sources),
        lists: unionLists(sources),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    opCount++;
    await flushIfNeeded();
  }

  if (opCount > 0) await batch.commit();
  return incoming.size;
}

const resolutionCache = (uid: string) =>
  db.collection('users').doc(uid).collection('resolutionCache');

/**
 * Load every place lookup already answered for this user.
 *
 * Re-importing the same export otherwise re-resolves all 2000-odd entries and
 * burns the Places free allowance for no new information.
 */
export async function loadResolutionCache(
  uid: string
): Promise<Map<string, string | null>> {
  const snapshot = await resolutionCache(uid).get();
  const cache = new Map<string, string | null>();
  for (const doc of snapshot.docs) {
    cache.set(doc.data().key as string, (doc.data().placeId as string) ?? null);
  }
  return cache;
}

/** Persist lookups learned during a run. */
export async function saveResolutionCache(
  uid: string,
  learned: Map<string, string | null>
): Promise<void> {
  if (learned.size === 0) return;

  let batch = db.batch();
  let ops = 0;

  for (const [key, placeId] of learned) {
    // Hash the key: names contain slashes and other characters Firestore
    // rejects in document ids.
    const id = createHash('sha1').update(key).digest('hex');
    batch.set(resolutionCache(uid).doc(id), {
      key,
      placeId,
      resolvedAt: FieldValue.serverTimestamp(),
    });
    ops++;

    if (ops >= BATCH_LIMIT) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }

  if (ops > 0) await batch.commit();
}

export async function createImportJob(
  uid: string,
  source: ImportSource,
  fields: Partial<ImportJobDoc> = {}
): Promise<string> {
  const ref = importJobs(uid).doc();
  const doc: ImportJobDoc = {
    source,
    state: 'PENDING',
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    ...fields,
  };
  await ref.set(stripUndefined(doc));
  return ref.id;
}

export async function updateImportJob(
  uid: string,
  jobId: string,
  fields: Partial<ImportJobDoc> & { state?: ImportJobState }
): Promise<void> {
  await importJobs(uid)
    .doc(jobId)
    .set(
      stripUndefined({ ...fields, updatedAt: FieldValue.serverTimestamp() }),
      { merge: true }
    );
}

function unionStatuses(
  sources: SavedPlaceDoc['sources']
): PlaceStatus[] {
  return unique(
    Object.values(sources).flatMap((slice) => slice?.statuses ?? [])
  );
}

function unionLists(sources: SavedPlaceDoc['sources']): string[] {
  return unique(Object.values(sources).flatMap((slice) => slice?.lists ?? []));
}

function unique<T>(values: T[]): T[] {
  return [...new Set(values)];
}

/** Firestore rejects `undefined`; imports frequently have missing fields. */
function stripUndefined<T extends object>(value: T): T {
  const out: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value)) {
    if (item !== undefined) out[key] = item;
  }
  return out as T;
}
