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
const LIST_NAME_TO_STATUS: Record<string, PlaceStatus> = {
  favorite: 'loved',
  favorites: 'loved',
  favourites: 'loved',
  'want to go': 'want_to_go',
  'want to go places': 'want_to_go',
  starred: 'starred',
  'starred places': 'starred',
};

/** CSV header aliases, lowercased. Takeout's column names vary by locale. */
const TITLE_COLUMNS = ['title', 'name'];
const URL_COLUMNS = ['url', 'google maps url'];
const NOTE_COLUMNS = ['note', 'comment'];

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
  const rows = parseCsvSync(csv, {
    columns: (header: string[]) => header.map((h) => h.trim().toLowerCase()),
    skip_empty_lines: true,
    relax_column_count: true,
    bom: true,
  }) as Record<string, string>[];

  const status = LIST_NAME_TO_STATUS[listName.trim().toLowerCase()];
  const places: RawPlace[] = [];

  for (const row of rows) {
    const name = firstValue(row, TITLE_COLUMNS);
    if (!name) continue;

    const mapsUrl = firstValue(row, URL_COLUMNS);
    const coords = mapsUrl ? coordsFromMapsUrl(mapsUrl) : undefined;

    places.push({
      name,
      // A recognised list becomes a marker; anything else stays a list.
      statuses: status ? [status] : [],
      lists: status ? [] : [listName],
      mapsUrl,
      note: firstValue(row, NOTE_COLUMNS),
      lat: coords?.lat,
      lng: coords?.lng,
    });
  }

  return places;
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
