-- =============================================================================
-- TEST-ONLY. Run after the shim and all migrations (see run_migration_tests.sh).
-- Every check raises NOTICE 'PASS: ...' or aborts the run with 'FAIL: ...'.
-- =============================================================================
\set ON_ERROR_STOP on
\set QUIET on

create schema test_helpers;
grant usage on schema test_helpers to public;

-- Become an API user for the rest of the transaction (RLS then applies).
create function test_helpers.as_user(p_user uuid, p_role text default 'authenticated')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
                     json_build_object('sub', p_user, 'role', p_role)::text, true);
  execute format('set local role %I', p_role);
end $$;

create function test_helpers.expect_error(p_sql text, p_sqlstate text, p_label text)
returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlstate = p_sqlstate then
      raise notice 'PASS: %', p_label;
      return;
    end if;
    raise exception 'FAIL: % - expected SQLSTATE % but got % (%)', p_label, p_sqlstate, sqlstate, sqlerrm;
  end;
  raise exception 'FAIL: % - expected SQLSTATE % but statement succeeded', p_label, p_sqlstate;
end $$;

create function test_helpers.expect_count(p_sql text, p_expected bigint, p_label text)
returns void language plpgsql as $$
declare v bigint;
begin
  execute 'select count(*) from (' || p_sql || ') q' into v;
  if v is distinct from p_expected then
    raise exception 'FAIL: % - expected % rows, got %', p_label, p_expected, v;
  end if;
  raise notice 'PASS: %', p_label;
end $$;

-- Runs a DML statement and asserts how many rows it touched.
create function test_helpers.expect_rows_affected(p_sql text, p_expected bigint, p_label text)
returns void language plpgsql as $$
declare v bigint;
begin
  execute p_sql;
  get diagnostics v = row_count;
  if v is distinct from p_expected then
    raise exception 'FAIL: % - expected % rows affected, got %', p_label, p_expected, v;
  end if;
  raise notice 'PASS: %', p_label;
end $$;

grant execute on all functions in schema test_helpers to public;

-- -----------------------------------------------------------------------------
-- Fixtures (committed, created as the superuser)
-- -----------------------------------------------------------------------------
-- cust_a  1111...  customer; sign-up metadata tries to claim role=admin
-- cust_b  2222...  customer
-- driver1 3333...  driver, assigned to booking A
-- driver2 4444...  driver, no assignments
-- admin1  5555...  admin
-- inactive 6666... deactivated customer with a booking
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'a@example.com', '{"role":"admin","full_name":"Alice A"}'),
  ('22222222-2222-2222-2222-222222222222', 'b@example.com', '{"full_name":"Bob B"}'),
  ('33333333-3333-3333-3333-333333333333', 'd1@drivers.test', '{}'),
  ('44444444-4444-4444-4444-444444444444', 'd2@drivers.test', '{}'),
  ('55555555-5555-5555-5555-555555555555', 'admin@example.com', '{}'),
  ('66666666-6666-6666-6666-666666666666', 'old@example.com', '{"full_name":"Old Customer"}');

do $$
begin
  if (select role from public.profiles where id = '11111111-1111-1111-1111-111111111111') <> 'customer' then
    raise exception 'FAIL: sign-up metadata must not be able to set role';
  end if;
  raise notice 'PASS: new auth user always gets role=customer, metadata role ignored';
  if (select full_name from public.profiles where id = '11111111-1111-1111-1111-111111111111') <> 'Alice A' then
    raise exception 'FAIL: full_name should be copied from metadata';
  end if;
  raise notice 'PASS: full_name copied from sign-up metadata';
end $$;

update public.profiles set role = 'driver', driver_login_id = 'driver01', phone = '+919800000001'
  where id = '33333333-3333-3333-3333-333333333333';
update public.profiles set role = 'driver', driver_login_id = 'driver02'
  where id = '44444444-4444-4444-4444-444444444444';
update public.profiles set role = 'admin' where id = '55555555-5555-5555-5555-555555555555';
update public.profiles set is_active = false where id = '66666666-6666-6666-6666-666666666666';

-- The migrations seed the 3 default services (checked in 00_service_seed_test.sql); these
-- tests count rows, so they start from an empty catalogue.
delete from public.services;

insert into public.services (id, name, vehicle_type, description, is_active) values
  ('a0000000-0000-0000-0000-000000000001', 'General Service', 'scooter', 'Routine service', true),
  ('a0000000-0000-0000-0000-000000000002', 'Legacy Service', 'bike', 'Retired', false),
  ('a0000000-0000-0000-0000-000000000003', 'Chain Service', 'bike', 'Chain clean and lube', true);

insert into public.service_packages (id, service_id, name, price, inclusions, is_active) values
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Basic', 499.00, array['Wash','Oil top-up'], true),
  ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Retired Pack', 299.00, '{}', false),
  ('b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000003', 'Chain Pack', 199.00, '{}', true);

insert into public.extra_charges (id, service_id, package_id, charge_type, name, amount) values
  ('c0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', null, 'engine_oil', 'Engine oil 10W-30', 350.00),
  ('c0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'spare_part', 'Air filter', null);

insert into public.service_areas (id, pincode, area_name, city, state, is_active) values
  ('d0000000-0000-0000-0000-000000000001', '462001', 'New Market', 'Bhopal', 'Madhya Pradesh', true),
  ('d0000000-0000-0000-0000-000000000002', '462002', 'Old Town', 'Bhopal', 'Madhya Pradesh', false);

insert into public.bookings
  (id, customer_id, service_id, package_id, vehicle_type, status, customer_name, customer_phone,
   address_line, city, state, pincode, service_area_id, scheduled_date, slot_start, slot_end,
   package_price, extra_charges_total, confirmed_at)
values
  ('e0000000-0000-0000-0000-00000000000a', '11111111-1111-1111-1111-111111111111',
   'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'scooter', 'assigned',
   'Alice A', '+919876543210', '12 MG Road', 'Bhopal', 'Madhya Pradesh', '462001',
   'd0000000-0000-0000-0000-000000000001', current_date + 1, '10:00', '12:00', 499.00, 350.00, now()),
  ('e0000000-0000-0000-0000-00000000000b', '22222222-2222-2222-2222-222222222222',
   'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'scooter', 'pending_payment',
   'Bob B', '+919876543211', '5 Park Street', 'Bhopal', 'Madhya Pradesh', '462001',
   'd0000000-0000-0000-0000-000000000001', current_date + 2, '14:00', '16:00', 499.00, 0, null),
  ('e0000000-0000-0000-0000-00000000000c', '66666666-6666-6666-6666-666666666666',
   'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'scooter', 'pending_payment',
   'Old Customer', '+919876543212', '9 Lake View', 'Bhopal', 'Madhya Pradesh', '462001',
   'd0000000-0000-0000-0000-000000000001', current_date + 3, '09:00', '11:00', 499.00, 0, null);

insert into public.driver_assignments (id, booking_id, driver_id, assigned_by) values
  ('f0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-00000000000a',
   '33333333-3333-3333-3333-333333333333', '55555555-5555-5555-5555-555555555555');

insert into public.payments (id, booking_id, customer_id, provider, provider_order_id, provider_payment_id, amount, status, paid_at) values
  ('90000000-0000-0000-0000-00000000000a', 'e0000000-0000-0000-0000-00000000000a',
   '11111111-1111-1111-1111-111111111111', 'testgw', 'order_A', 'pay_A', 849.00, 'successful', now()),
  ('90000000-0000-0000-0000-00000000000b', 'e0000000-0000-0000-0000-00000000000b',
   '22222222-2222-2222-2222-222222222222', 'testgw', 'order_B', null, 499.00, 'pending', null);

do $$ begin
  if (select total_amount from public.bookings where id = 'e0000000-0000-0000-0000-00000000000a') <> 849.00 then
    raise exception 'FAIL: total_amount should be generated as package_price + extra_charges_total';
  end if;
  raise notice 'PASS: bookings.total_amount is generated';
end $$;

-- -----------------------------------------------------------------------------
-- Customer A: own data only, no role escalation, read-only on business data
-- -----------------------------------------------------------------------------
begin;
select test_helpers.as_user('11111111-1111-1111-1111-111111111111');
do $$
begin
  perform test_helpers.expect_count('select 1 from public.profiles', 1, 'customer sees only own profile');
  perform test_helpers.expect_rows_affected(
    $q$update public.profiles set full_name = 'Alice Updated', phone = '+919811111111' where id = auth.uid()$q$,
    1, 'customer can edit own name and phone');
  perform test_helpers.expect_error(
    $q$update public.profiles set role = 'admin' where id = auth.uid()$q$, '42501',
    'customer cannot make themselves admin');
  perform test_helpers.expect_error(
    $q$update public.profiles set role = 'driver', driver_login_id = 'hacker01' where id = auth.uid()$q$, '42501',
    'customer cannot make themselves driver');
  perform test_helpers.expect_error(
    $q$update public.profiles set is_active = true where id = auth.uid()$q$, '42501',
    'customer cannot change is_active');
  perform test_helpers.expect_error(
    $q$update public.profiles set email = 'x@evil.test' where id = auth.uid()$q$, '42501',
    'customer cannot change email');
  perform test_helpers.expect_rows_affected(
    $q$update public.profiles set full_name = 'Hacked' where id = '22222222-2222-2222-2222-222222222222'$q$,
    0, 'customer cannot edit another profile');
  perform test_helpers.expect_error(
    $q$insert into public.profiles (id, role) values (gen_random_uuid(), 'admin')$q$, '42501',
    'customer cannot insert profiles');
  perform test_helpers.expect_error('delete from public.profiles', '42501', 'customer cannot delete profiles');

  perform test_helpers.expect_count('select 1 from public.bookings', 1, 'customer sees only own bookings');
  perform test_helpers.expect_count('select 1 from public.payments', 1, 'customer sees only own payments');
  perform test_helpers.expect_count('select 1 from public.driver_assignments', 0, 'customer sees no driver assignments');
  perform test_helpers.expect_error(
    $q$insert into public.bookings (customer_id, service_id, package_id, vehicle_type, customer_name, customer_phone,
         address_line, city, pincode, scheduled_date, slot_start, slot_end, package_price)
       values (auth.uid(), 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001',
         'scooter', 'A', '+919800000000', 'x', 'Bhopal', '462001', current_date + 1, '10:00', '11:00', 0)$q$,
    '42501', 'customer cannot insert bookings directly (price tampering)');
  perform test_helpers.expect_error(
    $q$update public.bookings set status = 'completed', completed_at = now()$q$, '42501',
    'customer cannot update bookings directly');
  perform test_helpers.expect_error(
    $q$insert into public.payments (booking_id, customer_id, provider, amount, status, paid_at, provider_payment_id)
       values ('e0000000-0000-0000-0000-00000000000a', auth.uid(), 'testgw', 1, 'successful', now(), 'fake')$q$,
    '42501', 'customer cannot forge a payment');
  perform test_helpers.expect_error(
    $q$insert into public.driver_assignments (booking_id, driver_id, assigned_by)
       values ('e0000000-0000-0000-0000-00000000000a', auth.uid(), auth.uid())$q$,
    '42501', 'customer cannot create driver assignments');

  perform test_helpers.expect_count('select 1 from public.services', 2, 'customer sees only active services');
  perform test_helpers.expect_count('select 1 from public.service_packages', 2, 'customer sees only active packages of active services');
  perform test_helpers.expect_count('select 1 from public.extra_charges', 2, 'customer sees active extra charges');
  perform test_helpers.expect_count('select 1 from public.service_areas', 1, 'customer sees only active service areas');
  perform test_helpers.expect_error(
    $q$insert into public.services (name, vehicle_type) values ('Free Service', 'bike')$q$, '42501',
    'customer cannot create services');
  perform test_helpers.expect_rows_affected(
    $q$update public.services set is_active = false$q$, 0, 'customer cannot modify services');
  perform test_helpers.expect_rows_affected(
    $q$delete from public.service_areas$q$, 0, 'customer cannot delete service areas');

  if public.is_admin() then raise exception 'FAIL: customer must not be admin'; end if;
  if public.current_user_role() <> 'customer' then raise exception 'FAIL: wrong role for customer'; end if;
  raise notice 'PASS: role helpers report customer correctly';
end $$;
reset role;
rollback;

-- Even if a future migration accidentally granted column UPDATE on role, the
-- trigger layer must still stop the API roles.
begin;
grant update (role, driver_login_id, is_active) on public.profiles to authenticated;
select test_helpers.as_user('11111111-1111-1111-1111-111111111111');
do $$
begin
  perform test_helpers.expect_error(
    $q$update public.profiles set role = 'admin' where id = auth.uid()$q$, '42501',
    'trigger blocks role escalation even if a column grant leaks');
  perform test_helpers.expect_error(
    $q$update public.profiles set is_active = false where id = auth.uid()$q$, '42501',
    'trigger blocks is_active change even if a column grant leaks');
  perform test_helpers.expect_error(
    $q$update public.profiles set role = 'driver', driver_login_id = 'sneaky01' where id = auth.uid()$q$, '42501',
    'trigger blocks self-promotion to driver even if a column grant leaks');
end $$;
reset role;
rollback;

-- -----------------------------------------------------------------------------
-- Customer B
-- -----------------------------------------------------------------------------
begin;
select test_helpers.as_user('22222222-2222-2222-2222-222222222222');
do $$
begin
  perform test_helpers.expect_count($q$select 1 from public.bookings where id = 'e0000000-0000-0000-0000-00000000000b'$q$, 1, 'customer B sees own booking');
  perform test_helpers.expect_count($q$select 1 from public.bookings where id = 'e0000000-0000-0000-0000-00000000000a'$q$, 0, 'customer B cannot see customer A booking');
  perform test_helpers.expect_count($q$select 1 from public.payments where id = '90000000-0000-0000-0000-00000000000a'$q$, 0, 'customer B cannot see customer A payment');
end $$;
reset role;
rollback;

-- -----------------------------------------------------------------------------
-- Driver 1 (assigned to booking A) and Driver 2 (nothing assigned)
-- -----------------------------------------------------------------------------
begin;
select test_helpers.as_user('33333333-3333-3333-3333-333333333333');
do $$
begin
  perform test_helpers.expect_count('select 1 from public.bookings', 1, 'driver sees only assigned bookings');
  perform test_helpers.expect_count($q$select 1 from public.bookings where id = 'e0000000-0000-0000-0000-00000000000a'$q$, 1, 'driver sees the booking assigned to them');
  perform test_helpers.expect_count('select 1 from public.driver_assignments', 1, 'driver sees own assignment');
  perform test_helpers.expect_count('select 1 from public.profiles', 1, 'driver sees only own profile (no customer profiles)');
  perform test_helpers.expect_count('select 1 from public.payments', 0, 'driver cannot see payments');
  perform test_helpers.expect_error(
    $q$update public.bookings set status = 'completed', completed_at = now()$q$, '42501',
    'driver cannot update bookings directly (status changes go through the backend)');
  perform test_helpers.expect_rows_affected(
    $q$update public.profiles set full_name = 'Renamed' where id = auth.uid()$q$, 0,
    'driver cannot self-edit profile (admin-managed)');
  perform test_helpers.expect_error(
    $q$update public.driver_assignments set is_active = false, unassigned_at = now()$q$, '42501',
    'driver cannot change assignments');
  if public.current_user_role() <> 'driver' then raise exception 'FAIL: wrong role for driver'; end if;
  raise notice 'PASS: role helpers report driver correctly';
end $$;
reset role;
rollback;

begin;
select test_helpers.as_user('44444444-4444-4444-4444-444444444444');
do $$
begin
  perform test_helpers.expect_count('select 1 from public.bookings', 0, 'unassigned driver sees no bookings');
  perform test_helpers.expect_count('select 1 from public.driver_assignments', 0, 'unassigned driver sees no assignments');
end $$;
reset role;
rollback;

-- A deactivated assignment (reassignment) must revoke the old driver's access.
begin;
update public.driver_assignments set is_active = false, unassigned_at = now()
  where id = 'f0000000-0000-0000-0000-000000000001';
select test_helpers.as_user('33333333-3333-3333-3333-333333333333');
do $$
begin
  perform test_helpers.expect_count('select 1 from public.bookings', 0, 'driver loses access after being unassigned');
end $$;
reset role;
rollback;

-- -----------------------------------------------------------------------------
-- Admin: reads everything, manages catalogue, still cannot write bookings/payments
-- -----------------------------------------------------------------------------
begin;
select test_helpers.as_user('55555555-5555-5555-5555-555555555555');
do $$
begin
  perform test_helpers.expect_count('select 1 from public.profiles', 6, 'admin sees all profiles');
  perform test_helpers.expect_count('select 1 from public.bookings', 3, 'admin sees all bookings');
  perform test_helpers.expect_count('select 1 from public.payments', 2, 'admin sees all payments');
  perform test_helpers.expect_count('select 1 from public.driver_assignments', 1, 'admin sees all assignments');
  perform test_helpers.expect_count('select 1 from public.services', 3, 'admin sees inactive services too');
  perform test_helpers.expect_count('select 1 from public.service_areas', 2, 'admin sees inactive areas too');
  perform test_helpers.expect_rows_affected(
    $q$update public.service_areas set is_active = true where pincode = '462002'$q$, 1, 'admin can activate a service area');
  perform test_helpers.expect_rows_affected(
    $q$insert into public.service_areas (pincode, area_name, city, state) values ('462003', 'Arera Colony', 'Bhopal', 'Madhya Pradesh')$q$,
    1, 'admin can add a service area');
  perform test_helpers.expect_rows_affected(
    $q$insert into public.services (name, vehicle_type) values ('Brake Service', 'bike')$q$, 1, 'admin can add a service');
  perform test_helpers.expect_error(
    $q$update public.profiles set role = 'admin' where id = '11111111-1111-1111-1111-111111111111'$q$, '42501',
    'admin cannot change roles through the API either (backend only)');
  perform test_helpers.expect_error(
    $q$update public.bookings set status = 'cancelled', cancelled_at = now()$q$, '42501',
    'admin cannot write bookings through the API (backend only)');
  perform test_helpers.expect_error(
    $q$delete from public.payments$q$, '42501', 'admin cannot delete payments through the API');
  if not public.is_admin() then raise exception 'FAIL: admin should be admin'; end if;
  raise notice 'PASS: role helpers report admin correctly';
end $$;
reset role;
rollback;

-- -----------------------------------------------------------------------------
-- Deactivated customer
-- -----------------------------------------------------------------------------
begin;
select test_helpers.as_user('66666666-6666-6666-6666-666666666666');
do $$
begin
  perform test_helpers.expect_count('select 1 from public.bookings', 0, 'deactivated customer sees no bookings');
  perform test_helpers.expect_count('select 1 from public.payments', 0, 'deactivated customer sees no payments');
  if public.current_user_role() is not null then raise exception 'FAIL: deactivated user must have no role'; end if;
  raise notice 'PASS: deactivated user has no effective role';
end $$;
reset role;
rollback;

-- -----------------------------------------------------------------------------
-- anon (no login) and service_role
-- -----------------------------------------------------------------------------
begin;
select test_helpers.as_user('00000000-0000-0000-0000-000000000000', 'anon');
do $$
begin
  perform test_helpers.expect_error('select 1 from public.profiles', '42501', 'anon cannot read profiles');
  perform test_helpers.expect_error('select 1 from public.bookings', '42501', 'anon cannot read bookings');
  perform test_helpers.expect_error('select 1 from public.payments', '42501', 'anon cannot read payments');
  perform test_helpers.expect_error('select 1 from public.services', '42501', 'anon cannot read services');
  perform test_helpers.expect_error('select 1 from public.service_areas', '42501', 'anon cannot read service areas');
  perform test_helpers.expect_error('select public.is_admin()', '42501', 'anon cannot call is_admin()');
end $$;
reset role;
rollback;

begin;
select test_helpers.as_user('00000000-0000-0000-0000-000000000000', 'service_role');
do $$
begin
  perform test_helpers.expect_count('select 1 from public.bookings', 3, 'service_role bypasses RLS (backend access)');
  perform test_helpers.expect_rows_affected(
    $q$update public.profiles set role = 'driver', driver_login_id = 'driver03' where id = '22222222-2222-2222-2222-222222222222'$q$,
    1, 'service_role can change roles (admin creates drivers via backend)');
  perform test_helpers.expect_rows_affected(
    $q$insert into public.driver_assignments (booking_id, driver_id, assigned_by)
       values ('e0000000-0000-0000-0000-00000000000b', '44444444-4444-4444-4444-444444444444', '55555555-5555-5555-5555-555555555555')$q$,
    1, 'service_role can assign drivers (validation trigger still fires without EXECUTE grants)');
  perform test_helpers.expect_error(
    $q$insert into public.driver_assignments (booking_id, driver_id, assigned_by)
       values ('e0000000-0000-0000-0000-00000000000c', '11111111-1111-1111-1111-111111111111', '55555555-5555-5555-5555-555555555555')$q$,
    '23514', 'validation trigger rejects a non-driver even for service_role');
end $$;

-- Trigger functions must not be callable through the REST /rpc API.
reset role;
rollback;

begin;
select test_helpers.as_user('11111111-1111-1111-1111-111111111111');
do $$
begin
  perform test_helpers.expect_error('select public.handle_new_user()', '42501', 'authenticated cannot call handle_new_user()');
  perform test_helpers.expect_error('select public.validate_driver_assignment()', '42501', 'authenticated cannot call validate_driver_assignment()');
  perform test_helpers.expect_error('select public.set_updated_at()', '42501', 'authenticated cannot call set_updated_at()');
  perform test_helpers.expect_error('select public.protect_profile_privileged_columns()', '42501', 'authenticated cannot call protect_profile_privileged_columns()');
end $$;
reset role;
rollback;

-- -----------------------------------------------------------------------------
-- Constraint and integrity checks (run as superuser, so RLS is not involved)
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_booking_cols text := $c$(customer_id, service_id, package_id, vehicle_type, customer_name, customer_phone,
      address_line, city, pincode, scheduled_date, slot_start, slot_end, package_price)$c$;
  v_ok_values text := $c$('11111111-1111-1111-1111-111111111111', 'a0000000-0000-0000-0000-000000000001',
      'b0000000-0000-0000-0000-000000000001', 'scooter', 'Alice', '+919800000000', 'x', 'Bhopal',
      '462001', current_date + 1, '10:00', '11:00', 100)$c$;
begin
  -- bookings
  perform test_helpers.expect_rows_affected('insert into public.bookings ' || v_booking_cols || ' values ' || v_ok_values, 1, 'valid booking inserts');
  perform test_helpers.expect_error('insert into public.bookings ' || v_booking_cols || ' values ' || replace(v_ok_values, '''462001''', '''12345'''), '23514', 'booking rejects malformed PIN code');
  perform test_helpers.expect_error('insert into public.bookings ' || v_booking_cols || ' values ' || replace(v_ok_values, '''11:00''', '''09:00'''), '23514', 'booking rejects slot_end <= slot_start');
  perform test_helpers.expect_error('insert into public.bookings ' || v_booking_cols || ' values ' || replace(v_ok_values, ', 100)', ', -1)'), '23514', 'booking rejects negative price');
  perform test_helpers.expect_error('insert into public.bookings ' || v_booking_cols || ' values ' || replace(v_ok_values, '+919800000000', 'abc'), '23514', 'booking rejects bad phone');
  perform test_helpers.expect_error('insert into public.bookings ' || v_booking_cols || ' values ' || replace(replace(v_ok_values, 'current_date + 1', 'current_date + 9'), 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000003'), '23503', 'booking rejects package that belongs to a different service');
  perform test_helpers.expect_error('insert into public.bookings ' || v_booking_cols || ' values ' || replace(v_ok_values, '11111111-1111-1111-1111-111111111111', '99999999-9999-9999-9999-999999999999'), '23503', 'booking rejects unknown customer');
  perform test_helpers.expect_error(
    $q$insert into public.bookings (customer_id, service_id, package_id, vehicle_type, customer_name, customer_phone,
         address_line, city, pincode, latitude, scheduled_date, slot_start, slot_end, package_price)
       values ('11111111-1111-1111-1111-111111111111', 'a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001',
         'scooter', 'A', '+919800000000', 'x', 'Bhopal', '462001', 23.25, current_date + 1, '10:00', '11:00', 1)$q$,
    '23514', 'booking rejects latitude without longitude');
  perform test_helpers.expect_error(
    $q$update public.bookings set status = 'completed' where id = 'e0000000-0000-0000-0000-00000000000a'$q$,
    '23514', 'booking cannot be completed without completed_at');
  perform test_helpers.expect_error(
    $q$update public.bookings set status = 'confirmed' where id = 'e0000000-0000-0000-0000-00000000000b'$q$,
    '23514', 'booking cannot be confirmed without confirmed_at');
  perform test_helpers.expect_error(
    $q$delete from public.service_packages where id = 'b0000000-0000-0000-0000-000000000001'$q$,
    '23503', 'package with bookings cannot be deleted (disable it instead)');
  perform test_helpers.expect_error(
    $q$delete from public.profiles where id = '11111111-1111-1111-1111-111111111111'$q$,
    '23503', 'customer with bookings cannot be deleted');
end $$;
rollback;

begin;
do $$
begin
  -- driver assignments
  perform test_helpers.expect_error(
    $q$insert into public.driver_assignments (booking_id, driver_id, assigned_by)
       values ('e0000000-0000-0000-0000-00000000000a', '44444444-4444-4444-4444-444444444444', '55555555-5555-5555-5555-555555555555')$q$,
    '23505', 'second active driver on a booking is rejected');
  perform test_helpers.expect_error(
    $q$insert into public.driver_assignments (booking_id, driver_id, assigned_by)
       values ('e0000000-0000-0000-0000-00000000000b', '22222222-2222-2222-2222-222222222222', '55555555-5555-5555-5555-555555555555')$q$,
    '23514', 'cannot assign a customer as driver');
  perform test_helpers.expect_error(
    $q$insert into public.driver_assignments (booking_id, driver_id, assigned_by)
       values ('e0000000-0000-0000-0000-00000000000b', '33333333-3333-3333-3333-333333333333', '22222222-2222-2222-2222-222222222222')$q$,
    '23514', 'assigned_by must be an admin');
  perform test_helpers.expect_error(
    $q$update public.driver_assignments set driver_id = '44444444-4444-4444-4444-444444444444'$q$,
    '23514', 'assignment driver_id is immutable');
  perform test_helpers.expect_error(
    $q$update public.driver_assignments set is_active = false$q$,
    '23514', 'inactive assignment must record unassigned_at');
end $$;
-- Reassignment flow: deactivate the old row, then insert a new active one.
update public.driver_assignments set is_active = false, unassigned_at = now()
  where id = 'f0000000-0000-0000-0000-000000000001';
insert into public.driver_assignments (booking_id, driver_id, assigned_by)
  values ('e0000000-0000-0000-0000-00000000000a', '44444444-4444-4444-4444-444444444444', '55555555-5555-5555-5555-555555555555');
do $$
begin
  perform test_helpers.expect_count($q$select 1 from public.driver_assignments where booking_id = 'e0000000-0000-0000-0000-00000000000a'$q$, 2, 'reassignment keeps assignment history');
  perform test_helpers.expect_count($q$select 1 from public.driver_assignments where booking_id = 'e0000000-0000-0000-0000-00000000000a' and is_active$q$, 1, 'exactly one active assignment after reassignment');
end $$;
rollback;

begin;
update public.profiles set is_active = false where id = '44444444-4444-4444-4444-444444444444';
do $$
begin
  perform test_helpers.expect_error(
    $q$insert into public.driver_assignments (booking_id, driver_id, assigned_by)
       values ('e0000000-0000-0000-0000-00000000000b', '44444444-4444-4444-4444-444444444444', '55555555-5555-5555-5555-555555555555')$q$,
    '23514', 'cannot assign to a deactivated driver');
end $$;
rollback;

begin;
do $$
begin
  -- payments
  perform test_helpers.expect_error(
    $q$insert into public.payments (booking_id, customer_id, provider, provider_payment_id, amount, status, paid_at)
       values ('e0000000-0000-0000-0000-00000000000a', '11111111-1111-1111-1111-111111111111', 'testgw', 'pay_other', 849, 'successful', now())$q$,
    '23505', 'second successful payment for a booking is rejected');
  perform test_helpers.expect_error(
    $q$insert into public.payments (booking_id, customer_id, provider, provider_payment_id, amount, status, paid_at)
       values ('e0000000-0000-0000-0000-00000000000b', '22222222-2222-2222-2222-222222222222', 'testgw', 'pay_A', 499, 'successful', now())$q$,
    '23505', 'replayed gateway transaction id is rejected');
  perform test_helpers.expect_error(
    $q$insert into public.payments (booking_id, customer_id, provider, provider_order_id, amount)
       values ('e0000000-0000-0000-0000-00000000000b', '22222222-2222-2222-2222-222222222222', 'testgw', 'order_B', 499)$q$,
    '23505', 'duplicate gateway order id is rejected');
  perform test_helpers.expect_error(
    $q$insert into public.payments (booking_id, customer_id, provider, amount, status)
       values ('e0000000-0000-0000-0000-00000000000b', '22222222-2222-2222-2222-222222222222', 'testgw', 499, 'successful')$q$,
    '23514', 'successful payment requires paid_at and transaction reference');
  perform test_helpers.expect_error(
    $q$insert into public.payments (booking_id, customer_id, provider, amount, paid_at)
       values ('e0000000-0000-0000-0000-00000000000b', '22222222-2222-2222-2222-222222222222', 'testgw', 499, now())$q$,
    '23514', 'pending payment cannot have paid_at');
  perform test_helpers.expect_error(
    $q$insert into public.payments (booking_id, customer_id, provider, amount, status)
       values ('e0000000-0000-0000-0000-00000000000b', '11111111-1111-1111-1111-111111111111', 'testgw', 499, 'failed')$q$,
    '23503', 'payment customer must match the booking customer');
  perform test_helpers.expect_error(
    $q$insert into public.payments (booking_id, customer_id, provider, amount)
       values ('e0000000-0000-0000-0000-00000000000b', '22222222-2222-2222-2222-222222222222', 'testgw', 0)$q$,
    '23514', 'payment amount must be positive');
  perform test_helpers.expect_rows_affected(
    $q$insert into public.payments (booking_id, customer_id, provider, provider_order_id, amount, status, failure_reason)
       values ('e0000000-0000-0000-0000-00000000000b', '22222222-2222-2222-2222-222222222222', 'testgw', 'order_B2', 499, 'failed', 'card declined'),
              ('e0000000-0000-0000-0000-00000000000b', '22222222-2222-2222-2222-222222222222', 'testgw', 'order_B3', 499, 'failed', 'timeout')$q$,
    2, 'multiple failed attempts per booking are allowed');
  perform test_helpers.expect_rows_affected(
    $q$insert into public.payments (booking_id, customer_id, provider, amount, idempotency_key, status)
       values ('e0000000-0000-0000-0000-00000000000b', '22222222-2222-2222-2222-222222222222', 'testgw', 499, 'idem-1', 'failed')$q$,
    1, 'payment with idempotency key inserts');
  perform test_helpers.expect_error(
    $q$insert into public.payments (booking_id, customer_id, provider, amount, idempotency_key, status)
       values ('e0000000-0000-0000-0000-00000000000b', '22222222-2222-2222-2222-222222222222', 'testgw', 499, 'idem-1', 'failed')$q$,
    '23505', 'duplicate idempotency key for the same customer is rejected');
end $$;
rollback;

begin;
do $$
begin
  -- catalogue, areas, profiles
  perform test_helpers.expect_error(
    $q$insert into public.services (name, vehicle_type) values ('general service', 'scooter')$q$,
    '23505', 'service names are unique per vehicle type, case-insensitively');
  perform test_helpers.expect_rows_affected(
    $q$insert into public.services (name, vehicle_type) values ('General Service', 'bike')$q$,
    1, 'same service name is allowed for a different vehicle type');
  perform test_helpers.expect_error(
    $q$insert into public.service_packages (service_id, name, price) values ('a0000000-0000-0000-0000-000000000001', 'Bad', -5)$q$,
    '23514', 'package price cannot be negative');
  perform test_helpers.expect_error(
    $q$insert into public.extra_charges (service_id, package_id, name, amount)
       values ('a0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000003', 'Mismatch', 10)$q$,
    '23503', 'extra charge package must belong to the same service');
  perform test_helpers.expect_error(
    $q$insert into public.extra_charges (service_id, name, amount) values ('a0000000-0000-0000-0000-000000000001', 'Neg', -1)$q$,
    '23514', 'extra charge amount cannot be negative');
  perform test_helpers.expect_error(
    $q$insert into public.service_areas (pincode, area_name, city, state) values ('462001', 'Dup', 'Bhopal', 'MP')$q$,
    '23505', 'PIN code is unique');
  perform test_helpers.expect_error(
    $q$insert into public.service_areas (pincode, area_name, city, state) values ('062001', 'Bad', 'Bhopal', 'MP')$q$,
    '23514', 'PIN code cannot start with 0');
  perform test_helpers.expect_error(
    $q$update public.profiles set role = 'driver' where id = '11111111-1111-1111-1111-111111111111'$q$,
    '23514', 'driver role requires a driver_login_id');
  perform test_helpers.expect_error(
    $q$update public.profiles set driver_login_id = 'abc123' where id = '11111111-1111-1111-1111-111111111111'$q$,
    '23514', 'only drivers may have a driver_login_id');
  perform test_helpers.expect_error(
    $q$update public.profiles set role = 'driver', driver_login_id = 'driver01' where id = '11111111-1111-1111-1111-111111111111'$q$,
    '23505', 'driver_login_id is unique');
  perform test_helpers.expect_error(
    $q$update public.profiles set phone = 'call-me' where id = '11111111-1111-1111-1111-111111111111'$q$,
    '23514', 'profile phone format is validated');
end $$;
rollback;

-- updated_at trigger (fixtures were committed in an earlier transaction)
begin;
update public.services set description = 'changed' where id = 'a0000000-0000-0000-0000-000000000001';
do $$
begin
  if (select updated_at > created_at from public.services where id = 'a0000000-0000-0000-0000-000000000001') is not true then
    raise exception 'FAIL: updated_at was not bumped';
  end if;
  raise notice 'PASS: updated_at trigger bumps the timestamp';
end $$;
rollback;

select 'ALL CHECKS COMPLETED' as result;
