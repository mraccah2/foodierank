import { logger } from 'firebase-functions';

const FILES_API = 'https://www.googleapis.com/drive/v3/files';

/**
 * Read access to the user's Drive, needed to pick up Takeout archives that
 * Takeout's scheduled export drops there.
 *
 * This is a **restricted** scope granting read of the user's *entire* Drive.
 * There is no narrower option: `drive.file` only exposes files this app itself
 * created, and Takeout's archives are created by Google. Ask for it only when
 * the user opts into Drive-based import — never as part of sign-in.
 */
export const DRIVE_READONLY_SCOPE =
  'https://www.googleapis.com/auth/drive.readonly';

/**
 * Archives above this are skipped rather than downloaded.
 *
 * A Maps-only export is kilobytes-to-megabytes. Anything at this scale means
 * the user exported far more than Maps, and pulling it into a function would
 * blow the memory limit for data we would discard anyway.
 */
const MAX_ARCHIVE_BYTES = 512 * 1024 * 1024;

export interface DriveArchive {
  id: string;
  name: string;
  size: number;
  createdTime: string;
}

/**
 * Find Takeout archives in the user's Drive, newest first.
 *
 * Takeout names its output `takeout-<timestamp>-<part>.zip`, so the query
 * filters on that prefix rather than listing the whole Drive.
 */
export async function listTakeoutArchives(
  accessToken: string
): Promise<DriveArchive[]> {
  // Deliberately loose. Drive reports zip uploads inconsistently — sometimes
  // application/zip, sometimes x-zip-compressed or octet-stream — so filtering
  // on mimeType server-side silently returned nothing. Match on the name and
  // sort the extension out here, where it can be logged.
  const query = ["name contains 'takeout'", 'trashed = false'].join(' and ');

  const url =
    `${FILES_API}?q=${encodeURIComponent(query)}` +
    '&fields=files(id,name,size,createdTime,mimeType)' +
    '&orderBy=createdTime desc&pageSize=50' +
    // Takeout may deposit archives in a shared drive rather than My Drive.
    '&supportsAllDrives=true&includeItemsFromAllDrives=true';

  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });

  const payload = (await response.json()) as {
    files?: {
      id: string;
      name: string;
      size?: string;
      createdTime?: string;
      mimeType?: string;
    }[];
    error?: { message?: string };
  };

  if (!response.ok) {
    throw new Error(
      `Drive list failed (${response.status}): ${
        payload.error?.message ?? 'unknown error'
      }`
    );
  }

  const all = payload.files ?? [];
  const archives = all
    .filter((f) => f.name.toLowerCase().endsWith('.zip'))
    .map((f) => ({
      id: f.id,
      name: f.name,
      size: Number(f.size ?? 0),
      createdTime: f.createdTime ?? '',
    }));

  // Without this, "found nothing" and "worked fine" look identical in the
  // logs — which is exactly how the first run was impossible to diagnose.
  logger.info('Drive scan', {
    matchedName: all.length,
    zipArchives: archives.length,
    names: all.slice(0, 10).map((f) => `${f.name} (${f.mimeType})`),
  });

  return archives;
}

/**
 * Group archives into exports and return every part of the most recent one.
 *
 * Takeout splits a single export across several zips —
 * `takeout-20260723T215440Z-001.zip`, `takeout-20260723T215440Z-2-001.zip` —
 * and spreads the data between them, so "Maps (your places)" may live in any
 * part. Reading only the newest *file* is how the first run came back empty:
 * it picked part 1, which happened to hold none of the Maps data.
 *
 * The shared `takeout-<timestamp>` prefix identifies the export; anything that
 * does not match it is treated as its own single-part export.
 */
export function newestExportParts(archives: DriveArchive[]): {
  key: string;
  parts: DriveArchive[];
} | null {
  if (archives.length === 0) return null;

  const keyOf = (name: string) =>
    name.match(/takeout-(\d{8}T\d{6}Z)/i)?.[1] ?? name;

  const groups = new Map<string, DriveArchive[]>();
  for (const archive of archives) {
    const key = keyOf(archive.name);
    (groups.get(key) ?? groups.set(key, []).get(key)!).push(archive);
  }

  // `archives` arrives newest-first, so the first key encountered is newest.
  const key = keyOf(archives[0].name);
  return { key, parts: groups.get(key) ?? [archives[0]] };
}

/** Download one archive. Returns null when it is implausibly large. */
export async function downloadArchive(
  accessToken: string,
  archive: DriveArchive
): Promise<Buffer | null> {
  if (archive.size > MAX_ARCHIVE_BYTES) {
    logger.warn('Skipping oversized Takeout archive', {
      name: archive.name,
      size: archive.size,
    });
    return null;
  }

  const response = await fetch(
    `${FILES_API}/${encodeURIComponent(archive.id)}?alt=media`,
    { headers: { Authorization: `Bearer ${accessToken}` } }
  );

  if (!response.ok) {
    throw new Error(`Drive download failed (${response.status})`);
  }

  return Buffer.from(await response.arrayBuffer());
}
