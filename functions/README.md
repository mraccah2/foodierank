# FoodieRank saved-places backend

Imports the signed-in user's Google Maps saved places into Firestore, so the
app can show a heart / blue star / green flag on places it ranks.

## Why there are two ingest paths

Google exposes **no API for writing** saved places, and only a partial one for
reading them. That constraint shapes everything here.

| Marker | Data Portability API | Takeout upload |
| --- | --- | --- |
| ⭐ Starred | ✅ `maps.starred_places` | ✅ |
| ❤️ Loved (Favorites) | ❌ no scope exists | ✅ |
| 🚩 Want to go | ❌ no scope exists | ✅ |
| 📋 Custom lists | ❌ no scope exists | ✅ |

So the API path is automated but covers one marker; the Takeout path needs the
user to upload a `.zip` but covers all four. Each source writes into its own
slice of a place (`sources.<source>` in Firestore) and the top-level
`statuses`/`lists` are the union — re-running one import never clobbers the
other's contribution.

**Clearing a marker is local to FoodieRank.** Nothing here writes back to
Google Maps, because no API permits it. The client keeps clears as tombstones
in `users/{uid}/clears/{placeId}` so a re-import cannot resurrect them.

## Functions

| Function | Trigger | Purpose |
| --- | --- | --- |
| `linkGoogleAccount` | callable | Exchanges the mobile `serverAuthCode` for a **refresh token**. Required because an archive can take days while an access token lasts an hour. |
| `unlinkGoogleAccount` | callable | Forgets the stored grant. |
| `startStarredPlacesImport` | callable | Initiates a Data Portability archive; returns a job id immediately. |
| `pollImportJobs` | every 15 min | Polls in-flight archives, downloads on `COMPLETE`, resolves and stores. |
| `resetImportAuthorization` | callable | Lets the same resource group be exported again. Revokes all scopes — the user must re-consent. |
| `onTakeoutUploaded` | Storage finalize | Parses `takeout/{uid}/*.zip`, then deletes it. |

## Firestore layout

```
users/{uid}
  savedPlaces/{placeId}   statuses[], lists[], sources{}, name, lat, lng, matchConfidence
  clears/{placeId}        statuses[]          <- client-owned, the only client write
  importJobs/{jobId}      state, placesImported, error
  private/google_oauth    refreshToken        <- rules deny all client access
```

## One-time setup

None of this can be done from code — it needs your Google Cloud / Firebase
console and a billing decision.

1. **Create the Firebase project** and enable Firestore, Storage, and
   Authentication (Google provider). Cloud Functions require the **Blaze**
   plan.
   ```bash
   firebase login
   firebase use --add          # writes .firebaserc, which is gitignored
   ```

2. **Create an OAuth client** (Web application type — the mobile
   `serverAuthCode` flow exchanges against a *web* client) in
   Google Cloud console → APIs & Services → Credentials.

3. **Enable the APIs**: Data Portability API, Places API (New).

4. **Set the secrets**:
   ```bash
   firebase functions:secrets:set GOOGLE_OAUTH_CLIENT_ID
   firebase functions:secrets:set GOOGLE_OAUTH_CLIENT_SECRET
   firebase functions:secrets:set GOOGLE_PLACES_API_KEY
   ```
   The Places key is a **server** key — restrict it by IP, not by app, since
   it is used from Cloud Functions.

5. **OAuth consent screen**: add the scope
   `https://www.googleapis.com/auth/dataportability.maps.starred_places`.

   ⚠️ This scope is classified **restricted**. Until the app passes Google's
   security assessment (third-party audit, weeks-to-months, real cost) it only
   works for accounts on the test-users list — fine for personal use, blocking
   for public release. The Takeout path has no such requirement, which is why
   it is worth having even if the API path is your primary plan.

6. **Deploy**:
   ```bash
   npm --prefix functions install
   firebase deploy --only firestore:rules,firestore:indexes,storage,functions
   ```

## Refresh cadence, honestly

"Refresh on request" is not really available from the API. Google will not
re-export a resource group until authorization is reset, and resets it
automatically only 14 days after the first initiate. Jobs themselves take
*"several minutes, several hours, or even several days."* Treat the API path as
a roughly fortnightly background sync; the Takeout upload is the path that
gives an on-demand refresh.

## Tests

```bash
npm test
```

Covers the archive parsing — list-name to marker mapping, GeoJSON coordinate
order, cross-list merging, and malformed input. Network-dependent code
(`placeResolve`, the Data Portability client) is not covered by unit tests.
