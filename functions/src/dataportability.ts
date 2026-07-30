import { logger } from 'firebase-functions';
import type { ImportJobState, RawPlace } from './types';

const API_BASE = 'https://dataportability.googleapis.com/v1';

/**
 * Resource group for Starred places. The request body uses the bare group
 * name (no `dataportability.` prefix), while the OAuth *scope* does carry the
 * prefix — mixing the two up is an easy way to get an opaque 400.
 */
export const STARRED_PLACES_RESOURCE = 'maps.starred_places';

export interface ArchiveState {
  state: ImportJobState;
  urls: string[];
}

/**
 * Google refused the export because this resource group was already exported
 * inside the current 24-hour window.
 *
 * Carries the timestamp after which a retry is allowed, so callers can wait
 * rather than pointlessly resetting authorization — a reset would revoke every
 * scope and force the user back through consent.
 */
export class ArchiveRateLimitError extends Error {
  constructor(
    message: string,
    readonly retryAfter: Date | null,
  ) {
    super(message);
    this.name = 'ArchiveRateLimitError';
  }
}

/** Kick off an export. Returns the archive job id to poll. */
export async function initiateArchive(
  accessToken: string,
  resources: string[]
): Promise<string> {
  const response = await fetch(`${API_BASE}/portabilityArchive:initiate`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ resources }),
  });

  const payload = (await response.json()) as {
    archiveJobId?: string;
    error?: {
      message?: string;
      status?: string;
      details?: { reason?: string; metadata?: Record<string, string> }[];
    };
  };

  if (response.status === 429) {
    throw new ArchiveRateLimitError(
      payload.error?.message ?? 'Already exported in the last 24 hours.',
      retryAfterFrom(payload.error?.details),
    );
  }

  if (!response.ok || !payload.archiveJobId) {
    throw new Error(
      `initiate failed (${response.status}): ${
        payload.error?.message ?? 'unknown error'
      }`
    );
  }
  return payload.archiveJobId;
}

/**
 * Dig the retry timestamp out of the error details. Google reports it under
 * `RESOURCE_EXHAUSTED_TIME_BASED`, but the metadata key has moved before, so
 * fall back to any parseable timestamp rather than failing outright.
 */
function retryAfterFrom(
  details: { reason?: string; metadata?: Record<string, string> }[] | undefined
): Date | null {
  for (const detail of details ?? []) {
    for (const value of Object.values(detail.metadata ?? {})) {
      const parsed = new Date(value);
      if (!Number.isNaN(parsed.getTime())) return parsed;
    }
  }
  return null;
}

/**
 * Poll one archive job.
 *
 * Google's guidance is to check every 5–60 minutes; jobs can take minutes,
 * hours, or days. The scheduled poller honours that cadence.
 */
export async function getArchiveState(
  accessToken: string,
  archiveJobId: string
): Promise<ArchiveState> {
  const response = await fetch(
    `${API_BASE}/archiveJobs/${encodeURIComponent(
      archiveJobId
    )}/portabilityArchiveState`,
    { headers: { Authorization: `Bearer ${accessToken}` } }
  );

  const payload = (await response.json()) as {
    state?: string;
    urls?: string[];
    error?: { message?: string };
  };

  if (!response.ok) {
    throw new Error(
      `poll failed (${response.status}): ${
        payload.error?.message ?? 'unknown error'
      }`
    );
  }

  const state = (payload.state ?? 'IN_PROGRESS') as ImportJobState;
  return { state, urls: payload.urls ?? [] };
}

/**
 * Revoke the grant so the same resource group can be exported again.
 *
 * Google will not re-export a resource group that has already been exported
 * until authorization is reset. This is why "refresh on demand" is really
 * "refresh, then wait" — and why the app must re-prompt for consent afterwards.
 */
export async function resetAuthorization(accessToken: string): Promise<void> {
  const response = await fetch(`${API_BASE}/authorization:reset`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: '{}',
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`reset failed (${response.status}): ${text}`);
  }
}

/**
 * Download every signed URL for a completed archive and pull the starred
 * places out.
 *
 * Signed URLs expire six hours after the job completes, so this runs as soon
 * as the poller observes COMPLETE.
 */
export async function downloadStarredPlaces(
  urls: string[]
): Promise<RawPlace[]> {
  const places: RawPlace[] = [];

  for (const url of urls) {
    const response = await fetch(url);
    if (!response.ok) {
      logger.warn('Archive download failed', { status: response.status });
      continue;
    }

    const buffer = Buffer.from(await response.arrayBuffer());
    // A single-resource archive is usually a bare GeoJSON document, but Google
    // may still wrap it in a zip. Sniff the magic bytes rather than trusting
    // the content type.
    if (buffer[0] === 0x50 && buffer[1] === 0x4b) {
      const { extractStarredFromZip } = await import('./takeout');
      places.push(...extractStarredFromZip(buffer));
    } else {
      places.push(...parseStarredGeoJson(buffer.toString('utf8')));
    }
  }

  return places;
}

/**
 * Parse the `Saved Places.json` GeoJSON that carries starred places.
 *
 * This is the richest saved-place data Google exposes: unlike the Takeout
 * list CSVs, it includes real coordinates, which makes place resolution exact.
 */
export function parseStarredGeoJson(text: string): RawPlace[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    logger.warn('Starred places payload was not valid JSON');
    return [];
  }

  const features = (parsed as { features?: unknown[] })?.features;
  if (!Array.isArray(features)) return [];

  const places: RawPlace[] = [];
  for (const feature of features) {
    const f = feature as {
      geometry?: { coordinates?: unknown };
      properties?: {
        google_maps_url?: string;
        location?: { name?: string; address?: string };
      };
    };

    const coords = f.geometry?.coordinates;
    // GeoJSON is [longitude, latitude] — the reverse of how we store it.
    const lng = Array.isArray(coords) ? Number(coords[0]) : undefined;
    const lat = Array.isArray(coords) ? Number(coords[1]) : undefined;

    const name = f.properties?.location?.name?.trim();
    if (!name) continue;

    places.push({
      name,
      statuses: ['starred'],
      lists: [],
      mapsUrl: f.properties?.google_maps_url,
      address: f.properties?.location?.address,
      lat: Number.isFinite(lat) ? lat : undefined,
      lng: Number.isFinite(lng) ? lng : undefined,
    });
  }

  return places;
}
