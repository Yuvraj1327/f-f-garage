-- =============================================================================
-- Migration 1 of 5: enum types and shared trigger helpers
-- =============================================================================
-- Enum values defined here are mirrored in:
--   backend/app/domain/enums.py
--   mobile/lib/data/models/enums.dart
-- backend/tests/test_schema_consistency.py fails if the three drift apart.
-- =============================================================================

create type public.user_role as enum ('customer', 'driver', 'admin');

create type public.vehicle_type as enum ('bike', 'scooter');

create type public.extra_charge_type as enum ('spare_part', 'engine_oil', 'other');

create type public.booking_status as enum (
  'pending_payment',
  'confirmed',
  'assigned',
  'on_the_way',
  'in_progress',
  'completed',
  'cancelled'
);

create type public.payment_status as enum ('pending', 'successful', 'failed');

-- Keeps updated_at current. Attached to every table that has the column.
create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Trigger functions are never meant to be called through the REST /rpc API.
revoke all on function public.set_updated_at() from public, anon, authenticated;
