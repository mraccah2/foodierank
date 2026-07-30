/**
 * Marker keys. These strings are a wire contract with the Flutter client —
 * they must stay identical to `PlaceStatusDisplay.storageKey` in
 * `lib/models/place_status.dart`.
 */
export type PlaceStatus = 'loved' | 'starred' | 'want_to_go';

export const ALL_STATUSES: readonly PlaceStatus[] = [
  'loved',
  'starred',
  'want_to_go',
];

/**
 * Where a marker came from. Each source owns its own slice of a place's
 * markers so re-running one import cannot clobber the other's contribution.
 *
 * - `dataportability` — the Data Portability API. Supplies *only* starred
 *   places; Google exposes no scope for the other markers or for lists.
 * - `takeout` — a Takeout archive the user uploaded from their phone. The
 *   only source for Loved, Want to go and custom lists.
 */
export type ImportSource = 'dataportability' | 'takeout';

/** One place as extracted from an import, before it has a `place_id`. */
export interface RawPlace {
  name: string;
  statuses: PlaceStatus[];
  lists: string[];
  mapsUrl?: string;
  lat?: number;
  lng?: number;
  address?: string;
  note?: string;
}

/** A place once resolved to a Google `place_id`, ready to store. */
export interface ResolvedPlace extends RawPlace {
  placeId: string;
  /**
   * How much to trust the match.
   * - `exact`   — coordinates came from the archive and the text search hit
   *               within {@link COORD_MATCH_RADIUS_M}.
   * - `likely`  — name matched with a location bias.
   * - `weak`    — name-only match, no coordinates to check against. Takeout
   *               CSVs carry no coordinates, so most list entries land here.
   */
  matchConfidence: 'exact' | 'likely' | 'weak';
}

export interface SavedPlaceDoc {
  /** Union of every source's markers. What the client renders. */
  statuses: PlaceStatus[];
  /** Union of every source's list names. */
  lists: string[];
  /** Per-source contributions, so one import can be replaced independently. */
  sources: Partial<
    Record<ImportSource, { statuses: PlaceStatus[]; lists: string[] }>
  >;
  name: string;
  mapsUrl?: string;
  lat?: number;
  lng?: number;
  address?: string;
  matchConfidence: ResolvedPlace['matchConfidence'];
  updatedAt: FirebaseFirestore.Timestamp | FirebaseFirestore.FieldValue;
}

export type ImportJobState =
  | 'PENDING'
  | 'IN_PROGRESS'
  | 'COMPLETE'
  | 'FAILED'
  | 'CANCELLED';

export interface ImportJobDoc {
  source: ImportSource;
  state: ImportJobState;
  /** Data Portability archive job id. Absent for Takeout uploads. */
  archiveJobId?: string;
  resources?: string[];
  placesImported?: number;
  /**
   * True when the run stopped at its deadline with entries still unresolved.
   * The next run continues, and everything already done is a cache hit.
   */
  partial?: boolean;
  error?: string;
  createdAt: FirebaseFirestore.Timestamp | FirebaseFirestore.FieldValue;
  updatedAt: FirebaseFirestore.Timestamp | FirebaseFirestore.FieldValue;
}
