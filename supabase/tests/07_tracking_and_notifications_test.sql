-- =============================================================================
-- TEST-ONLY. Phase 7: booking status history and customer notifications. Reuses
-- the fixtures and helpers of files 01, 04, 05 and 06 (customers 1111/2222,
-- drivers 3333/4444, admin 5555).
-- =============================================================================
\set ON_ERROR_STOP on
\set QUIET on

create or replace function test_helpers.kinds(p_booking uuid)
returns text language sql as $$
  select coalesce(string_agg(kind, ',' order by seq), '')
  from public.notifications where booking_id = p_booking;
$$;

create or replace function test_helpers.history(p_booking uuid)
returns text language sql as $$
  select coalesce(string_agg(status::text, ',' order by id), '')
  from public.booking_status_events where booking_id = p_booking;
$$;
grant execute on all functions in schema test_helpers to public;

-- -----------------------------------------------------------------------------
-- A new booking starts its history and says nothing yet
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_b uuid := test_helpers.mk_booking('11111111-1111-1111-1111-111111111111', '01:00', '02:00', 40);
begin
  perform test_helpers.expect_eq(test_helpers.history(v_b), 'pending_payment', 'a new booking has its first history entry');
  perform test_helpers.expect_eq(test_helpers.kinds(v_b), '', 'a new booking sends no notification');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Payment result
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_b uuid := test_helpers.mk_booking('11111111-1111-1111-1111-111111111111', '01:00', '02:00', 41);
begin
  perform test_helpers.mk_attempt(v_b, 'order_n1');
  perform test_helpers.apply('order_n1', 'pay_n1', 'failed', null, 'evt_n1');
  perform test_helpers.expect_eq(test_helpers.kinds(v_b), 'payment_failed', 'a failed payment notifies the customer');
  perform test_helpers.expect_eq(test_helpers.history(v_b), 'pending_payment', 'a failed payment does not change the history');

  perform test_helpers.apply('order_n1', 'pay_n1', 'failed', null, 'evt_n1');
  perform test_helpers.expect_eq(test_helpers.kinds(v_b), 'payment_failed', 'a replayed failure does not notify twice');

  perform test_helpers.mk_attempt(v_b, 'order_n2');
  perform test_helpers.apply('order_n2', 'pay_n2', 'captured', 49900, 'evt_n2');
  perform test_helpers.expect_eq(test_helpers.kinds(v_b), 'payment_failed,booking_confirmed', 'a verified payment confirms and notifies');
  perform test_helpers.expect_eq(test_helpers.history(v_b), 'pending_payment,confirmed', 'the confirmation is in the history');

  perform test_helpers.apply('order_n2', 'pay_n2', 'captured', 49900, 'evt_n2');
  perform test_helpers.apply('order_n2', 'pay_n2', 'captured', 49900, 'evt_n3');
  perform test_helpers.expect_eq(test_helpers.kinds(v_b), 'payment_failed,booking_confirmed', 'a replayed success notifies once');
  perform test_helpers.expect_eq(test_helpers.history(v_b), 'pending_payment,confirmed', 'a replayed success adds no history');

  perform test_helpers.mk_attempt(v_b, 'order_n3');
  perform test_helpers.apply('order_n3', 'pay_n3', 'failed', null, 'evt_n4');
  perform test_helpers.expect_eq(test_helpers.kinds(v_b), 'payment_failed,booking_confirmed', 'a failed retry on a paid booking is not announced');

  perform test_helpers.expect_eq((select count(*)::text from public.notifications where booking_id = v_b and user_id <> '11111111-1111-1111-1111-111111111111'), '0', 'only the booking owner is notified');
  perform test_helpers.expect_eq(
    ((select body from public.notifications where booking_id = v_b and kind = 'booking_confirmed') like 'Payment received for FF-%General Service%')::text,
    'true', 'the message names the booking and service');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Assignment, reassignment, removal, driver steps, completion
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_b uuid := test_helpers.mk_paid('11111111-1111-1111-1111-111111111111', '01:00', '02:00', 42);
  d1 uuid := '33333333-3333-3333-3333-333333333333';
  d2 uuid := '44444444-4444-4444-4444-444444444444';
begin
  perform test_helpers.expect_eq(test_helpers.kinds(v_b), 'booking_confirmed', 'starts with the confirmation');

  perform test_helpers.assign(v_b, d1);
  perform test_helpers.expect_eq(test_helpers.kinds(v_b), 'booking_confirmed,driver_assigned', 'assigning notifies');
  perform test_helpers.expect_eq(test_helpers.history(v_b), 'pending_payment,confirmed,assigned', 'assigning is in the history');

  perform test_helpers.assign(v_b, d1);
  perform test_helpers.expect_eq(test_helpers.kinds(v_b), 'booking_confirmed,driver_assigned', 'assigning the same driver again is silent');

  perform test_helpers.assign(v_b, d2);
  perform test_helpers.expect_eq(test_helpers.kinds(v_b), 'booking_confirmed,driver_assigned,driver_changed', 'reassigning says the driver changed');
  perform test_helpers.expect_eq(test_helpers.history(v_b), 'pending_payment,confirmed,assigned', 'a reassignment keeps the same status, so no history entry');

  perform test_helpers.unassign(v_b);
  perform test_helpers.expect_eq(test_helpers.kinds(v_b), 'booking_confirmed,driver_assigned,driver_changed,driver_removed', 'removing the driver notifies');
  perform test_helpers.expect_eq(test_helpers.history(v_b), 'pending_payment,confirmed,assigned,confirmed', 'removal returns the history to confirmed');

  perform test_helpers.assign(v_b, d1);
  perform test_helpers.expect_eq(
    (select kind from public.notifications where booking_id = v_b order by seq desc limit 1),
    'driver_changed', 'a driver assigned after a removal is announced');

  perform test_helpers.drive(v_b, d1, 'on_the_way');
  perform test_helpers.drive(v_b, d1, 'in_progress');
  perform test_helpers.drive(v_b, d1, 'completed');
  perform test_helpers.expect_eq(
    test_helpers.history(v_b),
    'pending_payment,confirmed,assigned,confirmed,assigned,on_the_way,in_progress,completed', 'every step is in the history, in order');
  perform test_helpers.expect_eq(
    (select string_agg(kind, ',' order by seq desc) from (
       select kind, seq from public.notifications where booking_id = v_b order by seq desc limit 3) x),
    'service_completed,service_started,driver_on_the_way'::text, 'each driver step notifies');

  perform test_helpers.drive(v_b, d1, 'completed');
  perform test_helpers.expect_eq((select count(*)::text from public.notifications where booking_id = v_b and kind = 'service_completed'), '1', 'repeating a step does not notify again');
  perform test_helpers.expect_eq((select count(*)::text from public.booking_status_events where booking_id = v_b and status = 'completed'), '1', 'repeating a step adds no history');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Cancellation
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_a uuid := test_helpers.mk_booking('11111111-1111-1111-1111-111111111111', '01:00', '02:00', 43);
  v_p uuid := test_helpers.mk_paid('11111111-1111-1111-1111-111111111111', '03:00', '04:00', 43);
begin
  update public.bookings set status = 'cancelled', cancelled_at = now() where id = v_a;
  perform test_helpers.expect_eq(test_helpers.kinds(v_a), 'booking_cancelled', 'cancelling an unpaid booking notifies');
  perform test_helpers.expect_eq(test_helpers.history(v_a), 'pending_payment,cancelled', 'the cancellation is in the history');

  perform test_helpers.assign(v_p, '33333333-3333-3333-3333-333333333333');
  update public.bookings set status = 'cancelled', cancelled_at = now() where id = v_p;
  perform test_helpers.expect_eq(test_helpers.kinds(v_p), 'booking_confirmed,driver_assigned,booking_cancelled', 'cancelling an assigned booking notifies once');
  perform test_helpers.expect_eq(test_helpers.history(v_p), 'pending_payment,confirmed,assigned,cancelled', 'history ends with the cancellation');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Who can read what, who can write what
-- -----------------------------------------------------------------------------
begin;
create temp table t_b as
  select test_helpers.mk_paid('11111111-1111-1111-1111-111111111111', '01:00', '02:00', 44) as id;
grant select on t_b to public;
select test_helpers.assign((select id from t_b), '33333333-3333-3333-3333-333333333333');

select test_helpers.as_user('11111111-1111-1111-1111-111111111111');
select test_helpers.expect_count('select 1 from public.notifications where booking_id = (select id from t_b)', 2, 'a customer reads their own notifications');
select test_helpers.expect_count('select 1 from public.booking_status_events where booking_id = (select id from t_b)', 3, 'a customer reads their own booking history');
select test_helpers.expect_error($q$update public.notifications set read_at = now()$q$, '42501', 'a customer cannot update notifications directly');
select test_helpers.expect_error($q$delete from public.notifications$q$, '42501', 'a customer cannot delete notifications');
select test_helpers.expect_error(
  $q$insert into public.notifications (user_id, kind, title, body) values ('11111111-1111-1111-1111-111111111111', 'booking_confirmed', 'x', 'y')$q$,
  '42501', 'a customer cannot create notifications');
select test_helpers.expect_error($q$insert into public.booking_status_events (booking_id, status) values ((select id from t_b), 'completed')$q$, '42501', 'a customer cannot write history');
select test_helpers.expect_error($q$select public.mark_notifications_read('11111111-1111-1111-1111-111111111111')$q$, '42501', 'a customer cannot call the mark-read function through the API');
reset role;

select test_helpers.as_user('22222222-2222-2222-2222-222222222222');
select test_helpers.expect_count('select 1 from public.notifications where booking_id = (select id from t_b)', 0, 'another customer sees none of them');
select test_helpers.expect_count('select 1 from public.booking_status_events where booking_id = (select id from t_b)', 0, 'another customer sees none of the history');
reset role;

select test_helpers.as_user('33333333-3333-3333-3333-333333333333');
select test_helpers.expect_count('select 1 from public.notifications', 0, 'a driver reads no notifications');
select test_helpers.expect_count('select 1 from public.booking_status_events', 0, 'a driver reads no history through the API');
reset role;

select test_helpers.as_user('55555555-5555-5555-5555-555555555555');
select test_helpers.expect_count('select 1 from public.notifications', 0, 'an admin does not read customers'' notifications');
select test_helpers.expect_count('select 1 from public.booking_status_events where booking_id = (select id from t_b)', 3, 'an admin reads booking history');
reset role;

select test_helpers.as_user('00000000-0000-0000-0000-000000000000', 'anon');
select test_helpers.expect_error('select 1 from public.notifications', '42501', 'anon cannot read notifications');
reset role;

-- mark read: the given ids, or everything, for that user only
create temp table t_unread as select count(*) as n from public.notifications
  where user_id = '11111111-1111-1111-1111-111111111111' and read_at is null;
grant select on t_unread to public;
select test_helpers.as_user('00000000-0000-0000-0000-000000000000', 'service_role');
select test_helpers.expect_eq(
  (select updated from public.mark_notifications_read('11111111-1111-1111-1111-111111111111',
    array[(select id from public.notifications where booking_id = (select id from t_b) and kind = 'booking_confirmed')]))::text,
  '1', 'marking one notification read');
select test_helpers.expect_eq(
  (select updated from public.mark_notifications_read('22222222-2222-2222-2222-222222222222',
    array[(select id from public.notifications where booking_id = (select id from t_b) and kind = 'driver_assigned')]))::text,
  '0', 'another user cannot mark someone else''s notification read');
select test_helpers.expect_eq(
  (select count(*)::text from public.notifications where booking_id = (select id from t_b) and read_at is null), '1', 'only the chosen one changed');
select test_helpers.expect_eq((select updated from public.mark_notifications_read('11111111-1111-1111-1111-111111111111'))::text,
  (select (n - 1)::text from t_unread), 'marking all read touches every remaining unread one');
select test_helpers.expect_count('select 1 from public.notifications where user_id = ''11111111-1111-1111-1111-111111111111'' and read_at is null', 0, 'nothing is left unread');
select test_helpers.expect_eq((select updated from public.mark_notifications_read('11111111-1111-1111-1111-111111111111'))::text, '0', 'marking again changes nothing');
reset role;

select test_helpers.expect_error(
  $q$insert into public.notifications (user_id, kind, title, body) values ('11111111-1111-1111-1111-111111111111', 'made_up', 'x', 'y')$q$,
  '23514', 'an unknown notification kind is refused');
select test_helpers.expect_error(
  $q$insert into public.notifications (user_id, kind, title, body) values ('11111111-1111-1111-1111-111111111111', 'booking_cancelled', ' ', 'y')$q$,
  '23514', 'a blank title is refused');
rollback;

-- deleting a booking removes its history and notifications (cascade)
begin;
do $$
declare v_b uuid := test_helpers.mk_booking('11111111-1111-1111-1111-111111111111', '01:00', '02:00', 45);
begin
  update public.bookings set status = 'cancelled', cancelled_at = now() where id = v_b;
  delete from public.bookings where id = v_b;
  perform test_helpers.expect_eq((select count(*)::text from public.booking_status_events where booking_id = v_b), '0', 'history goes with the booking');
  perform test_helpers.expect_eq((select count(*)::text from public.notifications where booking_id = v_b), '0', 'notifications go with the booking');
end $$;
rollback;

select 'PHASE 7 DB CHECKS COMPLETED' as result;
