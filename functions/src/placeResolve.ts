import { defineSecret } from 'firebase-functions/params';
import { GoogleAuth } from 'google-auth-library';
import { logger } from 'firebase-functions';
import type { RawPlace, ResolvedPlace } from './types';

export const PLACES_API_KEY = defineSecret('GOOGLE_PLACES_API_KEY');

const SEARCH_TEXT_URL = 'https://places.googleapis.com/v1/places:searchText';

/**
 * Authenticate to Places with the function's own service account.
 *
 * The API key worked too — imports were succeeding on it. OAuth is kept
 * because it means no long-lived key has to be stored, injected and rotated
 * for a backend that already has an identity of its own.
 *
 * `X-Goog-User-Project` must accompany it so usage is attributed to this
 * project; that requires the runtime service account to hold
 * roles/serviceusage.serviceUsageConsumer.
 */
const auth = new GoogleAuth({
  scopes: ['https://www.googleapis.com/auth/cloud-platform'],
});

let cachedToken: { value: string; expiresAt: number } | null = null;

async function accessToken(): Promise<string> {
  // Tokens last an hour; a single import makes thousands of calls, so minting
  // one per request would dominate the run time.
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) {
    return cachedToken.value;
  }
  const client = await auth.getClient();
  const token = await client.getAccessToken();
  if (!token.token) throw new Error('Could not mint an access token');
  cachedToken = { value: token.token, expiresAt: Date.now() + 45 * 60_000 };
  return cachedToken.value;
}

/** A text-search hit is only trusted as `exact` within this distance. */
const COORD_MATCH_RADIUS_M = 150;

/** Location bias radius when the archive gave us coordinates. */
const BIAS_RADIUS_M = 500;

/**
 * Resolve imported places to Google `place_id`s.
 *
 * FoodieRank matches markers to search results by `place_id`, but only the
 * starred-places GeoJSON identifies places usefully. Takeout list CSVs give a
 * name and a URL and nothing else, so those have to be looked up.
 *
 * Calls are billed per request, so results are cached by query within a run and
 * the caller is expected to batch whole imports rather than resolve per view.
 */
/** Stable key for a lookup, so a repeat import reuses the previous answer. */
export function resolutionKey(place: RawPlace): string {
  const coords =
    typeof place.lat === 'number' && typeof place.lng === 'number'
      ? `${place.lat.toFixed(3)},${place.lng.toFixed(3)}`
      : '';
  return `${place.name.trim().toLowerCase()}|${coords}`;
}

export interface ResolveOptions {
  /**
   * Previously resolved keys, including misses. A miss is cached as null on
   * purpose: roughly 15% of entries never match, and without that they would
   * be looked up again on every single run.
   */
  cache: Map<string, string | null>;
  /** Stop starting new lookups once past this moment. */
  deadline: number;
}

export interface ResolveResult {
  resolved: ResolvedPlace[];
  /** Keys looked up this run, to be persisted by the caller. */
  learned: Map<string, string | null>;
  lookups: number;
  /** False when the deadline cut the run short and work remains. */
  complete: boolean;
}

/**
 * Resolve imported places to Google `place_id`s.
 *
 * Two things keep this affordable and inside the function timeout: answers are
 * cached across runs, so a monthly re-import costs almost nothing; and the run
 * stops at a deadline rather than a fixed count, using whatever budget is
 * actually available. An incomplete run is resumed on the next tick, by which
 * point everything already done is a cache hit.
 */
export async function resolvePlaces(
  places: RawPlace[],
  apiKey: string,
  options: ResolveOptions
): Promise<ResolveResult> {
  const resolved: ResolvedPlace[] = [];
  const learned = new Map<string, string | null>();
  const byPlaceId = new Map<string, ResolvedPlace>();
  let lookups = 0;
  let complete = true;

  for (const place of places) {
    const key = resolutionKey(place);
    const known = options.cache.has(key)
      ? options.cache.get(key)
      : learned.get(key);

    if (known !== undefined) {
      // A miss stays a miss; a hit is reused with this occurrence's markers,
      // which may differ when the place appears in more than one list.
      if (known) {
        const previous = byPlaceId.get(known);
        resolved.push({
          ...(previous ?? {}),
          ...place,
          placeId: known,
          matchConfidence: previous?.matchConfidence ?? 'weak',
        });
      }
      continue;
    }

    if (Date.now() > options.deadline) {
      complete = false;
      break;
    }

    const match = await resolveOne(place, apiKey);
    lookups++;
    learned.set(key, match?.placeId ?? null);
    if (match) {
      byPlaceId.set(match.placeId, match);
      resolved.push(match);
    }
  }

  return { resolved, learned, lookups, complete };
}

async function resolveOne(
  place: RawPlace,
  apiKey: string
): Promise<ResolvedPlace | null> {
  const hasCoords =
    typeof place.lat === 'number' && typeof place.lng === 'number';

  const body: Record<string, unknown> = {
    textQuery: place.address ? `${place.name} ${place.address}` : place.name,
    maxResultCount: 1,
  };

  if (hasCoords) {
    body.locationBias = {
      circle: {
        center: { latitude: place.lat, longitude: place.lng },
        radius: BIAS_RADIUS_M,
      },
    };
  }

  let payload: {
    places?: {
      id?: string;
      displayName?: { text?: string };
      location?: { latitude?: number; longitude?: number };
      formattedAddress?: string;
    }[];
    error?: { message?: string };
  };

  try {
    const response = await fetch(SEARCH_TEXT_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${await accessToken()}`,
        'X-Goog-User-Project': process.env.GCLOUD_PROJECT ?? '',
        'X-Goog-FieldMask':
          'places.id,places.displayName,places.location,places.formattedAddress',
      },
      body: JSON.stringify(body),
    });
    payload = (await response.json()) as typeof payload;
    if (!response.ok) {
      logger.warn('Place text search failed', {
        name: place.name,
        status: response.status,
        message: payload.error?.message,
      });
      return null;
    }
  } catch (error) {
    logger.warn('Place text search threw', { name: place.name, error });
    return null;
  }

  const hit = payload.places?.[0];
  if (!hit?.id) {
    // Roughly 15% of list entries never match: CSV exports carry only a name,
    // and some are places that have since closed or were saved by coordinates.
    logger.debug('No place match', { name: place.name });
    return null;
  }

  return {
    ...place,
    placeId: hit.id,
    lat: hit.location?.latitude ?? place.lat,
    lng: hit.location?.longitude ?? place.lng,
    address: hit.formattedAddress ?? place.address,
    matchConfidence: confidenceFor(place, hit.location, hasCoords),
  };
}

function confidenceFor(
  place: RawPlace,
  hitLocation: { latitude?: number; longitude?: number } | undefined,
  hadCoords: boolean
): ResolvedPlace['matchConfidence'] {
  if (!hadCoords) return 'weak';
  if (
    typeof hitLocation?.latitude !== 'number' ||
    typeof hitLocation?.longitude !== 'number'
  ) {
    return 'likely';
  }

  const metres = haversineMetres(
    place.lat as number,
    place.lng as number,
    hitLocation.latitude,
    hitLocation.longitude
  );
  return metres <= COORD_MATCH_RADIUS_M ? 'exact' : 'likely';
}

function haversineMetres(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number
): number {
  const R = 6371000;
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
