-- =============================================================================
-- TEST-ONLY. Phase 6: driver assignment and driver status updates. Reuses the
-- fixtures and helpers of files 01, 04 and 05 (customers 1111/2222, drivers
-- 3333/4444, admin 5555).
-- =============================================================================
\set ON_ERROR_STOP on
\set QUIET on

-- A booking that is paid and confirmed (goes through the real payment function).
create or replace function test_helpers.mk_paid(p_customer uuid, p_start text, p_end text, p_day int)
returns uuid language plpgsql as $$
declare v_b uuid := test_helpers.mk_booking(p_customer, p_start, p_end, p_day);
begin
  perform test_helpers.mk_attempt(v_b, 'order_' || v_b::text);
  perform test_helpers.apply('order_' || v_b::text, 'pay_' || v_b::text, 'captured', 49900);
  return v_b;
end $$;

create or replace function test_helpers.assign(p_booking uuid, p_driver uuid)
returns text language sql as $$
  select result from public.assign_driver(p_booking, p_driver, '55555555-5555-5555-5555-555555555555');
$$;

create or replace function test_helpers.unassign(p_booking uuid)
returns text language sql as $$
  select result from public.unassign_driver(p_booking, '55555555-5555-5555-5555-555555555555');
$$;

create or replace function test_helpers.drive(p_booking uuid, p_driver uuid, p_status public.booking_status)
returns text language sql as $$
  select result from public.driver_update_status(p_booking, p_driver, p_status);
$$;

create or replace function test_helpers.status_of(p_booking uuid)
returns text language sql as $$ select status::text from public.bookings where id = p_booking; $$;

create or replace function test_helpers.active_driver(p_booking uuid)
returns text language sql as $$
  select driver_id::text from public.driver_assignments where booking_id = p_booking and is_active;
$$;
grant execute on all functions in schema test_helpers to public;

-- -----------------------------------------------------------------------------
-- Assign, retry, reassign
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_b uuid := test_helpers.mk_paid('11111111-1111-1111-1111-111111111111', '01:00', '02:00', 30);
  d1 text := '33333333-3333-3333-3333-333333333333';
  d2 text := '44444444-4444-4444-4444-444444444444';
begin
  perform test_helpers.expect_eq(test_helpers.status_of(v_b), 'confirmed', 'a paid booking is confirmed');
  perform test_helpers.expect_eq(test_helpers.assign(v_b, d1::uuid), 'assigned', 'a paid booking can be assigned');
  perform test_helpers.expect_eq(test_helpers.status_of(v_b), 'assigned', 'assigning moves the booking to assigned');
  perform test_helpers.expect_eq(test_helpers.active_driver(v_b), d1, 'the driver is recorded');
  perform test_helpers.expect_eq(
    (select assigned_by::text from public.driver_assignments where booking_id = v_b and is_active),
    '55555555-5555-5555-5555-555555555555', 'the admin who assigned is recorded');

  perform test_helpers.expect_eq(test_helpers.assign(v_b, d1::uuid), 'unchanged', 'assigning the same driver again changes nothing');
  perform test_helpers.expect_eq((select count(*)::text from public.driver_assignments where booking_id = v_b), '1', 'a retry adds no assignment row');

  perform test_helpers.expect_eq(test_helpers.assign(v_b, d2::uuid), 'reassigned', 'an assigned booking can be reassigned');
  perform test_helpers.expect_eq(test_helpers.status_of(v_b), 'assigned', 'a reassignment keeps the status');
  perform test_helpers.expect_eq(test_helpers.active_driver(v_b), d2, 'the new driver is the active one');
  perform test_helpers.expect_eq((select count(*)::text from public.driver_assignments where booking_id = v_b and is_active), '1', 'only one assignment is active');
  perform test_helpers.expect_eq((select count(*)::text from public.driver_assignments where booking_id = v_b), '2', 'the history keeps both assignments');
  if (select unassigned_at from public.driver_assignments where booking_id = v_b and driver_id = d1::uuid) is null then
    raise exception 'FAIL: old assignment not closed';
  end if;
  raise notice 'PASS: the previous assignment is closed with a time';

  -- The previous driver can no longer change the booking; the new one can.
  perform test_helpers.expect_eq(test_helpers.drive(v_b, d1::uuid, 'on_the_way'), 'not_assigned', 'a driver who was reassigned away cannot update it');
  perform test_helpers.expect_eq(test_helpers.status_of(v_b), 'assigned', 'and the booking did not move');
  perform test_helpers.expect_eq(test_helpers.drive(v_b, d2::uuid, 'on_the_way'), 'updated', 'the new driver can start the trip');

  -- A booking already on the way can still be handed to someone else.
  perform test_helpers.expect_eq(test_helpers.assign(v_b, d1::uuid), 'reassigned', 'an on_the_way booking can be reassigned');
  perform test_helpers.expect_eq(test_helpers.status_of(v_b), 'on_the_way', 'and keeps its status');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Who and what can be assigned
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_paid uuid := test_helpers.mk_paid('11111111-1111-1111-1111-111111111111', '01:00', '02:00', 31);
  v_pending uuid := test_helpers.mk_booking('11111111-1111-1111-1111-111111111111', '03:00', '04:00', 31);
  v_unpaid uuid;
  v_cancel uuid := test_helpers.mk_paid('11111111-1111-1111-1111-111111111111', '05:00', '06:00', 31);
  v_done uuid := test_helpers.mk_paid('11111111-1111-1111-1111-111111111111', '07:00', '08:00', 31);
  v_work uuid := test_helpers.mk_paid('11111111-1111-1111-1111-111111111111', '09:00', '10:00', 31);
  d1 uuid := '33333333-3333-3333-3333-333333333333';
  d2 uuid := '44444444-4444-4444-4444-444444444444';
  v_off uuid := '77777777-7777-7777-7777-777777777777';
begin
  insert into auth.users (id, email, raw_user_meta_data) values (v_off, 'off@drivers.test', '{}');
  update public.profiles set role = 'driver', driver_login_id = 'driver07', is_active = false where id = v_off;

  perform test_helpers.expect_eq(test_helpers.assign(v_pending, d1), 'not_assignable', 'an unpaid (pending_payment) booking cannot be assigned');
  perform test_helpers.expect_eq(test_helpers.status_of(v_pending), 'pending_payment', 'and stays pending_payment');

  -- Confirmed without any successful payment (an old Phase 4 admin confirmation).
  insert into public.bookings (customer_id, service_id, package_id, vehicle_type, status, customer_name, customer_phone,
      address_line, city, pincode, scheduled_date, slot_start, slot_end, package_price, confirmed_at)
    values ('11111111-1111-1111-1111-111111111111', 'a0000000-0000-0000-0000-000000000001',
      'b0000000-0000-0000-0000-000000000001', 'scooter', 'confirmed', 'Alice A', '+919876543210', 'x', 'Bhopal',
      '462001', current_date + 40, '11:00', '12:00', 499, now()) returning id into v_unpaid;
  perform test_helpers.expect_eq(test_helpers.assign(v_unpaid, d1), 'not_paid', 'a confirmed booking with no verified payment cannot be assigned');

  perform test_helpers.expect_eq(test_helpers.assign('00000000-0000-0000-0000-00000000dead', d1), 'booking_not_found', 'an unknown booking is reported');
  perform test_helpers.expect_eq(test_helpers.assign(v_paid, '11111111-1111-1111-1111-111111111111'), 'driver_not_found', 'a customer is not a driver');
  perform test_helpers.expect_eq(test_helpers.assign(v_paid, '55555555-5555-5555-5555-555555555555'), 'driver_not_found', 'an admin is not a driver');
  perform test_helpers.expect_eq(test_helpers.assign(v_paid, '00000000-0000-0000-0000-00000000beef'), 'driver_not_found', 'an unknown driver is reported');
  perform test_helpers.expect_eq(test_helpers.assign(v_paid, v_off), 'driver_inactive', 'a deactivated driver cannot be given work');
  perform test_helpers.expect_eq(test_helpers.status_of(v_paid), 'confirmed', 'a refused assignment changes nothing');

  -- cancelled / completed / in progress
  update public.bookings set status = 'cancelled', cancelled_at = now() where id = v_cancel;
  perform test_helpers.expect_eq(test_helpers.assign(v_cancel, d1), 'not_assignable', 'a cancelled booking cannot be assigned');

  perform test_helpers.assign(v_done, d1);
  perform test_helpers.drive(v_done, d1, 'on_the_way');
  perform test_helpers.drive(v_done, d1, 'in_progress');
  perform test_helpers.expect_eq(test_helpers.assign(v_done, d2), 'not_assignable', 'a booking in progress cannot be handed over');
  perform test_helpers.drive(v_done, d1, 'completed');
  perform test_helpers.expect_eq(test_helpers.assign(v_done, d2), 'not_assignable', 'a completed booking cannot be reassigned');
  perform test_helpers.expect_eq(test_helpers.assign(v_done, d1), 'unchanged', 'asking again for the same driver is still a no-op');

  -- A deactivated driver keeps their old assignment but can no longer act on it.
  perform test_helpers.assign(v_work, d2);
  update public.profiles set is_active = false where id = d2;
  perform test_helpers.expect_eq(test_helpers.drive(v_work, d2, 'on_the_way'), 'driver_inactive', 'a deactivated driver cannot update bookings');
  perform test_helpers.expect_eq(test_helpers.assign(v_work, d1), 'reassigned', 'an admin can move work off a deactivated driver');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- A driver cannot be in two places at once
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  a uuid := test_helpers.mk_paid('11111111-1111-1111-1111-111111111111', '01:00', '03:00', 32);
  b uuid := test_helpers.mk_paid('22222222-2222-2222-2222-222222222222', '02:00', '04:00', 32);
  c uuid := test_helpers.mk_paid('11111111-1111-1111-1111-111111111111', '03:00', '05:00', 32);
  e uuid := test_helpers.mk_paid('22222222-2222-2222-2222-222222222222', '02:00', '04:00', 33);
  d2 uuid := '44444444-4444-4444-4444-444444444444';
begin
  perform test_helpers.expect_eq(test_helpers.assign(a, d2), 'assigned', 'the first visit is assigned');
  perform test_helpers.expect_eq(test_helpers.assign(b, d2), 'driver_busy', 'an overlapping visit on the same day is refused');
  perform test_helpers.expect_eq(test_helpers.status_of(b), 'confirmed', 'the refused booking stays confirmed');
  perform test_helpers.expect_eq(test_helpers.assign(c, d2), 'assigned', 'a visit that starts when the other ends is allowed');
  perform test_helpers.expect_eq(test_helpers.assign(e, d2), 'assigned', 'the same slot on another day is allowed');
  perform test_helpers.expect_eq(test_helpers.assign(b, '33333333-3333-3333-3333-333333333333'), 'assigned', 'another driver can take the overlapping visit');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Unassign
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_b uuid := test_helpers.mk_paid('11111111-1111-1111-1111-111111111111', '01:00', '02:00', 34);
  v_c uuid := test_helpers.mk_paid('22222222-2222-2222-2222-222222222222', '03:00', '04:00', 34);
  d1 uuid := '33333333-3333-3333-3333-333333333333';
begin
  perform test_helpers.expect_eq(test_helpers.unassign(v_b), 'unchanged', 'unassigning a booking with no driver is a no-op');
  perform test_helpers.assign(v_b, d1);
  perform test_helpers.expect_eq(test_helpers.unassign(v_b), 'unassigned', 'an assigned booking can be unassigned');
  perform test_helpers.expect_eq(test_helpers.status_of(v_b), 'confirmed', 'it goes back to confirmed');
  perform test_helpers.expect_eq((select count(*)::text from public.driver_assignments where booking_id = v_b and is_active), '0', 'no assignment stays active');
  perform test_helpers.expect_eq(test_helpers.drive(v_b, d1, 'on_the_way'), 'not_assigned', 'the old driver can no longer act on it');
  perform test_helpers.expect_eq(test_helpers.assign(v_b, d1), 'assigned', 'it can be assigned again');

  perform test_helpers.assign(v_c, d1);
  perform test_helpers.drive(v_c, d1, 'on_the_way');
  perform test_helpers.expect_eq(test_helpers.unassign(v_c), 'not_unassignable', 'a booking already on the way cannot be unassigned');
  perform test_helpers.expect_eq(test_helpers.status_of(v_c), 'on_the_way', 'and keeps its status');
  perform test_helpers.expect_eq(test_helpers.unassign('00000000-0000-0000-0000-00000000dead'), 'booking_not_found', 'an unknown booking is reported');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Driver status steps
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_b uuid := test_helpers.mk_paid('11111111-1111-1111-1111-111111111111', '01:00', '02:00', 35);
  d1 uuid := '33333333-3333-3333-3333-333333333333';
  d2 uuid := '44444444-4444-4444-4444-444444444444';
begin
  perform test_helpers.assign(v_b, d1);
  perform test_helpers.expect_eq(test_helpers.drive(v_b, d2, 'on_the_way'), 'not_assigned', 'another driver cannot update the booking');
  perform test_helpers.expect_eq(test_helpers.drive(v_b, d1, 'completed'), 'invalid_transition', 'a step cannot be skipped');
  perform test_helpers.expect_eq(test_helpers.drive(v_b, d1, 'in_progress'), 'invalid_transition', 'work cannot start before the trip');
  perform test_helpers.expect_eq(test_helpers.drive(v_b, d1, 'cancelled'), 'invalid_transition', 'a driver cannot cancel');
  perform test_helpers.expect_eq(test_helpers.drive(v_b, d1, 'confirmed'), 'invalid_transition', 'a driver cannot unassign by moving back');
  perform test_helpers.expect_eq(test_helpers.drive(v_b, d1, 'pending_payment'), 'invalid_transition', 'a driver cannot reopen payment');
  perform test_helpers.expect_eq(test_helpers.status_of(v_b), 'assigned', 'refused steps change nothing');

  perform test_helpers.expect_eq(test_helpers.drive(v_b, d1, 'on_the_way'), 'updated', 'assigned -> on_the_way');
  perform test_helpers.expect_eq(test_helpers.drive(v_b, d1, 'on_the_way'), 'unchanged', 'repeating a step is a no-op');
  perform test_helpers.expect_eq(test_helpers.drive(v_b, d1, 'in_progress'), 'updated', 'on_the_way -> in_progress');
  perform test_helpers.expect_eq(test_helpers.drive(v_b, d1, 'on_the_way'), 'invalid_transition', 'a step cannot go backwards');
  if (select completed_at from public.bookings where id = v_b) is not null then raise exception 'FAIL: completed_at set too early'; end if;
  perform test_helpers.expect_eq(test_helpers.drive(v_b, d1, 'completed'), 'updated', 'in_progress -> completed');
  if (select completed_at from public.bookings where id = v_b) is null then raise exception 'FAIL: completed_at missing'; end if;
  raise notice 'PASS: completing the booking sets completed_at';
  perform test_helpers.expect_eq(test_helpers.drive(v_b, d1, 'completed'), 'unchanged', 'repeating the last step is a no-op');
  perform test_helpers.expect_eq(test_helpers.drive(v_b, d1, 'in_progress'), 'invalid_transition', 'a completed booking cannot be reopened');
  perform test_helpers.expect_eq(test_helpers.active_driver(v_b), d1::text, 'the driver keeps the completed job in their history');
  perform test_helpers.expect_eq(test_helpers.drive('00000000-0000-0000-0000-00000000dead', d1, 'on_the_way'), 'booking_not_found', 'an unknown booking is reported');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Consistency with cancellation and payment
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_b uuid := test_helpers.mk_paid('11111111-1111-1111-1111-111111111111', '01:00', '02:00', 36);
  d1 uuid := '33333333-3333-3333-3333-333333333333';
begin
  perform test_helpers.assign(v_b, d1);
  update public.bookings set status = 'cancelled', cancelled_at = now() where id = v_b;
  perform test_helpers.expect_eq(test_helpers.drive(v_b, d1, 'on_the_way'), 'booking_cancelled', 'a cancelled booking cannot be driven');
  perform test_helpers.expect_eq(test_helpers.status_of(v_b), 'cancelled', 'and stays cancelled');
  perform test_helpers.expect_eq(test_helpers.active_driver(v_b), d1::text, 'the driver can still see that it was cancelled');
  if not (select needs_review from public.payments where booking_id = v_b and status = 'successful') then
    raise exception 'FAIL: paid booking cancelled while assigned must be flagged for a refund decision';
  end if;
  raise notice 'PASS: cancelling an assigned paid booking flags the payment for review';
  perform test_helpers.expect_eq(test_helpers.assign(v_b, '44444444-4444-4444-4444-444444444444'), 'not_assignable', 'a cancelled booking cannot be handed to someone else');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- A driver's lists and the workload counts
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  a uuid := test_helpers.mk_paid('11111111-1111-1111-1111-111111111111', '01:00', '02:00', 41);
  b uuid := test_helpers.mk_paid('22222222-2222-2222-2222-222222222222', '03:00', '04:00', 40);
  c uuid := test_helpers.mk_paid('11111111-1111-1111-1111-111111111111', '05:00', '06:00', 42);
  d uuid := test_helpers.mk_paid('22222222-2222-2222-2222-222222222222', '07:00', '08:00', 43);
  e uuid := test_helpers.mk_paid('11111111-1111-1111-1111-111111111111', '09:00', '10:00', 44);
  d2 uuid := '44444444-4444-4444-4444-444444444444';
  v_ids uuid[];
  v_total bigint;
begin
  perform test_helpers.assign(a, d2);
  perform test_helpers.assign(b, d2);
  perform test_helpers.assign(c, d2);
  perform test_helpers.assign(d, d2);
  perform test_helpers.assign(e, '33333333-3333-3333-3333-333333333333');
  perform test_helpers.drive(c, d2, 'on_the_way');
  perform test_helpers.drive(c, d2, 'in_progress');
  perform test_helpers.drive(c, d2, 'completed');
  update public.bookings set status = 'cancelled', cancelled_at = now() where id = d;

  select array_agg(booking_id order by ord), max(total) into v_ids, v_total
  from (select booking_id, total, row_number() over () as ord
        from public.driver_booking_ids(d2, 'open', 10, 0)) x;
  if v_ids is distinct from array[b, a] then raise exception 'FAIL: open list should be soonest first, got %', v_ids; end if;
  perform test_helpers.expect_eq(v_total::text, '2', 'the open list counts only open bookings');

  select array_agg(booking_id order by ord), max(total) into v_ids, v_total
  from (select booking_id, total, row_number() over () as ord
        from public.driver_booking_ids(d2, 'history', 10, 0)) x;
  if v_ids is distinct from array[d, c] then raise exception 'FAIL: history should be latest first, got %', v_ids; end if;
  perform test_helpers.expect_eq(v_total::text, '2', 'history holds completed and cancelled bookings');

  perform test_helpers.expect_eq((select count(*)::text from public.driver_booking_ids(d2, 'open', 1, 1)), '1', 'paging returns the requested page');
  perform test_helpers.expect_eq((select booking_id::text from public.driver_booking_ids(d2, 'open', 1, 1)), a::text, 'the second page is the second booking');
  perform test_helpers.expect_eq((select count(*)::text from public.driver_booking_ids('33333333-3333-3333-3333-333333333333', 'open', 10, 0)), '2', 'another driver sees only their own (the fixture booking and the new one)');
  perform test_helpers.expect_error($q$select * from public.driver_booking_ids('44444444-4444-4444-4444-444444444444', 'all', 10, 0)$q$, '22023', 'an unknown scope is refused');

  perform test_helpers.expect_eq((select open_bookings::text from public.driver_workload() where driver_id = d2), '2', 'the workload counts open bookings only');
  perform test_helpers.expect_eq((select open_bookings::text from public.driver_workload() where driver_id = '33333333-3333-3333-3333-333333333333'), '2', 'the fixture booking and the new one count for driver 1');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Grants and row-level security
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_b uuid := test_helpers.mk_paid('11111111-1111-1111-1111-111111111111', '01:00', '02:00', 37);
begin
  perform test_helpers.assign(v_b, '44444444-4444-4444-4444-444444444444');
  create temp table t_booking (id uuid);
  insert into t_booking values (v_b);
  grant select on t_booking to public;
end $$;

select test_helpers.as_user('44444444-4444-4444-4444-444444444444');
select test_helpers.expect_count('select 1 from public.bookings where id = (select id from t_booking)', 1, 'an assigned driver can read their booking');
select test_helpers.expect_error(
  $q$update public.bookings set status = 'on_the_way' where id = (select id from t_booking)$q$,
  '42501', 'a driver cannot update a booking directly');
select test_helpers.expect_error(
  $q$select * from public.driver_update_status((select id from t_booking), '44444444-4444-4444-4444-444444444444', 'on_the_way')$q$,
  '42501', 'a driver cannot call the status function through the API');
select test_helpers.expect_error(
  $q$select * from public.assign_driver((select id from t_booking), '44444444-4444-4444-4444-444444444444', '44444444-4444-4444-4444-444444444444')$q$,
  '42501', 'a driver cannot assign themselves');
select test_helpers.expect_error(
  $q$insert into public.driver_assignments (booking_id, driver_id, assigned_by)
     values ((select id from t_booking), '44444444-4444-4444-4444-444444444444', '44444444-4444-4444-4444-444444444444')$q$,
  '42501', 'a driver cannot write assignments directly');
reset role;

select test_helpers.as_user('33333333-3333-3333-3333-333333333333');
select test_helpers.expect_count('select 1 from public.bookings where id = (select id from t_booking)', 0, 'another driver cannot read it');
reset role;

select test_helpers.as_user('55555555-5555-5555-5555-555555555555');
select test_helpers.expect_error(
  $q$select * from public.assign_driver((select id from t_booking), '33333333-3333-3333-3333-333333333333', '55555555-5555-5555-5555-555555555555')$q$,
  '42501', 'even an admin session cannot call it through the API (the backend uses the service role)');
reset role;

select test_helpers.as_user('00000000-0000-0000-0000-000000000000', 'anon');
select test_helpers.expect_error(
  $q$select * from public.unassign_driver('00000000-0000-0000-0000-00000000dead', '55555555-5555-5555-5555-555555555555')$q$,
  '42501', 'anon cannot call unassign');
reset role;

select test_helpers.as_user('00000000-0000-0000-0000-000000000000', 'service_role');
select test_helpers.expect_eq(
  (select result from public.unassign_driver((select id from t_booking), '55555555-5555-5555-5555-555555555555')),
  'unassigned', 'service_role can call the assignment functions');
reset role;

-- after the unassignment the driver can no longer read the booking
select test_helpers.as_user('44444444-4444-4444-4444-444444444444');
select test_helpers.expect_count('select 1 from public.bookings where id = (select id from t_booking)', 0, 'an unassigned driver loses access to the booking');
reset role;
rollback;

select 'PHASE 6 DB CHECKS COMPLETED' as result;
