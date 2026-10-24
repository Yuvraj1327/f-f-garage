-- =============================================================================
-- TEST-ONLY. Phase 4: booking workflow rules in the database. Reuses the
-- fixtures and test_helpers of 01_rls_and_constraints_test.sql.
--   customers: 1111.. (Alice), 2222.. (Bob)   admin: 5555..   service/package: a..1 / b..1
-- =============================================================================
\set ON_ERROR_STOP on
\set QUIET on

-- A helper to build the create_booking payload for these tests.
create or replace function test_helpers.booking_json(
  p_customer uuid, p_start text, p_end text, p_day int default 3, p_request uuid default null
) returns jsonb language sql as $$
  select jsonb_build_object(
    'customer_id', p_customer,
    'service_id', 'a0000000-0000-0000-0000-000000000001',
    'package_id', 'b0000000-0000-0000-0000-000000000001',
    'vehicle_type', 'scooter',
    'customer_name', 'Test Customer',
    'customer_phone', '+919800000001',
    'address_line', '12 MG Road',
    'city', 'Bhopal', 'state', 'Madhya Pradesh', 'pincode', '462001',
    'service_area_id', 'd0000000-0000-0000-0000-000000000001',
    'scheduled_date', current_date + p_day,
    'slot_start', p_start, 'slot_end', p_end,
    'service_name', 'General Service', 'package_name', 'Basic',
    'package_inclusions', jsonb_build_array('Wash', 'Oil top-up'),
    'estimated_duration_minutes', 90,
    'package_price', 499.00,
    'client_request_id', p_request);
$$;

-- -----------------------------------------------------------------------------
-- create_booking: snapshot, pricing, charges, idempotency
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  b public.bookings;
  v_first uuid;
  v_n bigint;
  v_charges jsonb := jsonb_build_array(
    jsonb_build_object('extra_charge_id', 'c0000000-0000-0000-0000-000000000001', 'charge_type', 'engine_oil',
                       'name', 'Engine oil 10W-30', 'amount', 350.00, 'included_in_total', true),
    jsonb_build_object('extra_charge_id', 'c0000000-0000-0000-0000-000000000002', 'charge_type', 'spare_part',
                       'name', 'Air filter', 'amount', null, 'included_in_total', false));
begin
  select * into b from public.create_booking(
    test_helpers.booking_json('11111111-1111-1111-1111-111111111111', '06:00', '08:00', 3,
                              'aaaaaaaa-0000-0000-0000-000000000001'), v_charges);
  if b.status <> 'pending_payment' then raise exception 'FAIL: new booking should be pending_payment, got %', b.status; end if;
  raise notice 'PASS: create_booking starts in pending_payment';
  if b.booking_number is null then raise exception 'FAIL: booking_number missing'; end if;
  raise notice 'PASS: booking gets a booking number';
  if b.total_amount <> 849.00 or b.extra_charges_total <> 350.00 then
    raise exception 'FAIL: total should be 499 + 350 selected extras, got % / %', b.total_amount, b.extra_charges_total;
  end if;
  raise notice 'PASS: only chosen fixed extra charges are added to the total';
  if b.service_name <> 'General Service' or b.package_name <> 'Basic'
     or b.package_inclusions <> array['Wash', 'Oil top-up'] or b.estimated_duration_minutes <> 90 then
    raise exception 'FAIL: snapshot columns not stored';
  end if;
  raise notice 'PASS: service, package, inclusions and duration are snapshotted';
  select count(*) into v_n from public.booking_extra_charges where booking_id = b.id;
  if v_n <> 2 then raise exception 'FAIL: expected 2 charge snapshot rows, got %', v_n; end if;
  if (select count(*) from public.booking_extra_charges where booking_id = b.id and included_in_total) <> 1 then
    raise exception 'FAIL: exactly one charge should be included';
  end if;
  raise notice 'PASS: extra charges are snapshotted (included and informational)';

  v_first := b.id;
  select * into b from public.create_booking(
    test_helpers.booking_json('11111111-1111-1111-1111-111111111111', '06:00', '08:00', 3,
                              'aaaaaaaa-0000-0000-0000-000000000001'), v_charges);
  if b.id <> v_first then raise exception 'FAIL: a repeated request key must return the first booking'; end if;
  if (select count(*) from public.bookings where client_request_id = 'aaaaaaaa-0000-0000-0000-000000000001') <> 1 then
    raise exception 'FAIL: replay created a second booking';
  end if;
  if (select count(*) from public.booking_extra_charges where booking_id = v_first) <> 2 then
    raise exception 'FAIL: replay duplicated the charges';
  end if;
  raise notice 'PASS: a repeated client_request_id is idempotent';

  perform test_helpers.expect_error(
    $q$select * from public.create_booking(test_helpers.booking_json(
         '11111111-1111-1111-1111-111111111111', '06:00', '08:00', 3, 'aaaaaaaa-0000-0000-0000-000000000002'))$q$,
    '23505', 'the same customer cannot hold the same slot twice');
  perform test_helpers.expect_rows_affected(
    $q$select * from public.create_booking(test_helpers.booking_json(
         '11111111-1111-1111-1111-111111111111', '06:00', '08:00', 4))$q$,
    1, 'the same slot on another date is allowed');

  perform test_helpers.expect_error(
    $q$select * from public.create_booking(test_helpers.booking_json(
         '11111111-1111-1111-1111-111111111111', '12:00', '12:00', 5))$q$,
    '23514', 'create_booking enforces the slot order check');

  -- booking numbers are unique and increase
  select * into b from public.create_booking(
    test_helpers.booking_json('22222222-2222-2222-2222-222222222222', '06:00', '08:00', 6));
  if b.booking_number <= (select booking_number from public.bookings where id = v_first) then
    raise exception 'FAIL: booking numbers should increase';
  end if;
  raise notice 'PASS: booking numbers are unique and increasing';
  perform test_helpers.expect_error(
    format($q$update public.bookings set booking_number = %s where id = %L$q$,
           (select booking_number from public.bookings where id = v_first), b.id),
    '428C9', 'a booking number cannot be changed (identity column)');

  -- a writer that omits the snapshot still gets one
  insert into public.bookings (customer_id, service_id, package_id, vehicle_type, customer_name, customer_phone,
      address_line, city, pincode, scheduled_date, slot_start, slot_end, package_price)
    values ('22222222-2222-2222-2222-222222222222', 'a0000000-0000-0000-0000-000000000001',
      'b0000000-0000-0000-0000-000000000001', 'scooter', 'Bob', '+919800000002', 'x', 'Bhopal', '462001',
      current_date + 20, '10:00', '11:00', 100) returning * into b;
  if b.service_name is distinct from (select name from public.services where id = 'a0000000-0000-0000-0000-000000000001')
     or b.package_name <> 'Basic' then
    raise exception 'FAIL: snapshot should be filled from the catalogue';
  end if;
  raise notice 'PASS: a direct insert gets its snapshot from the catalogue';
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Capacity per date and slot
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  a public.bookings;
  b public.bookings;
  v_slot uuid;
begin
  insert into public.time_slots (id, start_time, end_time, capacity, days_of_week)
    values ('a5000000-0000-0000-0000-0000000000f1', '06:00', '08:00', 1, '{1,2,3,4,5,6,7}')
    returning id into v_slot;
  insert into public.time_slots (id, start_time, end_time, capacity, days_of_week)
    values ('a5000000-0000-0000-0000-0000000000f2', '08:00', '09:00', 1, '{1,2,3,4,5,6,7}');

  select * into a from public.create_booking(
    test_helpers.booking_json('11111111-1111-1111-1111-111111111111', '06:00', '08:00', 3));
  perform test_helpers.expect_error(
    $q$select * from public.create_booking(test_helpers.booking_json(
         '22222222-2222-2222-2222-222222222222', '06:00', '08:00', 3))$q$,
    '23P01', 'a full slot refuses the next booking');
  perform test_helpers.expect_rows_affected(
    $q$select * from public.create_booking(test_helpers.booking_json(
         '22222222-2222-2222-2222-222222222222', '06:00', '08:00', 4))$q$,
    1, 'the same slot on another date still has room');

  update public.bookings set status = 'cancelled', cancelled_at = now() where id = a.id;
  perform test_helpers.expect_rows_affected(
    $q$select * from public.create_booking(test_helpers.booking_json(
         '22222222-2222-2222-2222-222222222222', '06:00', '08:00', 3))$q$,
    1, 'cancelling a booking frees its place');

  -- an "open" exception with a capacity overrides the slot capacity
  insert into public.availability_exceptions (exception_date, time_slot_id, is_open, capacity)
    values (current_date + 7, v_slot, true, 2);
  perform test_helpers.expect_rows_affected(
    $q$select * from public.create_booking(test_helpers.booking_json(
         '11111111-1111-1111-1111-111111111111', '06:00', '08:00', 7))$q$, 1, 'exception capacity: first place');
  perform test_helpers.expect_rows_affected(
    $q$select * from public.create_booking(test_helpers.booking_json(
         '22222222-2222-2222-2222-222222222222', '06:00', '08:00', 7))$q$, 1, 'exception capacity: second place');
  perform test_helpers.expect_error(
    $q$select * from public.create_booking(test_helpers.booking_json(
         '66666666-6666-6666-6666-666666666666', '06:00', '08:00', 7))$q$,
    '23P01', 'exception capacity is also a hard limit');

  -- rescheduling is capacity-checked too
  select * into b from public.create_booking(
    test_helpers.booking_json('11111111-1111-1111-1111-111111111111', '08:00', '09:00', 3));
  perform test_helpers.expect_error(
    format($q$update public.bookings set slot_start = '06:00', slot_end = '08:00' where id = %L$q$, b.id),
    '23P01', 'moving a booking into a full slot is refused');
  perform test_helpers.expect_rows_affected(
    format($q$update public.bookings set scheduled_date = current_date + 9 where id = %L$q$, b.id),
    1, 'moving a booking to a free date is allowed');
  perform test_helpers.expect_rows_affected(
    format($q$update public.bookings set landmark = 'Near the temple' where id = %L$q$, b.id),
    1, 'editing a non-schedule field skips the capacity check');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Status transitions and locked columns
-- -----------------------------------------------------------------------------
begin;
do $$
declare b public.bookings;
begin
  select * into b from public.create_booking(
    test_helpers.booking_json('11111111-1111-1111-1111-111111111111', '15:00', '16:00', 3));

  perform test_helpers.expect_error(
    format($q$update public.bookings set status = 'completed', completed_at = now(), confirmed_at = now() where id = %L$q$, b.id),
    '23514', 'pending_payment cannot jump to completed');
  perform test_helpers.expect_error(
    format($q$update public.bookings set status = 'assigned', confirmed_at = now() where id = %L$q$, b.id),
    '23514', 'pending_payment cannot jump to assigned');
  perform test_helpers.expect_rows_affected(
    format($q$update public.bookings set status = 'confirmed', confirmed_at = now() where id = %L$q$, b.id),
    1, 'pending_payment can be confirmed');
  perform test_helpers.expect_error(
    format($q$update public.bookings set status = 'pending_payment', confirmed_at = null where id = %L$q$, b.id),
    '23514', 'a confirmed booking cannot go back to pending_payment');

  perform test_helpers.expect_error(
    format($q$update public.bookings set package_price = 1 where id = %L$q$, b.id), '23514', 'the package price is locked');
  perform test_helpers.expect_error(
    format($q$update public.bookings set extra_charges_total = 5 where id = %L$q$, b.id), '23514', 'the extra-charge total is locked');
  perform test_helpers.expect_error(
    format($q$update public.bookings set package_name = 'Free' where id = %L$q$, b.id), '23514', 'the package snapshot is locked');
  perform test_helpers.expect_error(
    format($q$update public.bookings set customer_id = '22222222-2222-2222-2222-222222222222' where id = %L$q$, b.id),
    '23514', 'the booking owner cannot be changed');
  perform test_helpers.expect_rows_affected(
    format($q$update public.bookings set address_line = '14 MG Road' where id = %L$q$, b.id), 1, 'the address can be edited');

  perform test_helpers.expect_rows_affected(
    format($q$update public.bookings set status = 'cancelled', cancelled_at = now(), cancellation_reason = 'Changed my mind' where id = %L$q$, b.id),
    1, 'a confirmed booking can be cancelled');
  perform test_helpers.expect_error(
    format($q$update public.bookings set status = 'confirmed', cancelled_at = null where id = %L$q$, b.id),
    '23514', 'a cancelled booking cannot be revived');
  perform test_helpers.expect_error(
    format($q$update public.bookings set address_line = 'Elsewhere' where id = %L$q$, b.id),
    '23514', 'a cancelled booking is read-only');

  -- the full happy path is allowed step by step
  select * into b from public.create_booking(
    test_helpers.booking_json('11111111-1111-1111-1111-111111111111', '16:00', '17:00', 3));
  update public.bookings set status = 'confirmed', confirmed_at = now() where id = b.id;
  update public.bookings set status = 'assigned' where id = b.id;
  update public.bookings set status = 'confirmed' where id = b.id;
  update public.bookings set status = 'assigned' where id = b.id;
  update public.bookings set status = 'on_the_way' where id = b.id;
  update public.bookings set status = 'in_progress' where id = b.id;
  update public.bookings set status = 'completed', completed_at = now() where id = b.id;
  raise notice 'PASS: the whole status path is allowed in order';
  perform test_helpers.expect_error(
    format($q$update public.bookings set status = 'cancelled', cancelled_at = now() where id = %L$q$, b.id),
    '23514', 'a completed booking cannot be cancelled');

  perform test_helpers.expect_count(
    $q$select 1 where public.booking_status_transition_allowed('assigned', 'on_the_way')$q$, 1, 'transition helper: allowed');
  perform test_helpers.expect_count(
    $q$select 1 where public.booking_status_transition_allowed('confirmed', 'completed')$q$, 0, 'transition helper: refused');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Charge snapshots: immutable, cascade with the booking
-- -----------------------------------------------------------------------------
begin;
do $$
declare b public.bookings;
begin
  select * into b from public.create_booking(
    test_helpers.booking_json('11111111-1111-1111-1111-111111111111', '15:00', '16:00', 3),
    jsonb_build_array(jsonb_build_object('extra_charge_id', 'c0000000-0000-0000-0000-000000000001',
      'charge_type', 'engine_oil', 'name', 'Engine oil', 'amount', 350, 'included_in_total', true)));
  perform test_helpers.expect_error(
    format($q$update public.booking_extra_charges set amount = 1 where booking_id = %L$q$, b.id),
    '23514', 'a charge snapshot cannot be edited');
  perform test_helpers.expect_error(
    format($q$insert into public.booking_extra_charges (booking_id, charge_type, name, amount, included_in_total)
              values (%L, 'other', 'Free thing', null, true)$q$, b.id),
    '23514', 'an included charge needs an amount');
  delete from public.extra_charges where id = 'c0000000-0000-0000-0000-000000000001';
  if (select count(*) from public.booking_extra_charges where booking_id = b.id) <> 1 then
    raise exception 'FAIL: deleting a catalogue charge must not remove the snapshot';
  end if;
  raise notice 'PASS: deleting a catalogue charge keeps the booking snapshot';
  delete from public.bookings where id = b.id;
  if exists (select 1 from public.booking_extra_charges where booking_id = b.id) then
    raise exception 'FAIL: charges should cascade with the booking';
  end if;
  raise notice 'PASS: charge snapshots go with their booking';
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Who can see and write what
-- -----------------------------------------------------------------------------
begin;
do $$
begin
  perform public.create_booking(
    test_helpers.booking_json('11111111-1111-1111-1111-111111111111', '15:00', '16:00', 3),
    jsonb_build_array(jsonb_build_object('charge_type', 'other', 'name', 'Note', 'amount', null, 'included_in_total', false)));
  perform public.create_booking(
    test_helpers.booking_json('22222222-2222-2222-2222-222222222222', '15:00', '16:00', 3),
    jsonb_build_array(jsonb_build_object('charge_type', 'other', 'name', 'Note', 'amount', null, 'included_in_total', false)));
end $$;

select test_helpers.as_user('11111111-1111-1111-1111-111111111111');
do $$
begin
  perform test_helpers.expect_count(
    $q$select 1 from public.booking_extra_charges where booking_id in (select id from public.bookings where customer_id = '11111111-1111-1111-1111-111111111111')$q$,
    1, 'a customer sees the charges of their own booking');
  perform test_helpers.expect_count('select 1 from public.booking_extra_charges', 1, 'a customer sees no one else''s charges');
  perform test_helpers.expect_error(
    $q$insert into public.booking_extra_charges (booking_id, charge_type, name) select id, 'other', 'x' from public.bookings limit 1$q$,
    '42501', 'a customer cannot write charges');
  perform test_helpers.expect_error(
    $q$select * from public.create_booking('{}'::jsonb)$q$, '42501', 'a customer cannot call create_booking (price tampering)');
  perform test_helpers.expect_error(
    $q$update public.bookings set package_price = 0$q$, '42501', 'a customer cannot update booking prices');
end $$;
reset role;

select test_helpers.as_user('55555555-5555-5555-5555-555555555555');
select test_helpers.expect_error($q$select * from public.create_booking('{}'::jsonb)$q$, '42501', 'an admin cannot call create_booking over the API');
select test_helpers.expect_count('select 1 from public.booking_extra_charges', 2, 'an admin sees all charges');
reset role;

select test_helpers.as_user('00000000-0000-0000-0000-000000000000', 'anon');
select test_helpers.expect_error('select 1 from public.booking_extra_charges', '42501', 'anon cannot read charges');
select test_helpers.expect_error($q$select * from public.create_booking('{}'::jsonb)$q$, '42501', 'anon cannot call create_booking');
reset role;

select test_helpers.as_user('33333333-3333-3333-3333-333333333333');
select test_helpers.expect_count('select 1 from public.booking_extra_charges', 0, 'an unassigned driver sees no charges');
reset role;

select test_helpers.as_user('00000000-0000-0000-0000-000000000000', 'service_role');
select test_helpers.expect_rows_affected(
  $q$select * from public.create_booking(test_helpers.booking_json('11111111-1111-1111-1111-111111111111', '17:00', '18:00', 3))$q$,
  1, 'service_role can call create_booking');
reset role;
rollback;

select 'PHASE 4 DB CHECKS COMPLETED' as result;
