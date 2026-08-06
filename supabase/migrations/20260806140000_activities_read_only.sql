-- core.activities: revoke the write grants it inherited by accident.
--
-- `20260806130000` sets default privileges on `core`, `lift` and `run` granting
-- `authenticated` full CRUD on new tables — right for the tables users actually
-- own. `core.activities` was created in the NEXT migration, so it inherited
-- them, and the explicit `grant select` that followed only added to that set
-- rather than replacing it. `core.entitlements` got an explicit revoke;
-- activities did not.
--
-- Never exploitable: RLS is on and the only policy is FOR SELECT, so writes
-- found no permissive policy and were denied. But "no client write path at all"
-- is the design, and a grant nobody needs is a grant that only matters the day a
-- policy has a bug. Two layers, not one.
--
-- The general rule this is an instance of: in a schema with default privileges,
-- a read-only table needs an explicit REVOKE. Granting SELECT is not the same as
-- granting only SELECT.

revoke insert, update, delete on core.activities from authenticated;

-- Belt and braces: this table is derived, and the triggers that maintain it are
-- SECURITY DEFINER, so nothing is lost by making the intent explicit.
revoke insert, update, delete on core.activities from anon;
