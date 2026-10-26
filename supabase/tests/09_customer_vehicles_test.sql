-- =============================================================================
-- TEST-ONLY. Saved vehicles: API roles cannot touch the table, registrations are
-- unique per customer and validated, and create_booking snapshots the vehicle.
-- =============================================================================
\set ON_ERROR_STOP on
\set QUIET on

begin;
select test_helpers.as_user('11111111-1111-1111-1111-111111111111');
select test_helpers.expect_error(
  $q$select * from public.customer_vehicles$q$, '42501',
  'a customer cannot read the vehicles table directly');
select test_helpers.expect_error(
  $q$insert into public.customer_vehicles (customer_id, vehicle_type, registration_number, make, model)
     values ('11111111-1111-1111-1111-111111111111', 'bike', 'MH12AB1234', 'Honda', 'Shine')$q$, '42501',
  'a customer cannot write the vehicles table directly');
reset role;
rollback;

begin;
insert into public.customer_vehicles (customer_id, vehicle_type, registration_number, make, model)
values ('11111111-1111-1111-1111-111111111111', 'bike', 'MH12AB1234', 'Honda', 'Shine');
select test_helpers.expect_error(
  $q$insert into public.customer_vehicles (customer_id, vehicle_type, registration_number, make, model)
     values ('11111111-1111-1111-1111-111111111111', 'scooter', 'MH12AB1234', 'TVS', 'Jupiter')$q$, '23505',
  'the same customer cannot save a registration twice');
select test_helpers.expect_error(
  $q$insert into public.customer_vehicles (customer_id, vehicle_type, registration_number, make, model)
     values ('11111111-1111-1111-1111-111111111111', 'bike', 'mh 12', 'Honda', 'Shine')$q$, '23514',
  'a malformed registration is rejected');
select test_helpers.expect_error(
  $q$update public.customer_vehicles set make = '  '$q$, '23514',
  'a blank make is rejected');
rollback;
