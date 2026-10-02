import { defineSecret } from 'firebase-functions/params';
import { logger } from 'firebase-functions';
import { rejectionReason } from './placeKind';
import type { RawPlace, ResolvedPlace } from './types';

/**
 * FoodieRank's app key for the shared Places gateway.
 *
 * Places is no longer called directly: every lookup goes through the gateway,
 * which buys each place from Google once, ever, and caches searches on the
 * canonical request. A monthly re-import of the same saved places therefore
 * costs Google nothing even before the per-user resolution cache below.
 */
export const PLACES_GATEWAY_KEY = defineSecret('PLACES_GATEWAY_KEY');

export const PLACES_GATEWAY_URL =
  'https://cndaivlyzonqndnvzilr.supabase.co/functions/v1/places';

/**
 * POST `{op, ...body}` to the Places gateway.
 *
 * A 503 means another caller is fetching the very same thing right now; one
 * retry a second later usually finds it cached. Anything else non-2xx is
 * thrown with the gateway's error text.
 */
export async function placesGateway<T>(
  op: string,
  body: Record<string, unknown>,
  appKey: string
): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    const response = await fetch(PLACES_GATEWAY_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-app-key': appKey },
      body: JSON.stringify({ ...body, op }),
    });
    if (response.status === 503 && attempt === 0) {
      await new Promise((resolve) => setTimeout(resolve, 1000));
      continue;
    }
    const payload = (await response.json().catch(() => ({}))) as T & {
      error?: string;
    };
    if (!response.ok) {
      throw new Error(
        `Places gateway ${op} ${response.status}: ${payload.error ?? ''}`
      );
    }
    return payload;
  }
}

/** A text-search hit is only trusted as `exact` within this distance. */
const COORD_MATCH_RADIUS_M = 150;

/** Location bias radius when the archive gave us coordinates. */
const BIAS_RADIUS_M = 500;

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
  gatewayKey: string,
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

    const match = await resolveOne(place, gatewayKey);
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
  gatewayKey: string
): Promise<ResolvedPlace | null> {
  const hasCoords =
    typeof place.lat === 'number' && typeof place.lng === 'number';

  // Google's own searchText body; the gateway returns every field, so types
  // and businessStatus (used to drop streets and closed venues) come with it.
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
      types?: string[];
      businessStatus?: string;
    }[];
  };

  try {
    payload = await placesGateway<typeof payload>(
      'searchText',
      body,
      gatewayKey
    );
  } catch (error) {
    logger.warn('Place text search failed', {
      name: place.name,
      message: error instanceof Error ? error.message : String(error),
    });
    return null;
  }

  const hit = payload.places?.[0];
  if (!hit?.id) {
    // Roughly 15% of list entries never match: CSV exports carry only a name,
    // and some are places that have since closed or were saved by coordinates.
    logger.debug('No place match', { name: place.name });
    return null;
  }

  // Google's lists contain streets and shuttered venues alongside real ones.
  // Drop them here so they never reach Firestore, rather than filtering at
  // every read site.
  const reason = rejectionReason(hit.types, hit.businessStatus);
  if (reason) {
    logger.debug('Dropping non-restaurant', { name: place.name, reason });
    return null;
  }

  return {
    ...place,
    placeId: hit.id,
    types: hit.types,
    businessStatus: hit.businessStatus,
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
