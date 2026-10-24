-- =============================================================================
-- Migration 6: authentication hardening (Phase 2)
-- =============================================================================
-- 1. Driver login IDs map to a synthetic email  <driver_id>@<driver_email_domain>.
--    The domain uses the reserved ".invalid" TLD, so no mail can ever be
--    delivered there (a password-recovery mail for a driver can never reach a
--    third party). The same domain is configured in:
--      backend/app/core/config.py      (driver_email_domain)
--      mobile/lib/core/config/app_config.dart (defaultDriverEmailDomain)
--    backend/tests/test_schema_consistency.py fails if they differ.
--
-- 2. Public sign-up must never be able to create or take over a driver ID.
--    Only the backend (Supabase Auth admin API) can set `app_metadata`; a user
--    cannot. So an account on the driver domain is accepted only when
--    app_metadata.managed_driver = true.
--
-- 3. handle_new_user() now also
--      * copies a VALID phone number from sign-up metadata, and
--      * creates the driver profile atomically (role = driver, driver_login_id)
--        when app_metadata says so. user_metadata is never trusted for role.
-- =============================================================================

create function public.driver_email_domain()
returns text
language sql
immutable
set search_path = ''
as $$
  select 'drivers.ffgarage.invalid'::text
$$;

revoke all on function public.driver_email_domain() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Guard trigger on auth.users. SECURITY DEFINER so it does not depend on the
-- privileges of the role GoTrue uses to write to auth.users.
-- -----------------------------------------------------------------------------
create function public.guard_driver_email()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_suffix text := '@' || public.driver_email_domain();
  v_managed boolean := coalesce(new.raw_app_meta_data ->> 'managed_driver', '') = 'true';
  v_new_is_driver boolean := right(lower(coalesce(new.email, '')), length(v_suffix)) = v_suffix;
begin
  if tg_op = 'INSERT' then
    if v_new_is_driver and not v_managed then
      raise exception 'Driver accounts can only be created by an administrator'
        using errcode = '42501';
    end if;
  elsif new.email is distinct from old.email then
    if right(lower(coalesce(old.email, '')), length(v_suffix)) = v_suffix then
      raise exception 'A driver login ID cannot be changed'
        using errcode = '42501';
    end if;
    if v_new_is_driver and not v_managed then
      raise exception 'Driver login IDs are reserved'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

create trigger guard_driver_email_on_insert
  before insert on auth.users
  for each row execute function public.guard_driver_email();

create trigger guard_driver_email_on_update
  before update of email on auth.users
  for each row execute function public.guard_driver_email();

revoke all on function public.guard_driver_email() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Profile creation (replaces the Phase 1 version; existing privileges stay).
-- -----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_driver_id text := case
    when coalesce(new.raw_app_meta_data ->> 'managed_driver', '') = 'true'
      then nullif(new.raw_app_meta_data ->> 'driver_login_id', '')
  end;
begin
  insert into public.profiles (id, role, driver_login_id, full_name, phone, email)
  values (
    new.id,
    case when v_driver_id is not null
      then 'driver'::public.user_role
      else 'customer'::public.user_role
    end,
    v_driver_id,
    nullif(btrim(left(coalesce(new.raw_user_meta_data ->> 'full_name', ''), 120)), ''),
    case when new.raw_user_meta_data ->> 'phone' ~ '^\+?[0-9]{7,15}$'
      then new.raw_user_meta_data ->> 'phone'
    end,
    new.email
  );
  return new;
end;
$$;
