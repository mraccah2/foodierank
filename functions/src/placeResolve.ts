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
export async function resolvePlaces(
  places: RawPlace[],
  apiKey: string
): Promise<ResolvedPlace[]> {
  const resolved: ResolvedPlace[] = [];
  const cache = new Map<string, ResolvedPlace | null>();

  for (const place of places) {
    const cacheKey = `${place.name}|${place.lat ?? ''},${place.lng ?? ''}`;
    if (cache.has(cacheKey)) {
      const hit = cache.get(cacheKey);
      if (hit) {
        // Same physical place, but this occurrence may carry different
        // markers or lists (e.g. found again in another list file).
        resolved.push({ ...hit, ...place, placeId: hit.placeId });
      }
      continue;
    }

    const match = await resolveOne(place, apiKey);
    cache.set(cacheKey, match);
    if (match) resolved.push(match);
  }

  return resolved;
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
