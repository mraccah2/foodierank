import { logger } from 'firebase-functions';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onObjectFinalized } from 'firebase-functions/v2/storage';
import { db, storage } from './firebase';
import { Timestamp } from 'firebase-admin/firestore';
import {
  ArchiveRateLimitError,
  downloadStarredPlaces,
  getArchiveState,
  initiateArchive,
  resetAuthorization,
  STARRED_PLACES_RESOURCE,
} from './dataportability';
import {
  accessTokenFor,
  exchangeAndStoreAuthCode,
  forgetGrant,
  hasStarredPlacesGrant,
  OAUTH_CLIENT_ID,
  OAUTH_CLIENT_SECRET,
  STARRED_PLACES_SCOPE,
} from './oauth';
import {
  DRIVE_READONLY_SCOPE,
  downloadArchive,
  listTakeoutArchives,
  newestExportParts,
} from './drive';
import { PLACES_API_KEY, resolvePlaces } from './placeResolve';
import { parseTakeoutArchive } from './takeout';
import {
  applyImport,
  createImportJob,
  loadResolutionCache,
  saveResolutionCache,
  updateImportJob,
} from './store';
import type { ImportJobDoc, RawPlace } from './types';

const REGION = 'us-central1';

/**
 * How long a run may spend resolving places.
 *
 * Functions here time out at 540s. Stopping at seven minutes leaves room to
 * write results and cache entries; whatever is left over resumes next tick,
 * by which point it is all cache hits.
 */
const RESOLVE_BUDGET_MS = 7 * 60 * 1000;

/**
 * Step 1 of linking: swap the mobile client's `serverAuthCode` for a refresh
 * token we can use for days, since archive jobs long outlive an access token.
 */
export const linkGoogleAccount = onCall(
  { region: REGION, secrets: [OAUTH_CLIENT_ID, OAUTH_CLIENT_SECRET] },
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    const authCode = request.data?.serverAuthCode;
    if (typeof authCode !== 'string' || !authCode) {
      throw new HttpsError('invalid-argument', 'serverAuthCode is required.');
    }

    const { scopes } = await exchangeAndStoreAuthCode(
      uid,
      authCode,
      OAUTH_CLIENT_ID.value(),
      OAUTH_CLIENT_SECRET.value()
    );
    return { linked: true, scopes };
  }
);

/** Forget the stored grant. Called when the user disconnects or signs out. */
export const unlinkGoogleAccount = onCall({ region: REGION }, async (req) => {
  await forgetGrant(requireUid(req.auth?.uid));
  return { linked: false };
});

/**
 * Step 2: kick off a Starred places export.
 *
 * Returns immediately with a job id — the archive itself may take minutes,
 * hours or days, and `pollImportJobs` finishes the work.
 */
export const startStarredPlacesImport = onCall(
  {
    region: REGION,
    secrets: [OAUTH_CLIENT_ID, OAUTH_CLIENT_SECRET],
  },
  async (request) => {
    const uid = requireUid(request.auth?.uid);

    if (!(await hasStarredPlacesGrant(uid))) {
      throw new HttpsError(
        'failed-precondition',
        'Google account is not linked with the Starred places scope.'
      );
    }

    const accessToken = await accessTokenFor(
      uid,
      OAUTH_CLIENT_ID.value(),
      OAUTH_CLIENT_SECRET.value()
    );

    const jobId = await createImportJob(uid, 'dataportability', {
      resources: [STARRED_PLACES_RESOURCE],
    });

    try {
      const archiveJobId = await initiateArchive(accessToken, [
        STARRED_PLACES_RESOURCE,
      ]);
      await updateImportJob(uid, jobId, {
        archiveJobId,
        state: 'IN_PROGRESS',
      });
      return { jobId, archiveJobId, state: 'IN_PROGRESS' };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await updateImportJob(uid, jobId, { state: 'FAILED', error: message });

      if (error instanceof ArchiveRateLimitError) {
        // Already exported inside the 24-hour window. Resetting authorization
        // would "fix" this only by revoking every scope and forcing the user
        // back through consent, so say when to come back instead.
        const when = error.retryAfter?.toISOString() ?? null;
        await db.collection('users').doc(uid).set(
          {
            nextEligibleAt: error.retryAfter
              ? Timestamp.fromDate(error.retryAfter)
              : null,
          },
          { merge: true }
        );
        throw new HttpsError('resource-exhausted', message, { retryAfter: when });
      }

      throw new HttpsError('unavailable', message);
    }
  }
);

/**
 * Allow the same resource group to be exported again.
 *
 * Google refuses to re-export a group until authorization is reset, and resets
 * it automatically 14 days after the first initiate. Resetting revokes every
 * granted scope, so the app must send the user back through consent — hence
 * the stored grant is dropped here too.
 */
export const resetImportAuthorization = onCall(
  { region: REGION, secrets: [OAUTH_CLIENT_ID, OAUTH_CLIENT_SECRET] },
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    const accessToken = await accessTokenFor(
      uid,
      OAUTH_CLIENT_ID.value(),
      OAUTH_CLIENT_SECRET.value()
    );
    await resetAuthorization(accessToken);
    await forgetGrant(uid);
    return { reset: true, mustReconsent: true };
  }
);

/**
 * Poll in-flight archive jobs.
 *
 * Google asks for a 5–60 minute cadence; 15 minutes keeps latency reasonable
 * without hammering the API. Signed download URLs expire six hours after
 * completion, comfortably longer than this interval.
 */
export const pollImportJobs = onSchedule(
  {
    region: REGION,
    schedule: 'every 15 minutes',
    secrets: [OAUTH_CLIENT_ID, OAUTH_CLIENT_SECRET, PLACES_API_KEY],
    timeoutSeconds: 540,
    memory: '512MiB',
  },
  async () => {
    const pending = await db
      .collectionGroup('importJobs')
      .where('state', '==', 'IN_PROGRESS')
      .limit(50)
      .get();

    for (const doc of pending.docs) {
      const job = doc.data() as ImportJobDoc;
      // users/{uid}/importJobs/{jobId}
      const uid = doc.ref.parent.parent?.id;
      if (!uid || !job.archiveJobId) continue;

      try {
        const accessToken = await accessTokenFor(
          uid,
          OAUTH_CLIENT_ID.value(),
          OAUTH_CLIENT_SECRET.value()
        );
        const { state, urls } = await getArchiveState(
          accessToken,
          job.archiveJobId
        );

        if (state === 'IN_PROGRESS') continue;

        if (state !== 'COMPLETE') {
          await updateImportJob(uid, doc.id, { state });
          continue;
        }

        const raw = await downloadStarredPlaces(urls);
        const cache = await loadResolutionCache(uid);
        const result = await resolvePlaces(raw, PLACES_API_KEY.value(), {
          cache,
          deadline: Date.now() + RESOLVE_BUDGET_MS,
        });
        await saveResolutionCache(uid, result.learned);

        const count = await applyImport(uid, 'dataportability', result.resolved, {
          prune: result.complete,
        });

        await updateImportJob(uid, doc.id, {
          state: result.complete ? 'COMPLETE' : 'IN_PROGRESS',
          placesImported: count,
        });
        logger.info('Starred places import', {
          uid,
          count,
          complete: result.complete,
          lookups: result.lookups,
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        logger.error('Import job failed', { uid, jobId: doc.id, message });
        await updateImportJob(uid, doc.id, {
          state: 'FAILED',
          error: message,
        });
      }
    }
  }
);

/**
 * Keep Starred places fresh with no user involvement.
 *
 * When the user grants *time-based* access (the 30- or 180-day option on the
 * consent screen) Google permits one export per resource group per 24 hours.
 * That makes a genuine background sync possible: everyone who has linked their
 * account gets re-exported daily until their grant lapses, with no prompting.
 *
 * One-time grants simply fail the initiate call once and then sit idle, which
 * is the correct behaviour — there is nothing to refresh.
 *
 * Runs more often than daily so a user whose window opens mid-cycle waits hours
 * rather than a full extra day; `nextEligibleAt` is what actually gates work.
 */
export const autoSyncStarredPlaces = onSchedule(
  {
    region: REGION,
    schedule: 'every 6 hours',
    secrets: [OAUTH_CLIENT_ID, OAUTH_CLIENT_SECRET],
    timeoutSeconds: 540,
  },
  async () => {
    // Select on the granted scope, not merely on holding a refresh token: a
    // user who connected only Drive has a token but no Data Portability
    // access, and initiating an archive for them would fail every cycle.
    const grants = await db
      .collectionGroup('private')
      .where('scopes', 'array-contains', STARRED_PLACES_SCOPE)
      .limit(200)
      .get();

    for (const grant of grants.docs) {
      const uid = grant.ref.parent.parent?.id;
      if (!uid) continue;

      try {
        const userRef = db.collection('users').doc(uid);
        const user = (await userRef.get()).data() ?? {};

        const nextEligible = (user.nextEligibleAt as Timestamp | undefined)
          ?.toDate();
        if (nextEligible && nextEligible > new Date()) continue;

        // Never stack a second archive on top of one still building.
        const running = await userRef
          .collection('importJobs')
          .where('state', '==', 'IN_PROGRESS')
          .limit(1)
          .get();
        if (!running.empty) continue;

        const accessToken = await accessTokenFor(
          uid,
          OAUTH_CLIENT_ID.value(),
          OAUTH_CLIENT_SECRET.value()
        );

        const jobId = await createImportJob(uid, 'dataportability', {
          resources: [STARRED_PLACES_RESOURCE],
        });

        const archiveJobId = await initiateArchive(accessToken, [
          STARRED_PLACES_RESOURCE,
        ]);
        await updateImportJob(uid, jobId, {
          archiveJobId,
          state: 'IN_PROGRESS',
        });
        logger.info('Auto-sync initiated', { uid, archiveJobId });
      } catch (error) {
        if (error instanceof ArchiveRateLimitError) {
          // Expected on a one-time grant, or if something already synced
          // today. Park until Google says we may try again.
          await db
            .collection('users')
            .doc(uid)
            .set(
              {
                nextEligibleAt: error.retryAfter
                  ? Timestamp.fromDate(error.retryAfter)
                  : Timestamp.fromDate(
                      new Date(Date.now() + 24 * 60 * 60 * 1000)
                    ),
              },
              { merge: true }
            );
          continue;
        }
        logger.warn('Auto-sync skipped', {
          uid,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }
  }
);

/**
 * Pick up Takeout archives that land in the user's Drive.
 *
 * Takeout can be told to deliver on a schedule — every 2 months, six times
 * over a year — straight to Drive. That is the only way Loved, Want to go and
 * custom lists refresh without the user doing anything: no Google API exposes
 * them, and there is no API to create the Takeout schedule either, so the user
 * arms it once a year in the Takeout UI.
 *
 * Only runs for users who explicitly connected Drive; the scope is never part
 * of ordinary sign-in.
 */
export const syncTakeoutFromDrive = onSchedule(
  {
    region: REGION,
    schedule: 'every 12 hours',
    secrets: [OAUTH_CLIENT_ID, OAUTH_CLIENT_SECRET, PLACES_API_KEY],
    timeoutSeconds: 540,
    memory: '2GiB',
  },
  async () => {
    const grants = await db
      .collectionGroup('private')
      .where('scopes', 'array-contains', DRIVE_READONLY_SCOPE)
      .limit(200)
      .get();

    for (const grant of grants.docs) {
      const uid = grant.ref.parent.parent?.id;
      if (!uid) continue;

      try {
        const accessToken = await accessTokenFor(
          uid,
          OAUTH_CLIENT_ID.value(),
          OAUTH_CLIENT_SECRET.value()
        );

        const archives = await listTakeoutArchives(accessToken);
        if (archives.length === 0) {
          logger.info('No Takeout archives in Drive', { uid });
          continue;
        }

        // Take every part of the newest export, not just the newest file —
        // Takeout spreads one export across several zips and the Maps data can
        // sit in any of them. Older exports are ignored: each export is a full
        // snapshot, so re-importing one would only restore stale data.
        const newest = newestExportParts(archives);
        if (!newest) continue;

        const stateRef = db
          .collection('users')
          .doc(uid)
          .collection('private')
          .doc('drive_state');
        const seen = (await stateRef.get()).data()?.lastExportKey as
          | string
          | undefined;
        if (seen === newest.key) continue;

        const jobId = await createImportJob(uid, 'takeout', {
          state: 'IN_PROGRESS',
        });

        const places: RawPlace[] = [];
        const listsFound: string[] = [];
        const skippedParts: string[] = [];

        for (const part of newest.parts) {
          const buffer = await downloadArchive(accessToken, part);
          if (!buffer) {
            skippedParts.push(part.name);
            continue;
          }
          const parsed = parseTakeoutArchive(buffer);
          places.push(...parsed.places);
          listsFound.push(...parsed.listsFound);
          logger.info('Parsed Takeout part', {
            uid,
            part: part.name,
            places: parsed.places.length,
          });
        }

        if (places.length === 0) {
          await updateImportJob(uid, jobId, {
            state: 'FAILED',
            error:
              `No saved places across ${newest.parts.length} archive part(s). ` +
              'Include "Maps (your places)" in the Takeout export.',
          });
          await stateRef.set({ lastExportKey: newest.key }, { merge: true });
          continue;
        }

        if (skippedParts.length > 0) {
          logger.warn('Some export parts were skipped', { uid, skippedParts });
        }

        const cache = await loadResolutionCache(uid);
        const result = await resolvePlaces(places, PLACES_API_KEY.value(), {
          cache,
          deadline: Date.now() + RESOLVE_BUDGET_MS,
        });
        await saveResolutionCache(uid, result.learned);

        const count = await applyImport(uid, 'takeout', result.resolved, {
          prune: result.complete,
        });

        // Only mark the export done when it was fully processed; otherwise the
        // next run picks up where this one stopped, and everything already
        // resolved is a cache hit.
        if (result.complete) {
          await stateRef.set({ lastExportKey: newest.key }, { merge: true });
        }

        await updateImportJob(uid, jobId, {
          state: 'COMPLETE',
          partial: !result.complete,
          placesImported: count,
        });

        logger.info('Drive Takeout import', {
          uid,
          count,
          complete: result.complete,
          lookups: result.lookups,
          cached: cache.size,
          listsFound: [...new Set(listsFound)],
          export: newest.key,
        });
      } catch (error) {
        logger.warn('Drive sync skipped', {
          uid,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }
  }
);

/**
 * Ingest a Takeout archive uploaded from the phone.
 *
 * This is the only path that yields Loved, Want to go and custom lists, since
 * the Data Portability API has no scope for any of them. The upload lands at
 * `takeout/{uid}/{file}.zip`, and is deleted once parsed.
 */
export const onTakeoutUploaded = onObjectFinalized(
  {
    region: REGION,
    secrets: [PLACES_API_KEY],
    timeoutSeconds: 540,
    memory: '2GiB',
  },
  async (event) => {
    const path = event.data.name;
    const match = path?.match(/^takeout\/([^/]+)\/(.+)$/);
    if (!match) return;

    const uid = match[1];
    const jobId = await createImportJob(uid, 'takeout', {
      state: 'IN_PROGRESS',
    });
    const file = storage.bucket(event.data.bucket).file(path);

    try {
      const [buffer] = await file.download();
      const { places, listsFound, skipped } = parseTakeoutArchive(buffer);

      if (places.length === 0) {
        throw new Error(
          'No saved places found. Export "Maps (your places)" from Takeout ' +
            'and upload that .zip.'
        );
      }

      const cache = await loadResolutionCache(uid);
      const result = await resolvePlaces(places, PLACES_API_KEY.value(), {
        cache,
        deadline: Date.now() + RESOLVE_BUDGET_MS,
      });
      await saveResolutionCache(uid, result.learned);

      const count = await applyImport(uid, 'takeout', result.resolved, {
        prune: result.complete,
      });

      await updateImportJob(uid, jobId, {
        state: 'COMPLETE',
        partial: !result.complete,
        placesImported: count,
      });
      logger.info('Takeout upload import', {
        uid,
        count,
        complete: result.complete,
        lookups: result.lookups,
        listsFound,
        skipped: skipped.length,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.error('Takeout import failed', { uid, message });
      await updateImportJob(uid, jobId, { state: 'FAILED', error: message });
    } finally {
      // The archive holds a lot of personal data; do not keep it around.
      await file.delete().catch(() => undefined);
    }
  }
);

function requireUid(uid: string | undefined): string {
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Sign in first.');
  }
  return uid;
}
