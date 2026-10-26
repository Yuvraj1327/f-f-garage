-- =============================================================================
-- TEST-ONLY. Garage business details: API roles cannot read or write them (only
-- the backend's service role does) and the table holds a single row.
-- =============================================================================
\set ON_ERROR_STOP on
\set QUIET on

begin;
select test_helpers.as_user('11111111-1111-1111-1111-111111111111');
select test_helpers.expect_error(
  $q$select * from public.garage_settings$q$, '42501',
  'a customer cannot read the garage settings table');
select test_helpers.expect_error(
  $q$insert into public.garage_settings (name) values ('Mine')$q$, '42501',
  'a customer cannot write the garage settings table');
reset role;
rollback;

begin;
select test_helpers.as_user('55555555-5555-5555-5555-555555555555');
select test_helpers.expect_error(
  $q$select * from public.garage_settings$q$, '42501',
  'even an admin goes through the API, not the table');
reset role;
rollback;

begin;
insert into public.garage_settings (name, phone) values ('F&F Garage', '+919876543210');
select test_helpers.expect_error(
  $q$insert into public.garage_settings (id, name) values (false, 'Second')$q$, '23514',
  'only one settings row can exist');
select test_helpers.expect_error(
  $q$update public.garage_settings set name = '   '$q$, '23514',
  'the garage name cannot be blank');
rollback;
