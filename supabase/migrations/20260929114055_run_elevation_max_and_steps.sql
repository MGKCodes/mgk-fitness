-- RE-STAMPED 2026-09-29. This file was dated 20260901130000, which sorts
-- BEHIND 20260901172935 (progress_photos_week_start, already applied), so
-- `db push` skipped it and it never reached production: run.runs had no
-- elevation_max_m or steps, and every Run backup upsert, which sends both,
-- failed with PGRST204 from build 13 onward. Applied on 2026-09-29 and renamed
-- to the version the ledger stamped, as 20260904100915 was before it.

-- run.runs gains the two columns the device has had since schema version 8.
--
-- ## What was losing data
--
-- `elevation_max_m` and `steps` are written on every run by the recorder and
-- have never had anywhere to go. The mirror enumerates its columns explicitly,
-- so both were dropped on the way up and absent on the way back down: a runner
-- who changed phone got their runs restored **without their high point and
-- their step count**, silently, and with no way to tell that anything had gone.
--
-- Nothing rendered wrongly as a result — absent is already the normal state for
-- both, which is why it went unnoticed — and that is exactly what made it worth
-- fixing rather than living with. A loss that shows up as an empty field is a
-- loss nobody reports.
--
-- Both halves of the seam said so in their own comments and pointed at each
-- other: `SupabaseRunBackup.pushRun` and `SupabaseRestore`. They were right
-- that the schema was not theirs to change. This is that change.
--
-- ## Nullable, and staying that way
--
-- Absence is the designed state for both. `steps` needs a Health permission
-- that may be refused, and a denied read is indistinguishable from no data
-- (`apps/mgk_run/CLAUDE.md`, rule 6). `elevation_max_m` needs an absolute
-- barometric altitude the app does not read at all yet
-- (ADR-0024), so today it is null on every run and correctly so — a maximum
-- derived from a relative altimeter starts at zero wherever the runner set off,
-- which is the plausible-wrong-number that ADR refuses.
--
-- So this adds somewhere to put them, not a promise that they arrive.
--
-- No backfill: rows already in `run.runs` were mirrored before these existed
-- and the device copies still hold the values. A restore onto the ORIGINAL
-- phone was never the lossy path.

alter table run.runs
  add column if not exists elevation_max_m real,
  add column if not exists steps integer;

comment on column run.runs.elevation_max_m is
  'Highest point of the run, in metres. Null unless an absolute barometric altitude was available (ADR-0024) — which is every run today, because no barometric source is wired.';
comment on column run.runs.steps is
  'Steps recorded during the run, read from Health. Null when the permission was refused or Health had nothing: a denied read is indistinguishable from no data, so both are absent rather than zero.';
