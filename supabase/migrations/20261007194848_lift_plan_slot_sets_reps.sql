-- `lift.plan_slots` gains the two columns the app has written since 21 August.
--
-- b997cff (2026-08-21) made sets and reps part of a slot -- "coaching
-- knowledge, not a lookup on the goal" -- and taught SupabaseStandingPlanStore
-- to write and read them. No migration came with it, and every test of the
-- store ran against a fake, so nothing noticed. In production every plan save
-- since was refused by PostgREST (400, unknown column) AFTER the plan row had
-- been written: the lifter was left with an active plan holding no slots, and
-- the app said "Could not reach your coach". Found 2026-10-07, on the first
-- plan anybody had built in production.
--
-- **Not null, with the app's own defaults.** A slot read without them falls
-- back to 3 x 10 (`SupabaseStandingPlanStore._hydrate`), and a coach proposal
-- that omits them is given the same (`ProposedSlot.fromJson`). The defaults
-- also keep every insert written before these columns existed valid, which
-- includes the pgTAP suite's own fixtures.
--
-- Positive, like `last_top_reps` beside them: a slot of no sets, or of sets of
-- nothing, is not a prescription, and PlanShape would count it as one.

alter table lift.plan_slots
  add column if not exists sets smallint not null default 3
    constraint plan_slots_sets_check check (sets > 0),
  add column if not exists reps smallint not null default 10
    constraint plan_slots_reps_check check (reps > 0);

comment on column lift.plan_slots.sets is
  'Hard sets for this slot each time its day runs. Written by the app from the plan template or the coach''s proposal.';
comment on column lift.plan_slots.reps is
  'Target reps per set. The weight is never stored here: SessionPrescription derives it from the lifter''s own log.';
