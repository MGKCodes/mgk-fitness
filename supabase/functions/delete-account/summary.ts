// What `core.delete_account` reports back, and what the function does about it.
//
// Its own file so the one decision in here can be tested without starting the
// server in `index.ts`.

export interface DeletionSummary {
  deleted_rows?: Record<string, number>;
  remaining_apps?: string[];
  shared_deleted?: boolean;
  photos_deleted?: boolean;
  auth_user_deletable?: boolean;
}

/// Whether the picture files in the `progress-photos` bucket must go too.
///
/// The routine removes the rows; the JPEGs are in storage, where no `delete
/// from` reaches them. They go whenever the rows went: on `photos_deleted`,
/// which a deletion that includes Lift reports, and on `shared_deleted`, which
/// is all the routine reported before it learned to say which.
///
/// **Both, on purpose.** This function is deployed before the migration that
/// adds `photos_deleted`, so for a while it runs against a routine that never
/// sends it. Reading only the new flag would stop sweeping on a full deletion
/// until the migration landed.
export function sweepsProgressPhotos(summary: DeletionSummary): boolean {
  return summary.photos_deleted === true || summary.shared_deleted === true;
}
