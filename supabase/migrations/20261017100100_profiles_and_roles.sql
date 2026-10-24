-- =============================================================================
-- Migration 2 of 5: profiles, roles, role helper functions, profile RLS
-- =============================================================================
-- Security model for the whole schema
--   * Flutter talks only to FastAPI. FastAPI uses the service-role key, which
--     bypasses RLS, and enforces role checks itself.
--   * RLS + grants below are a second line of defence for the case where
--     someone calls Supabase's auto-generated REST API directly with a normal
--     user JWT (the anon key ships inside the mobile app, so that is possible).
--   * Therefore the `authenticated` role is READ-ONLY on business data, except
--     for a customer editing their own name/phone and admins editing the
--     service catalogue. Bookings, assignments and payments are written only
--     by the backend.
--
-- Driver login ("ID + password"): Supabase Auth requires an email or phone, so
-- the backend (a later phase) creates each driver's auth user with a synthetic
-- email derived from `driver_login_id`, and stores the readable ID here.
-- =============================================================================

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role public.user_role not null default 'customer',
  full_name text,
  phone text,
  email text,
  driver_login_id text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint profiles_full_name_valid
    check (full_name is null or (btrim(full_name) <> '' and char_length(full_name) <= 120)),
  constraint profiles_phone_format
    check (phone is null or phone ~ '^\+?[0-9]{7,15}$'),
  constraint profiles_driver_login_id_format
    check (driver_login_id is null or driver_login_id ~ '^[a-z0-9][a-z0-9._-]{2,31}$'),
  -- A driver always has a login ID; nobody else may have one.
  constraint profiles_driver_login_id_matches_role
    check ((role = 'driver') = (driver_login_id is not null)),
  constraint profiles_driver_login_id_key unique (driver_login_id)
);

comment on table public.profiles is
  'One row per auth user. Holds the role and basic contact details.';
comment on column public.profiles.driver_login_id is
  'Human-readable driver ID chosen by the admin. Only set when role = driver.';

create index profiles_role_idx on public.profiles (role);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Privileged-column guard (defence in depth on top of column-level grants).
-- API roles (`anon`, `authenticated`) can never change role, activation state,
-- driver ID or email, even if a future grant accidentally allows it. The
-- backend (service_role) and migrations (postgres) are unaffected.
-- SECURITY INVOKER on purpose: current_user must be the caller.
-- -----------------------------------------------------------------------------
create function public.protect_profile_privileged_columns()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('anon', 'authenticated') then
    if new.id is distinct from old.id
       or new.role is distinct from old.role
       or new.driver_login_id is distinct from old.driver_login_id
       or new.is_active is distinct from old.is_active
       or new.email is distinct from old.email
       or new.created_at is distinct from old.created_at then
      raise exception 'Not allowed to modify privileged profile columns'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

create trigger profiles_protect_privileged_columns
  before update on public.profiles
  for each row execute function public.protect_profile_privileged_columns();

revoke all on function public.protect_profile_privileged_columns() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Auto-create a profile for every new auth user.
-- The role is ALWAYS 'customer'. user_metadata is client-controlled at sign-up,
-- so it must never be trusted for role. Drivers and admins are created or
-- promoted only by the backend / an operator.
-- -----------------------------------------------------------------------------
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, role, full_name, email)
  values (
    new.id,
    'customer',
    nullif(btrim(left(coalesce(new.raw_user_meta_data ->> 'full_name', ''), 120)), ''),
    new.email
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- SECURITY DEFINER: must not be reachable through the REST /rpc API.
revoke all on function public.handle_new_user() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Role helpers used by RLS policies in every later migration.
-- SECURITY DEFINER so they can read profiles without recursing into the
-- profiles policies. They return NULL / false for deactivated accounts.
-- -----------------------------------------------------------------------------
create function public.current_user_role()
returns public.user_role
language sql
stable
security definer
set search_path = ''
as $$
  select p.role
  from public.profiles p
  where p.id = (select auth.uid())
    and p.is_active
$$;

create function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select public.current_user_role()) = 'admin', false)
$$;

revoke all on function public.current_user_role() from public, anon;
revoke all on function public.is_admin() from public, anon;
grant execute on function public.current_user_role() to authenticated, service_role;
grant execute on function public.is_admin() to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- RLS + grants
-- -----------------------------------------------------------------------------
alter table public.profiles enable row level security;

revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;
-- Column-level grant: customers may only ever edit these two columns.
grant update (full_name, phone) on table public.profiles to authenticated;
grant all on table public.profiles to service_role;

create policy profiles_select_own
  on public.profiles for select to authenticated
  using (id = (select auth.uid()));

create policy profiles_select_admin
  on public.profiles for select to authenticated
  using ((select public.is_admin()));

-- Only customers self-edit. Driver details are managed by the admin.
create policy profiles_update_own_customer
  on public.profiles for update to authenticated
  using (id = (select auth.uid()) and role = 'customer')
  with check (id = (select auth.uid()) and role = 'customer');
