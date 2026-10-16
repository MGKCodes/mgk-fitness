-- `lift.sets.set_type` accepts the four types the app records, not two.
--
-- 20260807120000_lift_sync_columns.sql added the column with a check for
-- 'working' and 'warmup'. The app's `SetType` has four: a drop set is stored as
-- 'dropset' and a set taken to failure as 'failure', and both can be chosen in
-- a session. Every workout holding either was refused with 23514, which the
-- backup files as `rejected`: set aside on the phone, never uploaded, waiting
-- for an edit that would not have helped. Found 2026-10-07 by checking every
-- column Lift writes against production rather than against a fake.
--
-- Widening only. No stored row changes, and nothing that was valid stops being
-- valid.

alter table lift.sets drop constraint if exists sets_set_type_check;
alter table lift.sets
  add constraint sets_set_type_check
  check (set_type in ('working', 'warmup', 'dropset', 'failure'));
