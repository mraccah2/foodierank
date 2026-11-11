import { getAuth } from 'firebase-admin/auth';
import { logger } from 'firebase-functions';
import { db, storage } from './firebase';

const REVOKE_ENDPOINT = 'https://oauth2.googleapis.com/revoke';

/**
 * The Storage prefix holding a user's uploaded Takeout archives.
 *
 * Validated hard because the result feeds a prefix delete: an empty or
 * slash-bearing uid would widen it to other users' files.
 */
export function takeoutPrefix(uid: string): string {
  if (typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) {
    throw new Error(`Refusing to build a storage prefix for uid "${uid}"`);
  }
  return `takeout/${uid}/`;
}

/**
 * Delete everything FoodieRank holds about a user, then the user.
 *
 * Order matters: the Google grant is revoked first, while the refresh token is
 * still on file, and the auth account goes last so a partial failure can be
 * retried by the same signed-in user.
 *
 *  1. Revoke the stored Google refresh token (best effort — a token the user
 *     already revoked in their Google account answers 400, which is fine).
 *  2. Delete any Takeout archives still waiting in Storage.
 *  3. Recursively delete `users/{uid}`: saved places, marks, clears, import
 *     jobs, the resolution cache and `private/` (tokens, Drive state).
 *  4. Delete the Firebase Auth user. Done with the Admin SDK, so it never
 *     fails with `requires-recent-login` the way a client-side delete can.
 */
export async function deleteUserAndData(uid: string): Promise<void> {
  const prefix = takeoutPrefix(uid);
  const userRef = db.collection('users').doc(uid);

  const token = await userRef.collection('private').doc('google_oauth').get();
  const refreshToken = token.data()?.refreshToken as string | undefined;
  if (refreshToken) {
    try {
      const response = await fetch(REVOKE_ENDPOINT, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ token: refreshToken }),
      });
      if (!response.ok) {
        logger.info('Token revoke returned non-OK (already revoked?)', {
          uid,
          status: response.status,
        });
      }
    } catch (error) {
      logger.warn('Token revoke failed; deleting anyway', {
        uid,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  await storage.bucket().deleteFiles({ prefix, force: true });

  await db.recursiveDelete(userRef);

  try {
    await getAuth().deleteUser(uid);
  } catch (error) {
    // Already gone (e.g. a retry after a dropped response) is success.
    if ((error as { code?: string }).code !== 'auth/user-not-found') throw error;
  }

  logger.info('Account deleted', { uid });
}
