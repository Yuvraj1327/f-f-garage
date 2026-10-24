-- =============================================================================
-- Migration 3 of 5: service catalogue, packages, extra charges, serviceable areas
-- =============================================================================
-- Model
--   services          what is offered (e.g. "General Service"), per vehicle type
--   service_packages  priced options inside a service (e.g. Basic / Premium)
--   extra_charges     spare-part / engine-oil / other charges that may apply to a
--                     service, or to one specific package of it
--   service_areas     PIN codes where doorstep service is available (one row per
--                     PIN code; deactivate instead of delete once bookings exist)
--
-- Reads: any signed-in user sees ACTIVE rows. Writes: admins only.
-- =============================================================================

create table public.services (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  vehicle_type public.vehicle_type not null,
  description text,
  display_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint services_name_not_blank check (btrim(name) <> '')
);

create unique index services_vehicle_type_name_key
  on public.services (vehicle_type, lower(name));
create index services_active_order_idx
  on public.services (vehicle_type, display_order)
  where is_active;

create table public.service_packages (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null references public.services (id) on delete cascade,
  name text not null,
  description text,
  price numeric(10, 2) not null,
  inclusions text[] not null default '{}',
  estimated_duration_minutes integer,
  display_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint service_packages_name_not_blank check (btrim(name) <> ''),
  constraint service_packages_price_non_negative check (price >= 0),
  constraint service_packages_duration_positive
    check (estimated_duration_minutes is null or estimated_duration_minutes > 0),
  -- Target for composite foreign keys that must prove "package belongs to service".
  constraint service_packages_id_service_key unique (id, service_id)
);

create unique index service_packages_service_name_key
  on public.service_packages (service_id, lower(name));
create index service_packages_service_idx
  on public.service_packages (service_id, display_order)
  where is_active;

create table public.extra_charges (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null references public.services (id) on delete cascade,
  -- NULL = applies to every package of the service.
  package_id uuid,
  charge_type public.extra_charge_type not null default 'other',
  name text not null,
  description text,
  -- NULL = charged at actuals (e.g. a spare part priced on the day).
  amount numeric(10, 2),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint extra_charges_name_not_blank check (btrim(name) <> ''),
  constraint extra_charges_amount_non_negative check (amount is null or amount >= 0),
  -- When package_id is set it must be a package of the same service.
  constraint extra_charges_package_matches_service
    foreign key (package_id, service_id)
    references public.service_packages (id, service_id)
    on delete cascade
);

create index extra_charges_service_idx on public.extra_charges (service_id) where is_active;
create index extra_charges_package_idx on public.extra_charges (package_id) where package_id is not null;

create table public.service_areas (
  id uuid primary key default gen_random_uuid(),
  pincode text not null,
  area_name text not null,
  city text not null,
  state text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- Indian PIN code: six digits, first digit 1-9.
  constraint service_areas_pincode_format check (pincode ~ '^[1-9][0-9]{5}$'),
  constraint service_areas_area_name_not_blank check (btrim(area_name) <> ''),
  constraint service_areas_city_not_blank check (btrim(city) <> ''),
  constraint service_areas_state_not_blank check (btrim(state) <> ''),
  constraint service_areas_pincode_key unique (pincode)
);

create trigger services_set_updated_at
  before update on public.services
  for each row execute function public.set_updated_at();
create trigger service_packages_set_updated_at
  before update on public.service_packages
  for each row execute function public.set_updated_at();
create trigger extra_charges_set_updated_at
  before update on public.extra_charges
  for each row execute function public.set_updated_at();
create trigger service_areas_set_updated_at
  before update on public.service_areas
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- RLS + grants
-- -----------------------------------------------------------------------------
alter table public.services enable row level security;
alter table public.service_packages enable row level security;
alter table public.extra_charges enable row level security;
alter table public.service_areas enable row level security;

revoke all on table public.services from anon, authenticated;
revoke all on table public.service_packages from anon, authenticated;
revoke all on table public.extra_charges from anon, authenticated;
revoke all on table public.service_areas from anon, authenticated;

-- Table-level DML grants are only effective for admins: the policies below
-- reject writes from everyone else.
grant select, insert, update, delete on table public.services to authenticated;
grant select, insert, update, delete on table public.service_packages to authenticated;
grant select, insert, update, delete on table public.extra_charges to authenticated;
grant select, insert, update, delete on table public.service_areas to authenticated;

grant all on table public.services to service_role;
grant all on table public.service_packages to service_role;
grant all on table public.extra_charges to service_role;
grant all on table public.service_areas to service_role;

-- services
create policy services_select_active
  on public.services for select to authenticated
  using (is_active);
create policy services_admin_all
  on public.services for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- service_packages (visible only while the parent service is also active)
create policy service_packages_select_active
  on public.service_packages for select to authenticated
  using (
    is_active
    and exists (
      select 1 from public.services s
      where s.id = service_packages.service_id and s.is_active
    )
  );
create policy service_packages_admin_all
  on public.service_packages for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- extra_charges
create policy extra_charges_select_active
  on public.extra_charges for select to authenticated
  using (
    is_active
    and exists (
      select 1 from public.services s
      where s.id = extra_charges.service_id and s.is_active
    )
  );
create policy extra_charges_admin_all
  on public.extra_charges for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- service_areas
create policy service_areas_select_active
  on public.service_areas for select to authenticated
  using (is_active);
create policy service_areas_admin_all
  on public.service_areas for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));
