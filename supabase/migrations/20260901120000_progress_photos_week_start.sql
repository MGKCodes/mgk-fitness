-- Progress photos: the week a photo belongs to, as its own column.
--
-- `core.progress_photos` came from Liftio with one timestamp, `date`, meaning
-- when the photo was taken. Lift needs two things from a photo and they are not
-- the same:
--
--   takenAt    when the shutter went. Metadata.
--   weekStart  Monday 00:00 of the week it is filed under. **Identity.**
--
-- The whole feature is one slot per (week, pose) — retaking replaces, and a
-- playback is one frame per week. So `weekStart` is what makes two rows the same
-- photo, and deriving it from `date` on the way back down would be a guess.
--
-- It is a guess in a specific and unfixable way: Monday-of-the-week depends on
-- the timezone the lifter was standing in, and the server does not know it. A
-- photo taken at 00:30 on Monday in Sydney is the previous week in London. A
-- backfill here would silently refile photos for anybody who has travelled, and
-- the failure would look like a photo moving weeks rather than like a bug.
--
-- Hence: nullable, no backfill, and **the client derives it when null**.
-- `ProgressPhoto.weekOf(takenAt)` runs on the device, in the device's zone,
-- which is the only place the answer exists. Rows written by this app carry it
-- explicitly; the 2024-25 Liftio rows do not and are derived on read.

alter table core.progress_photos
  add column if not exists week_start bigint;

comment on column core.progress_photos.week_start is
  'Monday 00:00 (local, epoch ms) of the week this photo is filed under. The '
  'identity half of a photo: one slot per (week_start, pose_type). Null on rows '
  'predating Lift 2.0.0, which the client derives from `date` in the device''s '
  'own timezone — the server cannot, because Monday depends on where you were '
  'standing.';

comment on column core.progress_photos.date is
  'When the photo was taken (epoch ms). Metadata, not identity — see '
  '`week_start`. Kept as the Liftio column name because renaming it would '
  'break the rows already in it for no gain.';

-- Retaking replaces, and the slot is what "the same photo" means. Without this
-- two devices that both shot a front photo in the same week produce two rows,
-- and the grid shows a duplicate week that no local database ever contained.
--
-- Partial, because a tombstone is not a slot: a deleted photo must not block
-- the week being shot again.
create unique index if not exists progress_photos_one_per_slot
  on core.progress_photos (user_id, week_start, pose_type)
  where deleted_at is null and week_start is not null;
