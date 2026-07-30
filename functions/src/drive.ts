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
  const query = [
    "name contains 'takeout'",
    "mimeType = 'application/zip'",
    'trashed = false',
  ].join(' and ');

  const url =
    `${FILES_API}?q=${encodeURIComponent(query)}` +
    '&fields=files(id,name,size,createdTime)' +
    '&orderBy=createdTime desc&pageSize=25';

  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });

  const payload = (await response.json()) as {
    files?: { id: string; name: string; size?: string; createdTime?: string }[];
    error?: { message?: string };
  };

  if (!response.ok) {
    throw new Error(
      `Drive list failed (${response.status}): ${
        payload.error?.message ?? 'unknown error'
      }`
    );
  }

  return (payload.files ?? []).map((f) => ({
    id: f.id,
    name: f.name,
    size: Number(f.size ?? 0),
    createdTime: f.createdTime ?? '',
  }));
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
