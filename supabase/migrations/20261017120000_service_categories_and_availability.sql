-- =============================================================================
-- Migration 7: service categories and availability (time slots + closures)
-- =============================================================================
-- Adds
--   services.category              free-text grouping ("General Service", "Wash", ...)
--   time_slots                     the visit windows offered on a normal day, with a
--                                  capacity (max simultaneous bookings) and the
--                                  weekdays they run on (ISO: 1 = Monday ... 7 = Sunday)
--   availability_exceptions        date-specific changes to that routine:
--                                    whole-day closure  (time_slot_id is null)
--                                    one slot closed    (time_slot_id set, is_open = false)
--                                    one slot opened / given a different capacity on
--                                    a date it would not normally run (is_open = true)
--
-- Whether a slot can be booked on a date (past dates, booking window, lead time,
-- capacity left) is computed by the backend from these tables plus bookings;
-- the database guarantees that the definitions themselves are valid and that
-- active slots never overlap.
--
-- Same access model as the other catalogue tables: any signed-in user can read
-- active rows; only admins can write (and the backend uses the service role).
-- =============================================================================

alter table public.services
  add column category text not null default 'General';

alter table public.services
  add constraint services_category_not_blank check (btrim(category) <> '');

create index services_category_idx
  on public.services (vehicle_type, lower(category));

create index service_areas_city_idx on public.service_areas (lower(city));

-- -----------------------------------------------------------------------------
-- time_slots
-- -----------------------------------------------------------------------------
create table public.time_slots (
  id uuid primary key default gen_random_uuid(),
  start_time time not null,
  end_time time not null,
  -- How many bookings may share this slot on one date (e.g. number of crews).
  capacity integer not null default 1,
  days_of_week smallint[] not null default '{1,2,3,4,5,6,7}',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint time_slots_order check (end_time > start_time),
  constraint time_slots_capacity_range check (capacity between 1 and 50),
  constraint time_slots_days_valid
    check (
      cardinality(days_of_week) between 1 and 7
      and days_of_week <@ array[1, 2, 3, 4, 5, 6, 7]::smallint[]
    )
);

create index time_slots_active_start_idx on public.time_slots (start_time) where is_active;

-- Normalises days_of_week (sorted, no duplicates) and refuses overlapping
-- active slots that run on a common weekday. The advisory lock serialises
-- concurrent writers so two overlapping slots cannot both pass the check.
create function public.guard_time_slot()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.days_of_week is not null then
    new.days_of_week := coalesce(
      (select array_agg(distinct d order by d)::smallint[] from unnest(new.days_of_week) as d),
      '{}'::smallint[]
    );
  end if;

  if new.is_active then
    perform pg_advisory_xact_lock(hashtext('public.time_slots'));
    if exists (
      select 1
      from public.time_slots t
      where t.id <> new.id
        and t.is_active
        and t.days_of_week && new.days_of_week
        and t.start_time < new.end_time
        and new.start_time < t.end_time
    ) then
      raise exception 'This time slot overlaps another active slot'
        using errcode = '23P01';
    end if;
  end if;
  return new;
end;
$$;

create trigger time_slots_guard
  before insert or update on public.time_slots
  for each row execute function public.guard_time_slot();

-- -----------------------------------------------------------------------------
-- availability_exceptions
-- -----------------------------------------------------------------------------
create table public.availability_exceptions (
  id uuid primary key default gen_random_uuid(),
  exception_date date not null,
  -- NULL = the whole day.
  time_slot_id uuid references public.time_slots (id) on delete cascade,
  is_open boolean not null default false,
  -- Only for is_open = true: replaces the slot's normal capacity on this date.
  capacity integer,
  -- Shown to customers ("Closed for Diwali"), so keep it customer-safe.
  reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint availability_exceptions_whole_day_is_closure
    check (time_slot_id is not null or not is_open),
  constraint availability_exceptions_capacity_only_when_open
    check (capacity is null or is_open),
  constraint availability_exceptions_capacity_range
    check (capacity is null or capacity between 1 and 50),
  constraint availability_exceptions_reason_length
    check (reason is null or (btrim(reason) <> '' and char_length(reason) <= 200))
);

-- One exception per date and slot (and one whole-day row per date).
create unique index availability_exceptions_date_slot_key
  on public.availability_exceptions (
    exception_date,
    coalesce(time_slot_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );
create index availability_exceptions_slot_idx
  on public.availability_exceptions (time_slot_id)
  where time_slot_id is not null;

create trigger time_slots_set_updated_at
  before update on public.time_slots
  for each row execute function public.set_updated_at();
create trigger availability_exceptions_set_updated_at
  before update on public.availability_exceptions
  for each row execute function public.set_updated_at();

revoke all on function public.guard_time_slot() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- RLS + grants
-- -----------------------------------------------------------------------------
alter table public.time_slots enable row level security;
alter table public.availability_exceptions enable row level security;

revoke all on table public.time_slots from anon, authenticated;
revoke all on table public.availability_exceptions from anon, authenticated;

grant select, insert, update, delete on table public.time_slots to authenticated;
grant select, insert, update, delete on table public.availability_exceptions to authenticated;
grant all on table public.time_slots to service_role;
grant all on table public.availability_exceptions to service_role;

create policy time_slots_select_active
  on public.time_slots for select to authenticated
  using (is_active);
create policy time_slots_admin_all
  on public.time_slots for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create policy availability_exceptions_select_all
  on public.availability_exceptions for select to authenticated
  using (true);
create policy availability_exceptions_admin_all
  on public.availability_exceptions for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- -----------------------------------------------------------------------------
-- Booked-slot counts (used by the backend to work out how many spots are left)
-- -----------------------------------------------------------------------------
-- Cancelled bookings do not hold a slot. Grouping happens in the database so the
-- result stays small regardless of how many bookings exist. Backend-only: the
-- function exposes counts across all customers, so API users cannot call it.
create function public.slot_booking_counts(p_from date, p_to date)
returns table (scheduled_date date, slot_start time, slot_end time, booked bigint)
language sql
stable
set search_path = ''
as $$
  select b.scheduled_date, b.slot_start, b.slot_end, count(*) as booked
  from public.bookings b
  where b.scheduled_date between p_from and p_to
    and b.status <> 'cancelled'
  group by b.scheduled_date, b.slot_start, b.slot_end
$$;

revoke all on function public.slot_booking_counts(date, date) from public, anon, authenticated;
grant execute on function public.slot_booking_counts(date, date) to service_role;

create index if not exists bookings_slot_lookup_idx
  on public.bookings (scheduled_date, slot_start, slot_end)
  where status <> 'cancelled';
