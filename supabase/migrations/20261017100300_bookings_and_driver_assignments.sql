-- =============================================================================
-- Migration 4 of 5: bookings and driver assignments
-- =============================================================================
-- Bookings snapshot the customer's name/phone, the address and the price at
-- booking time. That keeps history stable if the customer edits their profile
-- or the admin changes a price, and it lets a driver be shown only what the job
-- needs without any access to the customer's profile row.
--
-- Status values (enum booking_status), in normal order:
--   pending_payment -> confirmed -> assigned -> on_the_way -> in_progress
--   -> completed, with `cancelled` reachable from any non-final state.
-- The allowed transitions are enforced by the backend business layer (later
-- phase); the database enforces that the matching timestamps are present.
--
-- All writes to these tables come from the backend (service_role). The
-- `authenticated` role is SELECT-only, filtered by the policies below.
-- =============================================================================

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  -- Short human-friendly reference; format it in the app, e.g. FF-000123.
  booking_number bigint generated always as identity,
  customer_id uuid not null references public.profiles (id) on delete restrict,
  service_id uuid not null,
  package_id uuid not null,
  vehicle_type public.vehicle_type not null,
  status public.booking_status not null default 'pending_payment',

  -- Snapshots taken at booking time
  customer_name text not null,
  customer_phone text not null,
  address_line text not null,
  landmark text,
  city text not null,
  state text,
  pincode text not null,
  -- Kept for reporting; SET NULL so an admin can remove an area without
  -- touching booking history (pincode above is the permanent record).
  service_area_id uuid references public.service_areas (id) on delete set null,
  latitude numeric(9, 6),
  longitude numeric(9, 6),

  -- Requested visit
  scheduled_date date not null,
  slot_start time not null,
  slot_end time not null,

  -- Pricing snapshot (INR). total_amount is always derived.
  package_price numeric(10, 2) not null,
  extra_charges_total numeric(10, 2) not null default 0,
  total_amount numeric(10, 2) generated always as (package_price + extra_charges_total) stored,

  customer_notes text,
  cancellation_reason text,
  confirmed_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint bookings_booking_number_key unique (booking_number),
  -- Lets payments prove "this booking belongs to this customer".
  constraint bookings_id_customer_key unique (id, customer_id),
  -- The package must belong to the stated service.
  constraint bookings_package_matches_service
    foreign key (package_id, service_id)
    references public.service_packages (id, service_id)
    on delete restrict,

  constraint bookings_customer_name_not_blank check (btrim(customer_name) <> ''),
  constraint bookings_customer_phone_format check (customer_phone ~ '^\+?[0-9]{7,15}$'),
  constraint bookings_address_line_not_blank check (btrim(address_line) <> ''),
  constraint bookings_city_not_blank check (btrim(city) <> ''),
  constraint bookings_pincode_format check (pincode ~ '^[1-9][0-9]{5}$'),
  constraint bookings_latitude_range check (latitude is null or latitude between -90 and 90),
  constraint bookings_longitude_range check (longitude is null or longitude between -180 and 180),
  constraint bookings_coordinates_together check ((latitude is null) = (longitude is null)),
  constraint bookings_slot_order check (slot_end > slot_start),
  constraint bookings_package_price_non_negative check (package_price >= 0),
  constraint bookings_extra_charges_non_negative check (extra_charges_total >= 0),

  -- Status <-> timestamp consistency
  constraint bookings_confirmed_at_matches_status check (
    case
      when status = 'pending_payment' then confirmed_at is null
      when status = 'cancelled' then true
      else confirmed_at is not null
    end
  ),
  constraint bookings_completed_at_matches_status
    check ((status = 'completed') = (completed_at is not null)),
  constraint bookings_cancelled_at_matches_status
    check ((status = 'cancelled') = (cancelled_at is not null))
);

comment on table public.bookings is
  'Customer service bookings. Customer/address/price fields are snapshots.';

create index bookings_customer_created_idx on public.bookings (customer_id, created_at desc);
create index bookings_status_date_idx on public.bookings (status, scheduled_date);
create index bookings_scheduled_date_idx on public.bookings (scheduled_date);
create index bookings_package_idx on public.bookings (package_id);
create index bookings_service_area_idx on public.bookings (service_area_id) where service_area_id is not null;

create trigger bookings_set_updated_at
  before update on public.bookings
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Driver assignments. Reassigning = deactivate the old row, insert a new one,
-- so the full assignment history is kept.
-- -----------------------------------------------------------------------------
create table public.driver_assignments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings (id) on delete cascade,
  driver_id uuid not null references public.profiles (id) on delete restrict,
  assigned_by uuid not null references public.profiles (id) on delete restrict,
  is_active boolean not null default true,
  assigned_at timestamptz not null default now(),
  unassigned_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint driver_assignments_active_matches_unassigned
    check (is_active = (unassigned_at is null)),
  constraint driver_assignments_unassigned_after_assigned
    check (unassigned_at is null or unassigned_at >= assigned_at)
);

-- At most one active driver per booking.
create unique index driver_assignments_one_active_per_booking
  on public.driver_assignments (booking_id)
  where is_active;
create index driver_assignments_booking_idx on public.driver_assignments (booking_id);
create index driver_assignments_driver_active_idx
  on public.driver_assignments (driver_id)
  where is_active;

create trigger driver_assignments_set_updated_at
  before update on public.driver_assignments
  for each row execute function public.set_updated_at();

-- Cross-table rules a CHECK constraint cannot express:
--   * driver_id must be a driver profile (active when the assignment is active)
--   * assigned_by must be an admin profile
--   * identity columns never change after insert (create a new row instead)
create function public.validate_driver_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.user_role;
  v_active boolean;
begin
  if tg_op = 'UPDATE' then
    if new.booking_id is distinct from old.booking_id
       or new.driver_id is distinct from old.driver_id
       or new.assigned_by is distinct from old.assigned_by
       or new.assigned_at is distinct from old.assigned_at then
      raise exception 'Driver assignment identity columns are immutable; create a new assignment instead'
        using errcode = '23514';
    end if;
    return new;
  end if;

  select role, is_active into v_role, v_active
  from public.profiles where id = new.driver_id;
  if v_role is distinct from 'driver' then
    raise exception 'driver_id must reference a profile with the driver role'
      using errcode = '23514';
  end if;
  if new.is_active and not v_active then
    raise exception 'Cannot assign a booking to a deactivated driver'
      using errcode = '23514';
  end if;

  select role into v_role from public.profiles where id = new.assigned_by;
  if v_role is distinct from 'admin' then
    raise exception 'assigned_by must reference a profile with the admin role'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger driver_assignments_validate
  before insert or update on public.driver_assignments
  for each row execute function public.validate_driver_assignment();

-- SECURITY DEFINER: must not be reachable through the REST /rpc API.
revoke all on function public.validate_driver_assignment() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- RLS + grants (SELECT only for API roles; the backend writes via service_role)
-- -----------------------------------------------------------------------------
alter table public.bookings enable row level security;
alter table public.driver_assignments enable row level security;

revoke all on table public.bookings from anon, authenticated;
revoke all on table public.driver_assignments from anon, authenticated;
grant select on table public.bookings to authenticated;
grant select on table public.driver_assignments to authenticated;
grant all on table public.bookings to service_role;
grant all on table public.driver_assignments to service_role;

-- Customers: their own bookings (active accounts only).
create policy bookings_select_own
  on public.bookings for select to authenticated
  using (
    customer_id = (select auth.uid())
    and (select public.current_user_role()) is not null
  );

-- Drivers: only bookings they are currently or were previously assigned.
create policy bookings_select_assigned_driver
  on public.bookings for select to authenticated
  using (
    (select public.current_user_role()) = 'driver'
    and exists (
      select 1
      from public.driver_assignments da
      where da.booking_id = bookings.id
        and da.driver_id = (select auth.uid())
        and da.is_active
    )
  );

create policy bookings_select_admin
  on public.bookings for select to authenticated
  using ((select public.is_admin()));

-- Assignments: a driver sees their own; admins see all; customers see none.
create policy driver_assignments_select_own_driver
  on public.driver_assignments for select to authenticated
  using (
    driver_id = (select auth.uid())
    and (select public.current_user_role()) = 'driver'
  );

create policy driver_assignments_select_admin
  on public.driver_assignments for select to authenticated
  using ((select public.is_admin()));
