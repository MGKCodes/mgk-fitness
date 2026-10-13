-- run.runs gains the race a run can be (Run ADR-0049).
--
-- ## Why
--
-- Until now the app knew about a race only by having built a plan aimed at
-- its date (ADR-0027), and the result lived on the phone's copy of that plan:
-- `finished_at` and `race_time_s` on the local `plans` table, never mirrored.
-- A runner with no plan who ran a half marathon got an ordinary 21.69 km run,
-- and a runner with a plan lost their official time the day they changed
-- phone. ADR-0027 named that the most expensive gap of the three it left,
-- because a confirmed race time is the one figure nothing can rebuild.
--
-- So the race moves onto the run, and goes up with it.
--
-- ## The columns
--
-- `race_distance_m` is the whole of "this run was a race": the course
-- distance, 21097.5 for a half, never the trace's 21686 (which stays in
-- `distance_m`, so both can be shown). Null is a training run, which is nearly
-- every row.
--
-- `race_time_s` is the official time when the runner gave one. Null on a race
-- means the phone's `duration_s` is the only time there is.
--
-- `race_name` is what the runner calls it. Optional.
--
-- ## The checks
--
-- The same limits `RunEditor.markRace` refuses on (250 km, 80 characters), and
-- the same rule `AppDatabase.setRunRace` writes by: an official time or a name
-- only ever sits beside a race distance. A check here is the backstop for a
-- client that skipped the editor, not the first line of defence.
--
-- ## Order of release
--
-- This must be live before any build that sends these columns ships.
-- `SupabaseRunBackup.pushRun` enumerates its columns, and a column the table
-- does not have fails the whole upsert with PGRST204 (it happened with
-- `elevation_max_m` and `steps`; see 20260929114055). Additive and nullable,
-- so every build already in the stores is unaffected.
--
-- Grants on run.runs are table-wide and the policy is row-based (own_runs), so
-- new columns are covered without a grant of their own.

alter table run.runs
  add column if not exists race_distance_m real,
  add column if not exists race_time_s integer,
  add column if not exists race_name text;

alter table run.runs drop constraint if exists runs_race_distance_sane;
alter table run.runs add constraint runs_race_distance_sane check (
  race_distance_m is null or (race_distance_m > 0 and race_distance_m <= 250000)
);

alter table run.runs drop constraint if exists runs_race_time_on_a_race;
alter table run.runs add constraint runs_race_time_on_a_race check (
  race_time_s is null or (race_distance_m is not null and race_time_s > 0)
);

alter table run.runs drop constraint if exists runs_race_name_on_a_race;
alter table run.runs add constraint runs_race_name_on_a_race check (
  race_name is null
  or (race_distance_m is not null and char_length(race_name) <= 80)
);

comment on column run.runs.race_distance_m is
  'Course distance in metres when the runner marked this run as a race (Run ADR-0049); null for a training run. Never the trace''s distance, which stays in distance_m.';
comment on column run.runs.race_time_s is
  'Official finish time in seconds, when the runner gave one. Null on a race means duration_s, the phone''s time, is the only time there is.';
comment on column run.runs.race_name is
  'What the runner calls the race. Optional, and only on a race.';
