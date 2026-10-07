-- A slot's id is made unique to its plan on the way in.
--
-- `lift.plan_slots` keys on `id` alone, across every plan and every lifter.
-- The coach's slots were always named `<plan id>-<day>-<n>`, but the template
-- Lift falls back to when the coach cannot answer named them by day and role
-- only -- `upper-horizontal-press` -- so the second template plan saved
-- anywhere collided with the first and the whole plan was refused. Lift 2.0.1
-- prefixes them itself; 2.0.0 is in the stores and cannot be changed, so the
-- database does it for any id that does not already start with its plan's.
--
-- Nothing in 2.0.0 writes a slot back by the id it sent (`recordResult` is not
-- wired), and the next read of the plan returns the stored ids, so the app
-- holding the unprefixed ones until then costs nothing.
--
-- Applied 2026-10-07 through the SQL editor (apply_migration declined it, the
-- Supabase MCP's confirmation for a `drop`), and recorded in
-- schema_migrations by hand under this file's version.

create or replace function lift.plan_slot_id_per_plan()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if left(new.id, length(new.plan_id) + 1) <> new.plan_id || '-' then
    new.id := new.plan_id || '-' || new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists plan_slots_id_per_plan on lift.plan_slots;
create trigger plan_slots_id_per_plan
  before insert on lift.plan_slots
  for each row execute function lift.plan_slot_id_per_plan();
