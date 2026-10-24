-- =============================================================================
-- TEST-ONLY. Phase 3: service categories, PIN codes, time slots, availability
-- exceptions, and who may read/write them. Reuses the fixtures and
-- test_helpers of 01_rls_and_constraints_test.sql.
-- =============================================================================
\set ON_ERROR_STOP on
\set QUIET on

-- -----------------------------------------------------------------------------
-- services.category
-- -----------------------------------------------------------------------------
begin;
do $$
begin
  if (select category from public.services where id = 'a0000000-0000-0000-0000-000000000001') <> 'General' then
    raise exception 'FAIL: existing services should get the default category';
  end if;
  raise notice 'PASS: services get a default category';
  perform test_helpers.expect_error(
    $q$insert into public.services (name, vehicle_type, category) values ('X Service', 'bike', '   ')$q$,
    '23514', 'blank category rejected');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- time_slots: validity, normalisation, overlap
-- -----------------------------------------------------------------------------
begin;
do $$
begin
  insert into public.time_slots (id, start_time, end_time, capacity, days_of_week) values
    ('a5000000-0000-0000-0000-000000000001', '09:00', '11:00', 2, '{3,1,1,2}');
  if (select days_of_week from public.time_slots where id = 'a5000000-0000-0000-0000-000000000001') <> '{1,2,3}'::smallint[] then
    raise exception 'FAIL: days_of_week should be sorted and de-duplicated';
  end if;
  raise notice 'PASS: days_of_week is normalised';

  perform test_helpers.expect_error(
    $q$insert into public.time_slots (start_time, end_time) values ('12:00', '12:00')$q$, '23514', 'zero-length slot rejected');
  perform test_helpers.expect_error(
    $q$insert into public.time_slots (start_time, end_time) values ('13:00', '12:00')$q$, '23514', 'slot ending before it starts rejected');
  perform test_helpers.expect_error(
    $q$insert into public.time_slots (start_time, end_time, capacity) values ('12:00', '13:00', 0)$q$, '23514', 'capacity 0 rejected');
  perform test_helpers.expect_error(
    $q$insert into public.time_slots (start_time, end_time, capacity) values ('12:00', '13:00', 51)$q$, '23514', 'capacity above 50 rejected');
  perform test_helpers.expect_error(
    $q$insert into public.time_slots (start_time, end_time, days_of_week) values ('12:00', '13:00', '{}')$q$, '23514', 'empty weekday list rejected');
  perform test_helpers.expect_error(
    $q$insert into public.time_slots (start_time, end_time, days_of_week) values ('12:00', '13:00', '{8}')$q$, '23514', 'weekday 8 rejected');
  perform test_helpers.expect_error(
    $q$insert into public.time_slots (start_time, end_time, days_of_week) values ('12:00', '13:00', '{0}')$q$, '23514', 'weekday 0 rejected');

  perform test_helpers.expect_error(
    $q$insert into public.time_slots (start_time, end_time, days_of_week) values ('10:00', '12:00', '{1}')$q$, '23P01',
    'overlapping active slot on a shared weekday rejected');
  perform test_helpers.expect_rows_affected(
    $q$insert into public.time_slots (start_time, end_time, days_of_week) values ('11:00', '13:00', '{1,2,3}')$q$, 1,
    'back-to-back slots are allowed');
  perform test_helpers.expect_rows_affected(
    $q$insert into public.time_slots (start_time, end_time, days_of_week) values ('10:00', '12:00', '{4,5}')$q$, 1,
    'same hours on different weekdays are allowed');
  perform test_helpers.expect_rows_affected(
    $q$insert into public.time_slots (start_time, end_time, is_active, days_of_week) values ('10:00', '12:00', false, '{1}')$q$, 1,
    'an inactive overlapping slot is allowed');
  perform test_helpers.expect_error(
    $q$update public.time_slots set is_active = true where start_time = '10:00' and is_active = false$q$, '23P01',
    'reactivating an overlapping slot is rejected');
  perform test_helpers.expect_error(
    $q$update public.time_slots set end_time = '11:30' where id = 'a5000000-0000-0000-0000-000000000001'$q$, '23P01',
    'editing a slot so that it overlaps its neighbour is rejected');
  perform test_helpers.expect_error(
    $q$update public.time_slots set days_of_week = '{3,4}' where id = 'a5000000-0000-0000-0000-000000000001'$q$, '23P01',
    'adding a weekday that creates an overlap is rejected');
  perform test_helpers.expect_rows_affected(
    $q$update public.time_slots set end_time = '10:30' where id = 'a5000000-0000-0000-0000-000000000001'$q$, 1,
    'a harmless edit is allowed');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- availability_exceptions
-- -----------------------------------------------------------------------------
begin;
insert into public.time_slots (id, start_time, end_time) values
  ('a5000000-0000-0000-0000-000000000002', '09:00', '11:00');
do $$
begin
  perform test_helpers.expect_rows_affected(
    $q$insert into public.availability_exceptions (exception_date, reason) values (current_date + 5, 'Closed for Diwali')$q$, 1,
    'whole-day closure can be created');
  perform test_helpers.expect_error(
    $q$insert into public.availability_exceptions (exception_date) values (current_date + 5)$q$, '23505',
    'only one whole-day exception per date');
  perform test_helpers.expect_error(
    $q$insert into public.availability_exceptions (exception_date, is_open) values (current_date + 6, true)$q$, '23514',
    'a whole day cannot be "opened"');
  perform test_helpers.expect_rows_affected(
    $q$insert into public.availability_exceptions (exception_date, time_slot_id, is_open, capacity) values (current_date + 6, 'a5000000-0000-0000-0000-000000000002', true, 3)$q$, 1,
    'a slot can be opened with its own capacity');
  perform test_helpers.expect_error(
    $q$insert into public.availability_exceptions (exception_date, time_slot_id, is_open, capacity) values (current_date + 6, 'a5000000-0000-0000-0000-000000000002', true, 1)$q$, '23505',
    'only one exception per date and slot');
  perform test_helpers.expect_error(
    $q$insert into public.availability_exceptions (exception_date, time_slot_id, is_open, capacity) values (current_date + 7, 'a5000000-0000-0000-0000-000000000002', false, 2)$q$, '23514',
    'a closure cannot carry a capacity');
  perform test_helpers.expect_error(
    $q$insert into public.availability_exceptions (exception_date, time_slot_id, is_open, capacity) values (current_date + 7, 'a5000000-0000-0000-0000-000000000002', true, 0)$q$, '23514',
    'exception capacity must be at least 1');
  perform test_helpers.expect_error(
    $q$insert into public.availability_exceptions (exception_date, reason) values (current_date + 8, '   ')$q$, '23514',
    'blank reason rejected');
  perform test_helpers.expect_error(
    $q$insert into public.availability_exceptions (exception_date, time_slot_id) values (current_date + 8, gen_random_uuid())$q$, '23503',
    'exception must reference an existing slot');
  delete from public.time_slots where id = 'a5000000-0000-0000-0000-000000000002';
  perform test_helpers.expect_count('select 1 from public.availability_exceptions where time_slot_id is not null', 0,
    'deleting a slot removes its exceptions');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Service areas: PIN code validation and uniqueness
-- -----------------------------------------------------------------------------
begin;
do $$
begin
  perform test_helpers.expect_error(
    $q$insert into public.service_areas (pincode, area_name, city, state) values ('0123456', 'x', 'y', 'z')$q$, '23514', '7-digit PIN rejected');
  perform test_helpers.expect_error(
    $q$insert into public.service_areas (pincode, area_name, city, state) values ('012345', 'x', 'y', 'z')$q$, '23514', 'PIN starting with 0 rejected');
  perform test_helpers.expect_error(
    $q$insert into public.service_areas (pincode, area_name, city, state) values ('462001', 'Dup', 'Bhopal', 'MP')$q$, '23505', 'duplicate PIN rejected');
  -- Removing an area must not touch booking history.
  delete from public.service_areas where id = 'd0000000-0000-0000-0000-000000000001';
  perform test_helpers.expect_count(
    $q$select 1 from public.bookings where pincode = '462001' and service_area_id is null$q$, 3,
    'deleting a service area keeps bookings (PIN snapshot stays, link is cleared)');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Access: customers and drivers read but never write; anon sees nothing
-- -----------------------------------------------------------------------------
begin;
insert into public.time_slots (id, start_time, end_time, is_active) values
  ('a5000000-0000-0000-0000-000000000003', '09:00', '11:00', true),
  ('a5000000-0000-0000-0000-000000000004', '15:00', '17:00', false);
insert into public.availability_exceptions (id, exception_date, reason) values
  ('a6000000-0000-0000-0000-000000000001', current_date + 9, 'Holiday');

select test_helpers.as_user('11111111-1111-1111-1111-111111111111');
do $$
begin
  perform test_helpers.expect_count('select 1 from public.time_slots', 1, 'customer sees only active slots');
  perform test_helpers.expect_count('select 1 from public.availability_exceptions', 1, 'customer can read closures');
  perform test_helpers.expect_error(
    $q$insert into public.time_slots (start_time, end_time) values ('18:00', '19:00')$q$, '42501', 'customer cannot create slots');
  perform test_helpers.expect_rows_affected(
    $q$update public.time_slots set capacity = 50$q$, 0, 'customer cannot edit slots');
  perform test_helpers.expect_rows_affected(
    $q$delete from public.time_slots$q$, 0, 'customer cannot delete slots');
  perform test_helpers.expect_error(
    $q$insert into public.availability_exceptions (exception_date) values (current_date + 20)$q$, '42501', 'customer cannot create closures');
  perform test_helpers.expect_rows_affected(
    $q$delete from public.availability_exceptions$q$, 0, 'customer cannot remove closures');
  perform test_helpers.expect_error(
    $q$insert into public.service_areas (pincode, area_name, city, state) values ('560001', 'a', 'b', 'c')$q$, '42501', 'customer cannot add service areas');
  perform test_helpers.expect_rows_affected(
    $q$update public.service_areas set is_active = true$q$, 0, 'customer cannot edit service areas');
  perform test_helpers.expect_rows_affected(
    $q$delete from public.service_areas$q$, 0, 'customer cannot delete service areas');
  perform test_helpers.expect_count('select 1 from public.service_areas', 1, 'customer sees only active service areas');
  perform test_helpers.expect_rows_affected(
    $q$update public.services set category = 'Hacked'$q$, 0, 'customer cannot edit service categories');
end $$;
reset role;

select test_helpers.as_user('33333333-3333-3333-3333-333333333333');
do $$
begin
  perform test_helpers.expect_error(
    $q$insert into public.time_slots (start_time, end_time) values ('18:00', '19:00')$q$, '42501', 'driver cannot create slots');
  perform test_helpers.expect_rows_affected(
    $q$update public.service_areas set is_active = false$q$, 0, 'driver cannot edit service areas');
end $$;
reset role;

select test_helpers.as_user('55555555-5555-5555-5555-555555555555');
do $$
begin
  perform test_helpers.expect_count('select 1 from public.time_slots', 2, 'admin sees inactive slots too');
  perform test_helpers.expect_rows_affected(
    $q$update public.time_slots set capacity = 4 where id = 'a5000000-0000-0000-0000-000000000003'$q$, 1, 'admin can edit slots');
  perform test_helpers.expect_rows_affected(
    $q$insert into public.availability_exceptions (exception_date, reason) values (current_date + 21, 'Strike')$q$, 1, 'admin can add closures');
  perform test_helpers.expect_rows_affected(
    $q$insert into public.service_areas (pincode, area_name, city, state) values ('560001', 'MG Road', 'Bengaluru', 'Karnataka')$q$, 1, 'admin can add service areas');
end $$;
reset role;

select test_helpers.as_user('00000000-0000-0000-0000-000000000000', 'anon');
do $$
begin
  perform test_helpers.expect_error('select 1 from public.time_slots', '42501', 'anon cannot read slots');
  perform test_helpers.expect_error('select 1 from public.availability_exceptions', '42501', 'anon cannot read closures');
  perform test_helpers.expect_error('select 1 from public.service_areas', '42501', 'anon cannot read service areas');
  perform test_helpers.expect_error(
    $q$select public.guard_time_slot()$q$, '42501', 'anon cannot call the slot trigger function');
end $$;
reset role;
rollback;

-- -----------------------------------------------------------------------------
-- slot_booking_counts
-- -----------------------------------------------------------------------------
begin;
do $$
declare v bigint;
begin
  -- fixtures: three bookings on current_date+1/+2/+3, all non-cancelled, distinct slots
  select booked into v from public.slot_booking_counts(current_date, current_date + 5)
    where scheduled_date = current_date + 1 and slot_start = '10:00' and slot_end = '12:00';
  if v is distinct from 1 then raise exception 'FAIL: expected 1 booking in the 10-12 slot, got %', v; end if;
  raise notice 'PASS: slot_booking_counts counts bookings per date and slot';

  update public.bookings set status = 'cancelled', cancelled_at = now()
    where id = 'e0000000-0000-0000-0000-00000000000b';
  if exists (select 1 from public.slot_booking_counts(current_date, current_date + 5)
             where scheduled_date = current_date + 2) then
    raise exception 'FAIL: cancelled bookings must not hold a slot';
  end if;
  raise notice 'PASS: cancelled bookings do not hold a slot';

  if exists (select 1 from public.slot_booking_counts(current_date + 10, current_date + 20)) then
    raise exception 'FAIL: range filter ignored';
  end if;
  raise notice 'PASS: slot_booking_counts respects the date range';
end $$;
select test_helpers.as_user('11111111-1111-1111-1111-111111111111');
select test_helpers.expect_error('select * from public.slot_booking_counts(current_date, current_date)', '42501',
  'customers cannot call slot_booking_counts');
reset role;
select test_helpers.as_user('00000000-0000-0000-0000-000000000000', 'service_role');
select test_helpers.expect_count('select * from public.slot_booking_counts(current_date, current_date + 5)', 2,
  'service role can call slot_booking_counts');
reset role;
rollback;

select 'PHASE 3 DB CHECKS COMPLETED' as result;
