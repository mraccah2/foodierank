/**
 * Server-side Places for the browse path.
 *
 * The app used to call places.googleapis.com straight from the device. That
 * put an unmeterable, unstoppable spend source in every installed copy: no
 * cache could be shared between two users looking at the same street, and the
 * only way to stop a runaway was to disable the API project-wide — which took
 * the whole app down on 2026-08-10.
 *
 * Everything browse-related now comes through here, which buys three things
 * the device could not:
 *
 *   Shared cache   one user's search and one user's photo pay for everyone's.
 *                  Photos dominate the bill (12,557 calls in Jul–Aug at
 *                  $7/1000) and a place's photo effectively never changes, so
 *                  they cache hard.
 *   Kill switch    `config/places.enabled` in Firestore. Flip it and calls
 *                  stop within a minute, with no App Store release.
 *   Attribution    one project, one service account, one place to look.
 *
 * Caching is deliberately time-boxed to stay inside the Google Maps Platform
 * terms, which permit temporary caching for performance but not indefinite
 * storage of Places content. Place ids are the documented exception and are
 * the only thing kept without expiry.
 *
 * ── App Check is a hard prerequisite for the client cutover ──
 * Today the device's Places calls are protected by API-key *application*
 * restrictions: `Config.appAttestationHeaders` sends `X-Ios-Bundle-Identifier`
 * and Google rejects the key from anywhere else. A callable has no equivalent,
 * and browse works signed-out, so there is no `req.auth` to lean on either.
 * Shipping the client onto these functions without App Check would replace a
 * bundle-locked key with an open, unauthenticated endpoint that spends money
 * on request — strictly worse than the problem being solved. So: add
 * `firebase_app_check` (App Attest on iOS), register it in the Firebase
 * console, and flip both callables to `enforceAppCheck: true` in the *same*
 * app release that starts calling them.
 */

import { createHash } from 'crypto';
import { logger } from 'firebase-functions';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { db, storage } from './firebase';
import { accessToken } from './placeResolve';

const REGION = 'us-central1';

const SEARCH_TEXT_URL = 'https://places.googleapis.com/v1/places:searchText';
const SEARCH_NEARBY_URL = 'https://places.googleapis.com/v1/places:searchNearby';
const PLACES_BASE = 'https://places.googleapis.com/v1';

/**
 * How long a cached search stays usable.
 *
 * Short, because results carry `currentOpeningHours` and an "open now" filter,
 * and a stale answer here means telling someone a closed kitchen is open. One
 * hour still collapses the repeat traffic that matters: the same person
 * flipping between cuisine filters and back, and two people searching the same
 * block within the hour.
 */
const SEARCH_TTL_MS = 60 * 60 * 1000;

/**
 * How long a cached photo stays usable — the ceiling the Maps Platform terms
 * allow for temporary caching. A place's photos are effectively static, so
 * this is where nearly all of the saving comes from.
 */
const PHOTO_TTL_MS = 30 * 24 * 60 * 60 * 1000;

/** Kill-switch reads are cached in-instance so a hot function is not doing a
 *  Firestore read per request; a minute is short enough to stop a runaway. */
const SWITCH_TTL_MS = 60 * 1000;

let switchCache: { enabled: boolean; reason: string; readAt: number } | null = null;

interface PlacesSwitch {
  enabled: boolean;
  reason: string;
}

/**
 * Whether Places calls are permitted right now.
 *
 * Fails OPEN. A Firestore blip must not black out browse for every user; the
 * budget meter that flips this flag runs hourly and will simply flip it again.
 */
async function placesEnabled(): Promise<PlacesSwitch> {
  if (switchCache && Date.now() - switchCache.readAt < SWITCH_TTL_MS) {
    return switchCache;
  }
  try {
    const snap = await db.doc('config/places').get();
    const data = snap.data() ?? {};
    switchCache = {
      // Absent document means "never configured", which is not the same as
      // "switched off" — a fresh project must work out of the box.
      enabled: data.enabled !== false,
      reason: (data.reason as string) ?? '',
      readAt: Date.now(),
    };
  } catch (error) {
    logger.warn('places kill switch unreadable, allowing', { error });
    switchCache = { enabled: true, reason: '', readAt: Date.now() };
  }
  return switchCache;
}

function assertEnabled(sw: PlacesSwitch): void {
  if (sw.enabled) return;
  // `resource-exhausted` rather than `permission-denied`: this is a budget
  // stop, and the client shows "temporarily unavailable" rather than asking
  // the user to sign in again.
  throw new HttpsError(
    'resource-exhausted',
    sw.reason || 'Place search is temporarily switched off.'
  );
}

function keyOf(parts: unknown): string {
  return createHash('sha1').update(JSON.stringify(parts)).digest('hex');
}

export interface SearchKeyParams {
  kind?: string;
  textQuery?: string;
  latitude: number;
  longitude: number;
  radius?: number;
  maxResultCount?: number;
  openNow?: boolean;
  priceLevels?: string[];
  fieldTier?: string;
}

/**
 * The cache key for a search.
 *
 * Coordinates are rounded to three decimals — roughly 100m — so two people on
 * the same street share one cached answer instead of each paying for their
 * own. Everything that changes what Google returns is in the key; nothing that
 * does not is, or the cache would fragment into single-use entries.
 */
export function searchCacheKey(p: SearchKeyParams): string {
  return keyOf({
    kind: p.kind ?? 'text',
    textQuery: (p.textQuery ?? '').trim().toLowerCase(),
    lat: p.latitude.toFixed(3),
    lon: p.longitude.toFixed(3),
    radius: p.radius ?? 1000,
    maxResultCount: p.maxResultCount ?? 20,
    openNow: !!p.openNow,
    priceLevels: [...(p.priceLevels ?? [])].sort(),
    fieldTier: p.fieldTier ?? 'atmosphere',
  });
}

/**
 * Where a cached photo lives.
 *
 * Note what is absent: the photo resource name. Google mints a fresh one on
 * every search response, so a path built from it would be written once and
 * never read again — the exact bug that made photos the largest line on the
 * bill. placeId and index are stable, and the size is included because the
 * list thumbnail and the card header are fetched at different dimensions.
 */
export function photoObjectPath(
  placeId: string,
  index: number,
  maxWidthPx: number,
  maxHeightPx: number
): string {
  return `places-photos/${placeId}/${index}_${maxWidthPx}x${maxHeightPx}.jpg`;
}

async function placesFetch(
  url: string,
  fieldMask: string,
  body: unknown
): Promise<{ ok: boolean; status: number; payload: any }> {
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${await accessToken()}`,
      // Required with OAuth so usage bills to this project; the runtime service
      // account needs roles/serviceusage.serviceUsageConsumer for it.
      'X-Goog-User-Project': process.env.GCLOUD_PROJECT ?? '',
      'X-Goog-FieldMask': fieldMask,
    },
    body: JSON.stringify(body),
  });
  const payload = await response.json().catch(() => ({}));
  return { ok: response.ok, status: response.status, payload };
}

/**
 * Text and nearby search.
 *
 * The client sends the same shape it used to send to Google, minus the key.
 * The field mask stays server-side on purpose: it is what selects the SKU
 * tier ($5 Essentials / $35 Enterprise / $40 Enterprise+Atmosphere per 1000),
 * and leaving it client-controlled would mean an old app version could pick
 * the expensive one forever.
 */
export const placesSearch = onCall(
  // MUST become `enforceAppCheck: true` in the same release that points the
  // client here — see the header note. Left false only so the functions can be
  // deployed and exercised before App Check exists; nothing calls them yet.
  { region: REGION, enforceAppCheck: false },
  async (req) => {
    const sw = await placesEnabled();
    assertEnabled(sw);

    const {
      kind = 'text',
      textQuery,
      latitude,
      longitude,
      radius = 1000,
      maxResultCount = 20,
      openNow,
      priceLevels,
      fieldTier = 'atmosphere',
    } = (req.data ?? {}) as Record<string, any>;

    if (typeof latitude !== 'number' || typeof longitude !== 'number') {
      throw new HttpsError('invalid-argument', 'latitude and longitude are required');
    }
    if (kind === 'text' && !textQuery) {
      throw new HttpsError('invalid-argument', 'textQuery is required for a text search');
    }

    const fieldMask =
      fieldTier === 'essentials'
        ? 'places.id,places.displayName,places.location,places.formattedAddress'
        : 'places.id,places.displayName,places.location,places.formattedAddress,' +
          'places.rating,places.userRatingCount,places.priceLevel,places.photos,' +
          'places.types,places.primaryType,places.primaryTypeDisplayName,' +
          'places.businessStatus,places.currentOpeningHours,places.regularOpeningHours,' +
          'places.editorialSummary,places.googleMapsUri';

    const cacheKey = searchCacheKey({
      kind,
      textQuery,
      latitude,
      longitude,
      radius,
      maxResultCount,
      openNow,
      priceLevels,
      fieldTier,
    });

    const ref = db.doc(`placesSearchCache/${cacheKey}`);
    const cached = await ref.get().catch(() => null);
    if (cached?.exists) {
      const data = cached.data() as { cachedAt: number; places: unknown[] };
      if (Date.now() - data.cachedAt < SEARCH_TTL_MS) {
        return { places: data.places, cached: true };
      }
    }

    const body: Record<string, unknown> =
      kind === 'nearby'
        ? {
            locationRestriction: {
              circle: { center: { latitude, longitude }, radius },
            },
            maxResultCount,
          }
        : {
            textQuery,
            locationBias: {
              circle: { center: { latitude, longitude }, radius },
            },
            maxResultCount,
            ...(openNow ? { openNow: true } : {}),
            ...(priceLevels?.length ? { priceLevels } : {}),
          };

    const { ok, status, payload } = await placesFetch(
      kind === 'nearby' ? SEARCH_NEARBY_URL : SEARCH_TEXT_URL,
      fieldMask,
      body
    );
    if (!ok) {
      logger.warn('places search failed', { status, error: payload?.error?.message });
      throw new HttpsError('unavailable', 'Place search failed');
    }

    const places = payload.places ?? [];
    // Cache writes must never fail the request: the caller already has its
    // answer, and a cache miss next time is cheaper than an error now.
    await ref
      .set({ cachedAt: Date.now(), places })
      .catch((error) => logger.warn('search cache write failed', { error }));

    return { places, cached: false };
  }
);

/** A fresh photo resource name for a place, when the client's has gone stale. */
async function freshPhotoName(placeId: string, index: number): Promise<string | null> {
  const response = await fetch(`${PLACES_BASE}/places/${placeId}?fields=photos`, {
    headers: {
      Authorization: `Bearer ${await accessToken()}`,
      'X-Goog-User-Project': process.env.GCLOUD_PROJECT ?? '',
    },
  });
  if (!response.ok) return null;
  const payload = (await response.json()) as { photos?: { name: string }[] };
  return payload.photos?.[index]?.name ?? null;
}

/**
 * A place photo, cached in Cloud Storage and served by URL.
 *
 * Keyed on `placeId + index + size`, never on the photo resource name —
 * Google mints a fresh name on every search response (verified against the
 * live API), so a name-keyed cache has a 0% hit rate across searches. That
 * exact bug is what made photos the single largest line on the bill.
 *
 * Returns a URL rather than bytes: base64 through a callable would inflate
 * every image by a third and bill the egress twice.
 */
export const placesPhoto = onCall(
  // MUST become `enforceAppCheck: true` in the same release that points the
  // client here — see the header note. Left false only so the functions can be
  // deployed and exercised before App Check exists; nothing calls them yet.
  { region: REGION, enforceAppCheck: false },
  async (req) => {
    const sw = await placesEnabled();
    assertEnabled(sw);

    const {
      placeId,
      photoName,
      index = 0,
      maxWidthPx = 800,
      maxHeightPx = 450,
    } = (req.data ?? {}) as Record<string, any>;

    if (!placeId) throw new HttpsError('invalid-argument', 'placeId is required');

    const objectPath = photoObjectPath(placeId, index, maxWidthPx, maxHeightPx);
    const file = storage.bucket().file(objectPath);

    const [exists] = await file.exists().catch(() => [false]);
    if (exists) {
      const [meta] = await file.getMetadata().catch(() => [{} as any]);
      const age = Date.now() - new Date(meta.timeCreated ?? 0).getTime();
      if (age < PHOTO_TTL_MS) {
        return { url: await downloadUrl(file), cached: true };
      }
    }

    // The client's photoName came from a search response that may itself have
    // been served from cache, so it can be stale. Try it, then re-resolve once.
    let name: string | null = photoName ?? null;
    let bytes = name ? await fetchPhotoBytes(name, maxWidthPx, maxHeightPx) : null;
    if (!bytes) {
      name = await freshPhotoName(placeId, index);
      if (name) bytes = await fetchPhotoBytes(name, maxWidthPx, maxHeightPx);
    }
    if (!bytes) throw new HttpsError('not-found', 'No photo for that place');

    await file
      .save(Buffer.from(bytes), { contentType: 'image/jpeg', resumable: false })
      .catch((error) => logger.warn('photo cache write failed', { error }));

    return { url: await downloadUrl(file), cached: false };
  }
);

async function fetchPhotoBytes(
  photoName: string,
  maxWidthPx: number,
  maxHeightPx: number
): Promise<ArrayBuffer | null> {
  const url =
    `${PLACES_BASE}/${photoName}/media` +
    `?maxWidthPx=${maxWidthPx}&maxHeightPx=${maxHeightPx}`;
  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${await accessToken()}`,
      'X-Goog-User-Project': process.env.GCLOUD_PROJECT ?? '',
    },
  });
  if (!response.ok) {
    logger.info('photo fetch failed, will re-resolve', { status: response.status });
    return null;
  }
  return await response.arrayBuffer();
}

/** A long-lived read URL for a cached photo object. */
async function downloadUrl(file: ReturnType<ReturnType<typeof storage.bucket>['file']>) {
  const [url] = await file.getSignedUrl({
    action: 'read',
    // Comfortably inside the cache TTL, so a URL can never outlive the object
    // it points at.
    expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
  });
  return url;
}
