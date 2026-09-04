-- core.entitlements gains a watermark, so a late webhook cannot undo a live one.
--
-- ## Why a column and not `updated_at`
--
-- `updated_at` records when WE wrote, not when the store decided. Store
-- webhooks arrive out of order routinely — a renewal and the expiry it replaces
-- can cross on the wire, and a retry of a two-minute-old event can land after
-- the event that superseded it. Ordering on write time makes the last delivery
-- win, which is the wrong winner: it would take a live subscription and mark it
-- expired because a stale retry arrived second.
--
-- `event_ms` is the store's own timestamp for the event that produced the row,
-- so the writer can refuse anything older than what it already has. That is the
-- whole idempotency story: replaying an event is a no-op because its timestamp
-- is not greater than the one recorded.
--
-- ## Nullable on purpose
--
-- No row has one yet — nothing has ever written to this table (ADR-0028), and
-- the first webhook for each user fills it. A NULL means "written before there
-- was a watermark, or by hand", and the writer treats that as "older than
-- anything", so a real event always wins over a hand-inserted test row. That is
-- also what keeps the entitlement SQL in the TestFlight sheet working.

alter table core.entitlements
  add column if not exists event_ms bigint;

comment on column core.entitlements.event_ms is
  'Store timestamp (epoch ms) of the webhook event that last wrote this row. The writer refuses an event that is not newer, so replays are no-ops and a late delivery cannot revert a newer state. NULL means the row predates the watermark or was written by hand, and loses to any real event.';
