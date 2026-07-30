import { defineSecret } from 'firebase-functions/params';
import { HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';
import { db } from './firebase';

export const OAUTH_CLIENT_ID = defineSecret('GOOGLE_OAUTH_CLIENT_ID');
export const OAUTH_CLIENT_SECRET = defineSecret('GOOGLE_OAUTH_CLIENT_SECRET');

/**
 * The Data Portability scope for Starred places.
 *
 * This is the *only* Maps saved-place scope Google offers. There is no scope
 * for Favorites ("Loved"), Want to go, or custom lists — those can only reach
 * us through a Takeout upload. See `takeout.ts`.
 *
 * It is classified `restricted`, so the OAuth client must pass Google's
 * security assessment before it works for users outside the test list.
 */
export const STARRED_PLACES_SCOPE =
  'https://www.googleapis.com/auth/dataportability.maps.starred_places';

const TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token';

/**
 * Where a user's refresh token lives. Firestore rules deny all client access
 * to `users/{uid}/private/**`; only the Admin SDK reads this.
 */
const tokenRef = (uid: string) =>
  db.collection('users').doc(uid).collection('private').doc('google_oauth');

interface StoredToken {
  refreshToken: string;
  scopes: string[];
  updatedAt: FirebaseFirestore.FieldValue;
}

/**
 * Trade the `serverAuthCode` from the mobile Google Sign-In flow for a refresh
 * token, and store it.
 *
 * A refresh token — not the access token the client already holds — is what
 * makes this work at all: a Data Portability archive can take *days*, far
 * outliving the one-hour access token, and the polling job runs with no user
 * present.
 */
export async function exchangeAndStoreAuthCode(
  uid: string,
  authCode: string,
  clientId: string,
  clientSecret: string
): Promise<{ scopes: string[] }> {
  const body = new URLSearchParams({
    code: authCode,
    client_id: clientId,
    client_secret: clientSecret,
    grant_type: 'authorization_code',
    // Mobile clients exchanging a serverAuthCode use the empty redirect URI.
    redirect_uri: '',
  });

  const response = await fetch(TOKEN_ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });

  const payload = (await response.json()) as {
    refresh_token?: string;
    scope?: string;
    error?: string;
    error_description?: string;
  };

  if (!response.ok) {
    logger.error('Auth code exchange failed', {
      uid,
      error: payload.error,
      description: payload.error_description,
    });
    throw new HttpsError(
      'permission-denied',
      `Could not exchange auth code: ${payload.error ?? response.status}`
    );
  }

  if (!payload.refresh_token) {
    // Google only returns a refresh token when offline access is requested and
    // the user has not already granted it. The client must re-consent.
    throw new HttpsError(
      'failed-precondition',
      'Google returned no refresh token. Request offline access and force ' +
        'the consent prompt, then try again.'
    );
  }

  const granted = (payload.scope ?? '').split(' ').filter(Boolean);

  // Union with what is already on file. Each consent returns only its own
  // scopes, so overwriting here would make connecting Drive look like it had
  // revoked the Data Portability grant (or vice versa).
  const existing =
    ((await tokenRef(uid).get()).data() as StoredToken | undefined)?.scopes ??
    [];
  const scopes = [...new Set([...existing, ...granted])];

  const doc: StoredToken = {
    refreshToken: payload.refresh_token,
    scopes,
    updatedAt: new Date() as unknown as FirebaseFirestore.FieldValue,
  };
  await tokenRef(uid).set(doc, { merge: true });

  return { scopes };
}

/** True when we hold a refresh token carrying the Data Portability scope. */
export async function hasStarredPlacesGrant(uid: string): Promise<boolean> {
  return hasScope(uid, STARRED_PLACES_SCOPE);
}

/** True when the stored grant carries [scope]. */
export async function hasScope(uid: string, scope: string): Promise<boolean> {
  const snap = await tokenRef(uid).get();
  const data = snap.data() as StoredToken | undefined;
  return !!data?.refreshToken && data.scopes.includes(scope);
}


/**
 * Mint a fresh access token for `uid`. Throws if the user has not linked their
 * Google account, or if the grant has been revoked.
 */
export async function accessTokenFor(
  uid: string,
  clientId: string,
  clientSecret: string
): Promise<string> {
  const snap = await tokenRef(uid).get();
  const stored = snap.data() as StoredToken | undefined;
  if (!stored?.refreshToken) {
    throw new HttpsError(
      'failed-precondition',
      'No Google authorization on file. Connect the account first.'
    );
  }

  const response = await fetch(TOKEN_ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      refresh_token: stored.refreshToken,
      grant_type: 'refresh_token',
    }),
  });

  const payload = (await response.json()) as {
    access_token?: string;
    error?: string;
  };

  if (!response.ok || !payload.access_token) {
    // invalid_grant means the user revoked access (or Data Portability's
    // automatic 14-day reset fired). Drop the dead token so the app can
    // prompt for a fresh grant instead of retrying forever.
    if (payload.error === 'invalid_grant') {
      await tokenRef(uid).delete().catch(() => undefined);
    }
    throw new HttpsError(
      'permission-denied',
      `Could not refresh Google access: ${payload.error ?? response.status}`
    );
  }

  return payload.access_token;
}

/** Forget a user's stored grant (used after resetAuthorization, and on unlink). */
export async function forgetGrant(uid: string): Promise<void> {
  await tokenRef(uid).delete().catch(() => undefined);
}
