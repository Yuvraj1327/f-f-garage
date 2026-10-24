-- =============================================================================
-- Migration 8: customer booking workflow (Phase 4)
-- =============================================================================
-- The bookings table already exists (migration 4). This migration adds what the
-- booking workflow needs and puts the rules that must never be broken into the
-- database, so they hold no matter which code writes a booking:
--
--   * price/service snapshots (names, inclusions, duration) and a snapshot table
--     for the extra charges shown in the booking summary
--   * an idempotency key so a retried request cannot create a second booking
--   * one active booking per customer per slot (double-tap / duplicate guard)
--   * a hard capacity check per date and slot, serialised with an advisory lock
--     so two customers racing for the last place cannot both get it
--   * an allowed-transitions check on `status`, and locked snapshot columns
--   * `create_booking(...)`: booking + extra-charge snapshot in ONE transaction
--
-- Customers still have no write access: all writes come from the backend
-- (service_role). `booking_number` is the unique identity column; the app shows
-- it as FF-000123.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Snapshot columns
-- -----------------------------------------------------------------------------
alter table public.bookings
  add column service_name text,
  add column package_name text,
  add column package_inclusions text[] not null default '{}',
  add column estimated_duration_minutes integer,
  add column client_request_id uuid,
  add column cancelled_by uuid references public.profiles (id) on delete set null;

-- Backfill any pre-existing rows from the live catalogue, then require the columns.
update public.bookings b
set service_name = s.name,
    package_name = p.name,
    package_inclusions = p.inclusions,
    estimated_duration_minutes = p.estimated_duration_minutes
from public.services s, public.service_packages p
where s.id = b.service_id and p.id = b.package_id and b.service_name is null;

alter table public.bookings
  alter column service_name set not null,
  alter column package_name set not null,
  add constraint bookings_service_name_not_blank check (btrim(service_name) <> ''),
  add constraint bookings_package_name_not_blank check (btrim(package_name) <> ''),
  add constraint bookings_duration_range
    check (estimated_duration_minutes is null or estimated_duration_minutes between 5 and 1440),
  add constraint bookings_address_line_length check (char_length(address_line) <= 250),
  add constraint bookings_landmark_length check (landmark is null or char_length(landmark) <= 120),
  add constraint bookings_notes_length
    check (customer_notes is null or char_length(customer_notes) <= 500),
  add constraint bookings_cancellation_reason_length
    check (cancellation_reason is null or char_length(cancellation_reason) <= 300);

-- Any writer that omits the snapshot (e.g. a script) still gets one: it is copied
-- from the catalogue at insert time. The backend sends the values explicitly.
create function public.fill_booking_snapshot()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.service_name is null then
    select name into new.service_name from public.services where id = new.service_id;
  end if;
  if new.package_name is null or new.estimated_duration_minutes is null then
    select coalesce(new.package_name, p.name),
           coalesce(new.estimated_duration_minutes, p.estimated_duration_minutes),
           case when new.package_inclusions = '{}' then p.inclusions else new.package_inclusions end
    into new.package_name, new.estimated_duration_minutes, new.package_inclusions
    from public.service_packages p where p.id = new.package_id;
  end if;
  return new;
end;
$$;

create trigger bookings_fill_snapshot
  before insert on public.bookings
  for each row execute function public.fill_booking_snapshot();

-- A retried request (same key) returns the first booking instead of a new one.
create unique index bookings_client_request_key
  on public.bookings (customer_id, client_request_id)
  where client_request_id is not null;

-- A customer cannot hold the same slot twice (double tap, duplicate submit).
create unique index bookings_one_active_per_customer_slot
  on public.bookings (customer_id, scheduled_date, slot_start, slot_end)
  where status <> 'cancelled';

create index bookings_created_idx on public.bookings (created_at desc);
create index bookings_pincode_idx on public.bookings (pincode);
create index bookings_customer_phone_idx on public.bookings (customer_phone);

-- -----------------------------------------------------------------------------
-- Extra charges shown in the booking summary (snapshot; never edited)
-- -----------------------------------------------------------------------------
create table public.booking_extra_charges (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings (id) on delete cascade,
  -- SET NULL: an admin may delete a charge later; the snapshot stays.
  extra_charge_id uuid references public.extra_charges (id) on delete set null,
  charge_type public.extra_charge_type not null,
  name text not null,
  -- NULL = "charged at actuals on the day"
  amount numeric(10, 2),
  -- true: the customer chose it and it is part of bookings.extra_charges_total.
  -- false: shown for information only (may apply on the day).
  included_in_total boolean not null default false,
  created_at timestamptz not null default now(),

  constraint booking_extra_charges_name_not_blank check (btrim(name) <> ''),
  constraint booking_extra_charges_amount_non_negative check (amount is null or amount >= 0),
  constraint booking_extra_charges_included_has_amount
    check (not included_in_total or amount is not null)
);

create index booking_extra_charges_booking_idx on public.booking_extra_charges (booking_id);

create function public.protect_booking_extra_charge_snapshot()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- The only permitted change: the foreign key clearing itself (ON DELETE SET NULL)
  -- when an admin deletes the catalogue charge.
  if new.extra_charge_id is null
     and new.booking_id = old.booking_id
     and new.charge_type = old.charge_type
     and new.name = old.name
     and new.amount is not distinct from old.amount
     and new.included_in_total = old.included_in_total
     and new.created_at = old.created_at then
    return new;
  end if;
  raise exception 'Booking extra-charge snapshots cannot be changed' using errcode = '23514';
end;
$$;

create trigger booking_extra_charges_immutable
  before update on public.booking_extra_charges
  for each row execute function public.protect_booking_extra_charge_snapshot();

-- -----------------------------------------------------------------------------
-- Status transitions and locked columns
-- -----------------------------------------------------------------------------
create function public.booking_status_transition_allowed(
  p_from public.booking_status,
  p_to public.booking_status
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_from = p_to
    or (p_from, p_to) in (
      ('pending_payment', 'confirmed'),
      ('pending_payment', 'cancelled'),
      ('confirmed', 'assigned'),
      ('confirmed', 'cancelled'),
      ('assigned', 'confirmed'),
      ('assigned', 'on_the_way'),
      ('assigned', 'cancelled'),
      ('on_the_way', 'in_progress'),
      ('on_the_way', 'cancelled'),
      ('in_progress', 'completed'),
      ('in_progress', 'cancelled')
    );
$$;

create function public.guard_booking_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status in ('completed', 'cancelled') then
    raise exception 'A % booking cannot be changed', old.status using errcode = '23514';
  end if;

  if not public.booking_status_transition_allowed(old.status, new.status) then
    raise exception 'A booking cannot move from % to %', old.status, new.status
      using errcode = '23514';
  end if;

  -- What was booked and what it cost never changes after creation.
  if new.booking_number is distinct from old.booking_number
     or new.customer_id is distinct from old.customer_id
     or new.service_id is distinct from old.service_id
     or new.package_id is distinct from old.package_id
     or new.vehicle_type is distinct from old.vehicle_type
     or new.service_name is distinct from old.service_name
     or new.package_name is distinct from old.package_name
     or new.package_inclusions is distinct from old.package_inclusions
     or new.estimated_duration_minutes is distinct from old.estimated_duration_minutes
     or new.package_price is distinct from old.package_price
     or new.extra_charges_total is distinct from old.extra_charges_total
     or new.customer_name is distinct from old.customer_name
     or new.customer_phone is distinct from old.customer_phone
     or new.client_request_id is distinct from old.client_request_id
     or new.created_at is distinct from old.created_at then
    raise exception 'The booked service, price and customer cannot be changed'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger bookings_guard_update
  before update on public.bookings
  for each row execute function public.guard_booking_update();

-- -----------------------------------------------------------------------------
-- Capacity per date and slot
-- -----------------------------------------------------------------------------
-- Runs when a booking is created or moved to another date/slot. The advisory lock
-- (released at commit) makes "count, then insert" atomic per slot and date.
-- Capacity = the slot's capacity, or the capacity of an "open" exception for that
-- date. Closures, lead time and the booking window are checked by the backend; a
-- time that matches no slot row is not limited here (the backend refuses it).
create function public.enforce_slot_capacity()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_slot_id uuid;
  v_capacity integer;
  v_booked integer;
begin
  if new.status = 'cancelled' then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and new.scheduled_date = old.scheduled_date
     and new.slot_start = old.slot_start
     and new.slot_end = old.slot_end then
    return new;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('booking-slot:' || new.scheduled_date::text || new.slot_start::text, 0));

  select id, capacity into v_slot_id, v_capacity
  from public.time_slots
  where start_time = new.slot_start and end_time = new.slot_end
  order by is_active desc, created_at
  limit 1;
  if v_slot_id is null then
    return new;
  end if;

  select e.capacity into v_capacity
  from public.availability_exceptions e
  where e.exception_date = new.scheduled_date
    and e.time_slot_id = v_slot_id
    and e.is_open
    and e.capacity is not null;
  if not found then
    select capacity into v_capacity from public.time_slots where id = v_slot_id;
  end if;

  select count(*) into v_booked
  from public.bookings b
  where b.scheduled_date = new.scheduled_date
    and b.slot_start = new.slot_start
    and b.slot_end = new.slot_end
    and b.status <> 'cancelled'
    and b.id <> new.id;

  if v_booked >= v_capacity then
    raise exception 'slot_full: that time slot has no places left' using errcode = '23P01';
  end if;
  return new;
end;
$$;

create trigger bookings_enforce_capacity
  before insert or update of scheduled_date, slot_start, slot_end on public.bookings
  for each row execute function public.enforce_slot_capacity();

-- -----------------------------------------------------------------------------
-- Atomic create: booking + extra-charge snapshot
-- -----------------------------------------------------------------------------
-- p_booking carries the already-validated values (the backend computed the price
-- from the catalogue; the client never supplies one). p_charges is an array of
-- {extra_charge_id, charge_type, name, amount, included_in_total}.
-- A repeated client_request_id returns the booking it created the first time.
create function public.create_booking(p_booking jsonb, p_charges jsonb default '[]'::jsonb)
returns setof public.bookings
language plpgsql
set search_path = ''
as $$
declare
  v_row public.bookings;
  v_extra numeric(10, 2);
  v_customer uuid := (p_booking ->> 'customer_id')::uuid;
  v_request uuid := nullif(p_booking ->> 'client_request_id', '')::uuid;
begin
  if v_request is not null then
    select * into v_row from public.bookings
    where customer_id = v_customer and client_request_id = v_request;
    if found then
      return next v_row;
      return;
    end if;
  end if;

  select coalesce(sum((c ->> 'amount')::numeric)
                  filter (where (c ->> 'included_in_total')::boolean), 0)
  into v_extra
  from jsonb_array_elements(p_charges) c;

  insert into public.bookings (
    customer_id, service_id, package_id, vehicle_type, status,
    customer_name, customer_phone,
    address_line, landmark, city, state, pincode, service_area_id, latitude, longitude,
    scheduled_date, slot_start, slot_end,
    service_name, package_name, package_inclusions, estimated_duration_minutes,
    package_price, extra_charges_total, customer_notes, client_request_id
  ) values (
    v_customer,
    (p_booking ->> 'service_id')::uuid,
    (p_booking ->> 'package_id')::uuid,
    (p_booking ->> 'vehicle_type')::public.vehicle_type,
    'pending_payment',
    p_booking ->> 'customer_name',
    p_booking ->> 'customer_phone',
    p_booking ->> 'address_line',
    nullif(p_booking ->> 'landmark', ''),
    p_booking ->> 'city',
    nullif(p_booking ->> 'state', ''),
    p_booking ->> 'pincode',
    nullif(p_booking ->> 'service_area_id', '')::uuid,
    nullif(p_booking ->> 'latitude', '')::numeric,
    nullif(p_booking ->> 'longitude', '')::numeric,
    (p_booking ->> 'scheduled_date')::date,
    (p_booking ->> 'slot_start')::time,
    (p_booking ->> 'slot_end')::time,
    p_booking ->> 'service_name',
    p_booking ->> 'package_name',
    coalesce(array(select jsonb_array_elements_text(p_booking -> 'package_inclusions')), '{}'),
    nullif(p_booking ->> 'estimated_duration_minutes', '')::integer,
    (p_booking ->> 'package_price')::numeric,
    v_extra,
    nullif(p_booking ->> 'customer_notes', ''),
    v_request
  ) returning * into v_row;

  insert into public.booking_extra_charges
    (booking_id, extra_charge_id, charge_type, name, amount, included_in_total)
  select v_row.id,
         nullif(c ->> 'extra_charge_id', '')::uuid,
         (c ->> 'charge_type')::public.extra_charge_type,
         c ->> 'name',
         nullif(c ->> 'amount', '')::numeric,
         coalesce((c ->> 'included_in_total')::boolean, false)
  from jsonb_array_elements(p_charges) c;

  return next v_row;
  return;
end;
$$;

-- Backend only: not reachable through the public REST API.
revoke all on function public.create_booking(jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.create_booking(jsonb, jsonb) to service_role;
revoke all on function public.fill_booking_snapshot() from public, anon, authenticated;
revoke all on function public.guard_booking_update() from public, anon, authenticated;
revoke all on function public.enforce_slot_capacity() from public, anon, authenticated;
revoke all on function public.protect_booking_extra_charge_snapshot() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- RLS + grants for the snapshot table (read-only for API roles)
-- -----------------------------------------------------------------------------
alter table public.booking_extra_charges enable row level security;
revoke all on table public.booking_extra_charges from anon, authenticated;
grant select on table public.booking_extra_charges to authenticated;
grant all on table public.booking_extra_charges to service_role;

-- Whoever may see the booking may see its charges: the subquery runs under the
-- caller's own bookings policies (customer: own, driver: assigned, admin: all).
create policy booking_extra_charges_select_via_booking
  on public.booking_extra_charges for select to authenticated
  using (exists (select 1 from public.bookings b where b.id = booking_extra_charges.booking_id));
