import AdmZip from 'adm-zip';
import { parse as parseCsvSync } from 'csv-parse/sync';
import { logger } from 'firebase-functions';
import { parseStarredGeoJson } from './dataportability';
import type { PlaceStatus, RawPlace } from './types';

/**
 * Google Takeout is the only source for Loved, Want to go, and custom lists —
 * the Data Portability API has no scope for any of them.
 *
 * Inside the archive, `Takeout/Maps (your places)/Saved/` (localised) holds one
 * CSV per list. Two list names are special-cased onto markers; anything else is
 * a user-created list such as "Iceland trip".
 */
/**
 * The only lists FoodieRank imports.
 *
 * Google exports every list a user owns — "Parked car", "Images", "Airbnbs",
 * trip plans — but only these three map to a marker the app renders, so the
 * rest are skipped rather than resolved. That is a large saving: this account's
 * export held 2362 entries across 22 lists, of which only these matter.
 *
 * Real exports name the favourites list "Favorite places", not "Favorites" —
 * getting this wrong silently demotes every heart to an ordinary list.
 */
const LIST_NAME_TO_STATUS: Record<string, PlaceStatus> = {
  favorite: 'loved',
  favorites: 'loved',
  favourites: 'loved',
  'favorite places': 'loved',
  'favourite places': 'loved',
  'want to go': 'want_to_go',
  'want to go places': 'want_to_go',
  starred: 'starred',
  'starred places': 'starred',
};

/** The marker a list maps to, or null when the list should be ignored. */
export function statusForList(listName: string): PlaceStatus | null {
  return LIST_NAME_TO_STATUS[listName.trim().toLowerCase()] ?? null;
}

/** CSV header aliases, lowercased. Takeout's column names vary by locale. */
const TITLE_COLUMNS = ['title', 'name'];
const URL_COLUMNS = ['url', 'google maps url'];
const NOTE_COLUMNS = ['note', 'comment'];
const TAG_COLUMNS = ['tags', 'tag'];

export interface TakeoutParseResult {
  places: RawPlace[];
  /** Names of every list found, for reporting back to the app. */
  listsFound: string[];
  /** Files we recognised but could not read, for diagnostics. */
  skipped: string[];
}

/** Pull every saved place out of a Takeout zip. */
export function parseTakeoutArchive(buffer: Buffer): TakeoutParseResult {
  const zip = new AdmZip(buffer);
  const byPlace = new Map<string, RawPlace>();
  const listsFound: string[] = [];
  const skipped: string[] = [];

  for (const entry of zip.getEntries()) {
    if (entry.isDirectory) continue;
    const path = entry.entryName;

    try {
      if (isSavedListCsv(path)) {
        const listName = listNameFromPath(path);
        listsFound.push(listName);

        // Only the three marker lists are imported. Skipping the rest before
        // reading them avoids resolving thousands of places the app can never
        // display — parked cars, apartments, trip plans.
        if (!statusForList(listName)) {
          skipped.push(listName);
          continue;
        }

        for (const place of parseSavedListCsv(
          entry.getData().toString('utf8'),
          listName
        )) {
          mergeInto(byPlace, place);
        }
      } else if (isStarredGeoJson(path)) {
        for (const place of parseStarredGeoJson(
          entry.getData().toString('utf8')
        )) {
          mergeInto(byPlace, place);
        }
      }
    } catch (error) {
      logger.warn('Could not parse Takeout entry', { path, error });
      skipped.push(path);
    }
  }

  return { places: [...byPlace.values()], listsFound, skipped };
}

/** Used when a Data Portability archive arrives zipped rather than bare. */
export function extractStarredFromZip(buffer: Buffer): RawPlace[] {
  const zip = new AdmZip(buffer);
  const places: RawPlace[] = [];
  for (const entry of zip.getEntries()) {
    if (entry.isDirectory) continue;
    if (!entry.entryName.toLowerCase().endsWith('.json')) continue;
    places.push(...parseStarredGeoJson(entry.getData().toString('utf8')));
  }
  return places;
}

function isSavedListCsv(path: string): boolean {
  const lower = path.toLowerCase();
  return lower.endsWith('.csv') && lower.includes('/saved/');
}

function isStarredGeoJson(path: string): boolean {
  const lower = path.toLowerCase();
  return (
    lower.endsWith('.json') &&
    (lower.includes('saved places') || lower.includes('starred'))
  );
}

/** `Takeout/Maps (your places)/Saved/Iceland trip.csv` → `Iceland trip`. */
function listNameFromPath(path: string): string {
  const file = path.split('/').pop() ?? path;
  return file.replace(/\.csv$/i, '').trim();
}

/**
 * Parse one list CSV.
 *
 * These carry only Title, Note, URL and Comment — **no coordinates**. That is
 * why places from here resolve by name and usually land at `weak` confidence.
 */
export function parseSavedListCsv(
  csv: string,
  listName: string
): RawPlace[] {
  let headers: string[] = [];
  const rows = parseCsvSync(stripPreamble(csv), {
    columns: (header: string[]) => {
      headers = header.map((h) => h.trim());
      return headers.map((h) => h.toLowerCase());
    },
    skip_empty_lines: true,
    relax_column_count: true,
    bom: true,
  }) as Record<string, string>[];

  // Ground truth about what Takeout actually hands us, rather than what the
  // docs claim. Column names vary by locale and have changed over time, and a
  // silently-unmatched column is indistinguishable from an empty list.
  logger.info('Takeout list columns', {
    list: listName,
    headers,
    rows: rows.length,
    sample: rows[0]
      ? Object.fromEntries(
          Object.entries(rows[0]).map(([k, v]) => [k, String(v).slice(0, 120)])
        )
      : null,
  });

  const status = statusForList(listName);
  if (!status) return [];

  const places: RawPlace[] = [];

  for (const row of rows) {
    const name = firstValue(row, TITLE_COLUMNS);
    if (!name) continue;

    const mapsUrl = firstValue(row, URL_COLUMNS);
    const coords = mapsUrl ? coordsFromMapsUrl(mapsUrl) : undefined;

    // Real exports carry a Tags column alongside Note and Comment. Fold
    // whichever are populated into one note rather than dropping them.
    const note = [
      firstValue(row, NOTE_COLUMNS),
      firstValue(row, TAG_COLUMNS),
    ]
      .filter(Boolean)
      .join(' · ');

    places.push({
      name,
      statuses: [status],
      lists: [],
      mapsUrl,
      note: note || undefined,
      lat: coords?.lat,
      lng: coords?.lng,
    });
  }

  return places;
}

/**
 * Drop anything above the real header row.
 *
 * Some list exports carry a free-text description first — an "Iceland Trip"
 * list began with "Aakash & Omri's Iceland Plan" — which the CSV parser
 * otherwise adopts as the column names, silently mapping every field wrong.
 * Scan for the line that actually looks like Takeout's header and start there.
 */
export function stripPreamble(csv: string): string {
  const lines = csv.split(/\r?\n/);
  const headerIndex = lines.findIndex((line) => {
    const cells = line.toLowerCase().split(',').map((c) => c.trim().replace(/^"|"$/g, ''));
    return cells.includes('title') && (cells.includes('url') || cells.includes('note'));
  });

  // No recognisable header: hand back the original and let the caller's
  // title-required check discard the rows rather than inventing structure.
  if (headerIndex <= 0) return csv;
  return lines.slice(headerIndex).join('\n');
}

function firstValue(
  row: Record<string, string>,
  keys: string[]
): string | undefined {
  for (const key of keys) {
    const value = row[key]?.trim();
    if (value) return value;
  }
  return undefined;
}

/**
 * Best-effort coordinate extraction from a Google Maps URL.
 *
 * Many saved URLs embed the location as `@lat,lng,zoom` or as `!3dLAT!4dLNG`.
 * When present this upgrades an otherwise name-only match to a checked one, so
 * it is worth attempting even though plenty of URLs carry neither.
 */
export function coordsFromMapsUrl(
  url: string
): { lat: number; lng: number } | undefined {
  const at = url.match(/@(-?\d+\.\d+),(-?\d+\.\d+)/);
  if (at) {
    return { lat: Number(at[1]), lng: Number(at[2]) };
  }

  const bang = url.match(/!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/);
  if (bang) {
    return { lat: Number(bang[1]), lng: Number(bang[2]) };
  }

  return undefined;
}

/**
 * Fold a place into the accumulator, keyed by Maps URL when we have one and by
 * name otherwise. A place can appear in several lists — "Iceland trip" *and*
 * Favorites — and must end up as one record carrying both.
 */
function mergeInto(target: Map<string, RawPlace>, place: RawPlace): void {
  const key = (place.mapsUrl ?? place.name).toLowerCase();
  const existing = target.get(key);

  if (!existing) {
    target.set(key, { ...place });
    return;
  }

  existing.statuses = unique([...existing.statuses, ...place.statuses]);
  existing.lists = unique([...existing.lists, ...place.lists]);
  // Prefer whichever record actually carries coordinates.
  existing.lat ??= place.lat;
  existing.lng ??= place.lng;
  existing.address ??= place.address;
  existing.note ??= place.note;
}

function unique<T>(values: T[]): T[] {
  return [...new Set(values)];
}
