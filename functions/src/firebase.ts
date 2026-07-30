import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';

// Functions files import this module rather than initialising the app
// themselves, so repeated cold-start imports cannot double-initialise.
if (getApps().length === 0) {
  initializeApp();
}

export const db = getFirestore();
export const storage = getStorage();
