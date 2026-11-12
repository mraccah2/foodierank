import { createHash } from 'node:crypto';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { defineSecret } from 'firebase-functions/params';
import { db } from './firebase';

/**
 * Guest access for the unlisted (guest) build.
 *
 * There are no accounts. A guest types the last four digits of the phone
 * number on their reservation; if that matches a live stay running now, the
 * app unlocks until the end of checkout day.
 *
 * Stays come from the PamperHomes hub's mirror of the Hospitable calendar
 * (project `pamperhomes`, collection `reservations`), the same source the house
 * manual gate and Chelsea AC use. The mirror keeps only a first name and the
 * last four digits of each phone number, kept current by Hospitable webhooks
 * and a daily reconcile. This project's runtime service account reads it with
 * roles/datastore.viewer on `pamperhomes`.
 *
 * Six digits are the App Review code or the owner code. The owner code also
 * turns on Google sign-in in the app.
 */

/** Six digits, kept out of the (public) repo. Given to App Review in the notes. */
export const GUEST_REVIEW_CODE = defineSecret('GUEST_REVIEW_CODE');
/** Six digits for the owner: full access, Google sign-in included. Never in the repo. */
export const OWNER_CODE = defineSecret('OWNER_CODE');

const CALENDAR_PROJECT = 'pamperhomes';
const RESERVATIONS = 'reservations';

/** Same list as the hub's DEAD_STATUSES: anything else is a stay that is happening. */
const DEAD_STATUSES = new Set(['cancelled', 'canceled', 'denied', 'declined', 'expired', 'pending']);

/** How long a reviewer pass lasts before the code must be entered again. */
export const REVIEW_PASS_MS = 7 * 24 * 60 * 60 * 1000;
/** How long an owner pass lasts. */
export const OWNER_PASS_MS = 365 * 24 * 60 * 60 * 1000;

/** Failed attempts allowed per caller per window before refusing outright. */
export const MAX_FAILURES = 8;
const FAILURE_WINDOW_MS = 60 * 60 * 1000;

export interface StayWindow {
  /** Start of check-in day, at the property. */
  startsAt: number;
  /** End of checkout day, at the property. */
  endsAt: number;
}

/** The fields of a hub `reservations` document this reads. */
export interface MirroredStay {
  status?: string;
  /** ISO with the property's offset, as Hospitable sent it. */
  arrivalDate?: string;
  departureDate?: string;
  phoneLast4?: string[];
}

export function isFourDigits(code: unknown): code is string {
  return typeof code === 'string' && /^\d{4}$/.test(code);
}

/** A guest code (4 digits) or the review/owner code (6 digits). */
export function isAccessCode(code: unknown): code is string {
  return typeof code === 'string' && /^(\d{4}|\d{6})$/.test(code);
}

/**
 * Midnight-to-midnight bounds of an ISO timestamp's calendar day, in the
 * offset the timestamp was written in (the property's).
 * "2026-11-10T16:00:00-05:00" → that day 00:00 to 23:59:59.999 at -05:00.
 */
export function dayBounds(iso: string): { start: number; end: number } | null {
  const m = /^(\d{4}-\d{2}-\d{2})(?:[T ][\d:.]+)?(Z|[+-]\d{2}:?\d{2})?$/.exec(
    iso.trim()
  );
  if (!m) return null;
  let offset = m[2] ?? 'Z';
  if (/^[+-]\d{4}$/.test(offset)) offset = `${offset.slice(0, 3)}:${offset.slice(3)}`;
  const start = Date.parse(`${m[1]}T00:00:00${offset}`);
  if (Number.isNaN(start)) return null;
  return { start, end: start + 24 * 60 * 60 * 1000 - 1 };
}

/**
 * The stay a code unlocks right now, if any: a live reservation with a phone
 * ending in [code] whose check-in day has begun and checkout day has not
 * ended. When several match, the one ending last wins.
 */
export function matchStay(
  stays: MirroredStay[],
  code: string,
  now: number
): StayWindow | null {
  let best: StayWindow | null = null;
  for (const r of stays) {
    if (DEAD_STATUSES.has((r.status ?? '').toLowerCase())) continue;
    if (!(r.phoneLast4 ?? []).includes(code)) continue;
    if (!r.arrivalDate || !r.departureDate) continue;
    const a = dayBounds(r.arrivalDate);
    const d = dayBounds(r.departureDate);
    if (!a || !d) continue;
    if (now < a.start || now > d.end) continue;
    if (!best || d.end > best.endsAt) best = { startsAt: a.start, endsAt: d.end };
  }
  return best;
}

let calendarDb: FirebaseFirestore.Firestore | null = null;

function calendar(): FirebaseFirestore.Firestore {
  if (!calendarDb) {
    const app =
      getApps().find((a) => a.name === CALENDAR_PROJECT) ??
      initializeApp({ projectId: CALENDAR_PROJECT }, CALENDAR_PROJECT);
    calendarDb = getFirestore(app);
  }
  return calendarDb;
}

/** Every mirrored reservation, at any property, with a phone ending in [code]. */
export async function staysForCode(code: string): Promise<MirroredStay[]> {
  const snap = await calendar()
    .collection(RESERVATIONS)
    .where('phoneLast4', 'array-contains', code)
    .get();
  return snap.docs.map((d) => d.data() as MirroredStay);
}

function callerKey(ip: string | undefined): string {
  return createHash('sha256').update(ip || 'unknown').digest('hex').slice(0, 32);
}

/** True when this caller has used up its failed attempts for the window. */
export async function isThrottled(ip: string | undefined, now: number): Promise<boolean> {
  const snap = await db.collection('guestAttempts').doc(callerKey(ip)).get();
  const d = snap.data();
  if (!d) return false;
  const windowStart = (d.windowStart as Timestamp | undefined)?.toMillis() ?? 0;
  return now - windowStart < FAILURE_WINDOW_MS && (d.failures ?? 0) >= MAX_FAILURES;
}

export async function recordFailure(ip: string | undefined, now: number): Promise<void> {
  const ref = db.collection('guestAttempts').doc(callerKey(ip));
  await db.runTransaction(async (tx) => {
    const d = (await tx.get(ref)).data();
    const windowStart = (d?.windowStart as Timestamp | undefined)?.toMillis() ?? 0;
    const fresh = !d || now - windowStart >= FAILURE_WINDOW_MS;
    tx.set(ref, {
      windowStart: fresh ? Timestamp.fromMillis(now) : d!.windowStart,
      failures: fresh ? 1 : (d!.failures ?? 0) + 1,
    });
  });
}

export type Role = 'guest' | 'reviewer' | 'owner';

export type GuestCheck =
  | { ok: true; expiresAt: number; role: Role }
  | { ok: false };

export interface Codes {
  reviewCode: string;
  ownerCode: string;
}

const isSixDigits = (s: string) => /^\d{6}$/.test(s);

/** Resolve a code to a pass, or to nothing. Throws only if the calendar is unreadable. */
export async function checkGuestCode(
  code: string,
  now: number,
  codes: Codes,
  lookup: (code: string) => Promise<MirroredStay[]> = staysForCode
): Promise<GuestCheck> {
  if (code.length === 6) {
    const owner = codes.ownerCode.trim();
    const review = codes.reviewCode.trim();
    if (isSixDigits(owner) && code === owner) {
      return { ok: true, expiresAt: now + OWNER_PASS_MS, role: 'owner' };
    }
    if (isSixDigits(review) && code === review) {
      return { ok: true, expiresAt: now + REVIEW_PASS_MS, role: 'reviewer' };
    }
    return { ok: false };
  }
  const stay = matchStay(await lookup(code), code, now);
  if (!stay) return { ok: false };
  logger.info('Guest pass issued', { endsAt: new Date(stay.endsAt).toISOString() });
  return { ok: true, expiresAt: stay.endsAt, role: 'guest' };
}
