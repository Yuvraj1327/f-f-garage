-- =============================================================================
-- TEST-ONLY. Phase 2: sign-up/profile creation, driver-ID protection and extra
-- unauthorized-access checks. Runs after 01_rls_and_constraints_test.sql and
-- reuses its committed fixtures and test_helpers schema.
-- =============================================================================
\set ON_ERROR_STOP on
\set QUIET on

-- -----------------------------------------------------------------------------
-- Sign-up as the real writer role (supabase_auth_admin has no access to the
-- public schema, so this proves the triggers do not depend on its privileges)
-- -----------------------------------------------------------------------------
begin;
select test_helpers.as_user('00000000-0000-0000-0000-000000000000', 'supabase_auth_admin');
insert into auth.users (id, email, raw_user_meta_data) values
  ('a1000000-0000-0000-0000-000000000001', 'new@example.com',
   '{"full_name":"  New Person  ","phone":"+919812345678","role":"admin"}'),
  ('a1000000-0000-0000-0000-000000000002', 'badphone@example.com',
   '{"full_name":"Bad Phone","phone":"call me"}'),
  ('a1000000-0000-0000-0000-000000000003', 'meta@example.com',
   '{"managed_driver":true,"driver_login_id":"hacker01","role":"driver"}');
reset role;
do $$
begin
  if (select (role, full_name, phone) from public.profiles where id = 'a1000000-0000-0000-0000-000000000001')::text
       is distinct from '(customer,"New Person",+919812345678)' then
    raise exception 'FAIL: sign-up profile wrong: %',
      (select (role, full_name, phone) from public.profiles where id = 'a1000000-0000-0000-0000-000000000001');
  end if;
  raise notice 'PASS: sign-up as supabase_auth_admin creates a customer profile with name and phone (role in metadata ignored)';
  if (select phone from public.profiles where id = 'a1000000-0000-0000-0000-000000000002') is not null then
    raise exception 'FAIL: an invalid phone must be dropped, not stored';
  end if;
  raise notice 'PASS: invalid phone in sign-up metadata is dropped instead of failing sign-up';
  if (select role from public.profiles where id = 'a1000000-0000-0000-0000-000000000003') <> 'customer' then
    raise exception 'FAIL: user_metadata must never make a driver';
  end if;
  raise notice 'PASS: managed_driver / role in user_metadata cannot create a driver';
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Driver ID protection
-- -----------------------------------------------------------------------------
begin;
-- An admin-created driver account to try to tamper with.
insert into auth.users (id, email, raw_app_meta_data) values
  ('a3000000-0000-0000-0000-000000000001', 'driver77@drivers.ffgarage.invalid',
   '{"managed_driver":true,"driver_login_id":"driver77"}');
select test_helpers.as_user('00000000-0000-0000-0000-000000000000', 'supabase_auth_admin');
do $$
begin
  perform test_helpers.expect_error(
    $q$insert into auth.users (email) values ('driver99@drivers.ffgarage.invalid')$q$, '42501',
    'public sign-up cannot create an account on the driver domain');
  perform test_helpers.expect_error(
    $q$insert into auth.users (email) values ('Driver99@DRIVERS.FFGARAGE.INVALID')$q$, '42501',
    'driver-domain check is case-insensitive');
  perform test_helpers.expect_error(
    $q$insert into auth.users (email, raw_user_meta_data) values ('driver99@drivers.ffgarage.invalid', '{"managed_driver":true}')$q$, '42501',
    'managed_driver in user_metadata does not unlock the driver domain');
  perform test_helpers.expect_error(
    $q$update auth.users set email = 'driver98@drivers.ffgarage.invalid' where id = '11111111-1111-1111-1111-111111111111'$q$, '42501',
    'an existing user cannot change their email to a driver ID');
  perform test_helpers.expect_error(
    $q$update auth.users set email = 'real@example.com' where id = 'a3000000-0000-0000-0000-000000000001'$q$, '42501',
    'driver accounts on the driver domain cannot change email');
  perform test_helpers.expect_rows_affected(
    $q$update auth.users set raw_user_meta_data = '{"x":1}' where id = 'a3000000-0000-0000-0000-000000000001'$q$, 1,
    'other changes to a driver auth user are still allowed');
end $$;
reset role;
rollback;

-- Admin-created driver (what the backend does through the Auth admin API)
begin;
select test_helpers.as_user('00000000-0000-0000-0000-000000000000', 'supabase_auth_admin');
insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data) values
  ('a2000000-0000-0000-0000-000000000001', 'driver99@drivers.ffgarage.invalid',
   '{"managed_driver":true,"driver_login_id":"driver99"}', '{"full_name":"Driver Ninety-Nine","phone":"+919800000099"}');
reset role;
do $$
begin
  if (select (role, driver_login_id, full_name, phone, is_active) from public.profiles
        where id = 'a2000000-0000-0000-0000-000000000001')::text
       is distinct from '(driver,driver99,"Driver Ninety-Nine",+919800000099,t)' then
    raise exception 'FAIL: managed driver profile wrong: %',
      (select (role, driver_login_id, full_name, phone, is_active) from public.profiles where id = 'a2000000-0000-0000-0000-000000000001');
  end if;
  raise notice 'PASS: admin-created driver gets role=driver and driver_login_id atomically';
end $$;
select test_helpers.as_user('00000000-0000-0000-0000-000000000000', 'supabase_auth_admin');
do $$
begin
  perform test_helpers.expect_error(
    $q$insert into auth.users (email, raw_app_meta_data) values ('other@drivers.ffgarage.invalid', '{"managed_driver":true,"driver_login_id":"driver99"}')$q$, '23505',
    'duplicate driver_login_id is rejected at creation');
  perform test_helpers.expect_error(
    $q$insert into auth.users (email, raw_app_meta_data) values ('x@drivers.ffgarage.invalid', '{"managed_driver":true,"driver_login_id":"BAD ID"}')$q$, '23514',
    'invalid driver_login_id is rejected at creation');
end $$;
reset role;
rollback;

-- -----------------------------------------------------------------------------
-- More unauthorized-access attempts through the API roles
-- -----------------------------------------------------------------------------
begin;
select test_helpers.as_user('11111111-1111-1111-1111-111111111111');
do $$
begin
  perform test_helpers.expect_count($q$select 1 from public.profiles where role = 'driver'$q$, 0, 'customer cannot read driver profiles');
  perform test_helpers.expect_count($q$select 1 from public.profiles where role = 'admin'$q$, 0, 'customer cannot read admin profiles');
  perform test_helpers.expect_count($q$select 1 from public.profiles where id <> auth.uid()$q$, 0, 'customer cannot read any other profile');
  perform test_helpers.expect_error(
    $q$update public.profiles set phone = 'not-a-number' where id = auth.uid()$q$, '23514',
    'customer cannot store an invalid phone number');
  perform test_helpers.expect_error('select public.driver_email_domain()', '42501', 'authenticated cannot call driver_email_domain()');
  perform test_helpers.expect_error('select 1 from auth.users', '42501', 'customer cannot read auth.users');
end $$;
reset role;
rollback;

begin;
select test_helpers.as_user('33333333-3333-3333-3333-333333333333');
do $$
begin
  perform test_helpers.expect_count($q$select 1 from public.profiles where id <> auth.uid()$q$, 0, 'driver cannot read other drivers, customers or admins');
  perform test_helpers.expect_count($q$select 1 from public.profiles where driver_login_id is not null$q$, 1, 'driver sees only their own driver ID');
end $$;
reset role;
rollback;

begin;
select test_helpers.as_user('00000000-0000-0000-0000-000000000000', 'anon');
do $$
begin
  perform test_helpers.expect_error('select public.driver_email_domain()', '42501', 'anon cannot call driver_email_domain()');
  perform test_helpers.expect_error('select 1 from auth.users', '42501', 'anon cannot read auth.users');
end $$;
reset role;
rollback;

select 'PHASE 2 DB CHECKS COMPLETED' as result;
