-- =============================================================================
-- TEST-ONLY. Phase 5: payment rules in the database. Reuses the fixtures and
-- helpers of files 01 and 04 (customers 1111/2222, driver 3333, admin 5555).
-- =============================================================================
\set ON_ERROR_STOP on
\set QUIET on

-- A booking for `customer` on `current_date + day` (499 + optional 350 extra).
create or replace function test_helpers.mk_booking(
  p_customer uuid, p_start text, p_end text, p_day int, p_with_extra boolean default false
) returns uuid language plpgsql as $$
declare b public.bookings;
begin
  select * into b from public.create_booking(
    test_helpers.booking_json(p_customer, p_start, p_end, p_day),
    case when p_with_extra then jsonb_build_array(jsonb_build_object(
      'extra_charge_id', 'c0000000-0000-0000-0000-000000000001', 'charge_type', 'engine_oil',
      'name', 'Engine oil 10W-30', 'amount', 350.00, 'included_in_total', true))
    else '[]'::jsonb end);
  return b.id;
end $$;

-- An open payment attempt for the booking's full total.
create or replace function test_helpers.mk_attempt(p_booking uuid, p_order text)
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into public.payments (booking_id, customer_id, provider, provider_order_id, amount, currency, receipt)
  select id, customer_id, 'razorpay', p_order, total_amount, 'INR', 'FF-' || booking_number
  from public.bookings where id = p_booking
  returning id into v;
  return v;
end $$;

create or replace function test_helpers.apply(
  p_order text, p_payment text, p_outcome text, p_paise bigint, p_event text default null,
  p_currency text default 'INR', p_source text default 'webhook')
returns text language sql as $$
  select result from public.apply_payment_event(
    'razorpay', p_order, p_payment, p_outcome, p_paise, p_currency, 'upi',
    case when p_outcome = 'failed' then 'Card declined' end,
    p_source, p_event, 'payment.' || p_outcome, '{}'::jsonb);
$$;

create or replace function test_helpers.expect_eq(p_actual text, p_expected text, p_label text)
returns void language plpgsql as $$
begin
  if p_actual is distinct from p_expected then
    raise exception 'FAIL: % - expected %, got %', p_label, p_expected, p_actual;
  end if;
  raise notice 'PASS: %', p_label;
end $$;
grant execute on all functions in schema test_helpers to public;

-- -----------------------------------------------------------------------------
-- A successful payment confirms the booking, exactly once
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_b uuid := test_helpers.mk_booking('11111111-1111-1111-1111-111111111111', '01:00', '02:00', 20, true);
  v_p uuid := test_helpers.mk_attempt(v_b, 'order_A1');
  v_paid timestamptz;
begin
  perform test_helpers.expect_eq((select status::text from public.payments where id = v_p), 'pending', 'a new attempt is pending');
  perform test_helpers.expect_eq((select amount::text from public.payments where id = v_p), '849.00', 'the attempt holds the booking total');
  perform test_helpers.expect_eq((select status::text from public.bookings where id = v_b), 'pending_payment', 'an unpaid booking stays pending_payment');

  perform test_helpers.expect_eq(test_helpers.apply('order_A1', 'pay_A1', 'captured', 84900, 'evt_1'), 'paid', 'a captured payment is applied');
  perform test_helpers.expect_eq((select status::text from public.payments where id = v_p), 'successful', 'the payment becomes successful');
  perform test_helpers.expect_eq((select provider_payment_id from public.payments where id = v_p), 'pay_A1', 'the transaction reference is stored');
  perform test_helpers.expect_eq((select method from public.payments where id = v_p), 'upi', 'the payment method is stored');
  if (select paid_at from public.payments where id = v_p) is null then raise exception 'FAIL: paid_at missing'; end if;
  raise notice 'PASS: paid_at is set';
  perform test_helpers.expect_eq((select status::text from public.bookings where id = v_b), 'confirmed', 'the booking is confirmed by the verified payment');
  if (select confirmed_at from public.bookings where id = v_b) is null then raise exception 'FAIL: confirmed_at missing'; end if;
  raise notice 'PASS: confirmed_at is set';
  select paid_at into v_paid from public.payments where id = v_p;

  -- Duplicates
  perform test_helpers.expect_eq(test_helpers.apply('order_A1', 'pay_A1', 'captured', 84900, 'evt_1'), 'duplicate_event', 'the same webhook event twice is a no-op');
  perform test_helpers.expect_eq(test_helpers.apply('order_A1', 'pay_A1', 'captured', 84900, 'evt_2'), 'already_processed', 'a second event for the same payment is a no-op');
  perform test_helpers.expect_eq(test_helpers.apply('order_A1', 'pay_A1', 'captured', 84900, null, 'INR', 'verify'), 'already_processed', 'verify after the webhook is a no-op');
  perform test_helpers.expect_eq(test_helpers.apply('order_A1', 'pay_A1', 'captured', 84900, null, 'INR', 'verify'), 'already_processed', 'verify twice is a no-op');
  if (select paid_at from public.payments where id = v_p) <> v_paid then raise exception 'FAIL: paid_at changed by a replay'; end if;
  raise notice 'PASS: a replay does not touch the payment';
  perform test_helpers.expect_eq((select count(*)::text from public.payment_events where provider_order_id = 'order_A1'), '4', 'every distinct callback is logged (the replayed event id once)');

  -- A late failure never undoes a success
  perform test_helpers.expect_eq(test_helpers.apply('order_A1', 'pay_A1', 'failed', null, 'evt_3'), 'ignored', 'a failure after success is ignored');
  perform test_helpers.expect_eq((select status::text from public.payments where id = v_p), 'successful', 'the payment stays successful');

  -- A second capture on the same order is flagged, not accepted twice
  perform test_helpers.expect_eq(test_helpers.apply('order_A1', 'pay_A2', 'captured', 84900, 'evt_4'), 'duplicate_payment', 'a second capture on the same order is flagged');
  if not (select needs_review from public.payments where id = v_p) then raise exception 'FAIL: not flagged'; end if;
  raise notice 'PASS: the order is flagged for review';
  perform test_helpers.expect_eq((select provider_payment_id from public.payments where id = v_p), 'pay_A1', 'the original transaction stays recorded');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Amount and currency must match the order exactly
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_b uuid := test_helpers.mk_booking('11111111-1111-1111-1111-111111111111', '01:00', '02:00', 21);
  v_p uuid := test_helpers.mk_attempt(v_b, 'order_B1');
  v_b2 uuid := test_helpers.mk_booking('22222222-2222-2222-2222-222222222222', '01:00', '02:00', 21);
  v_p2 uuid := test_helpers.mk_attempt(v_b2, 'order_B2');
begin
  perform test_helpers.expect_eq(test_helpers.apply('order_B1', 'pay_B1', 'captured', 100, 'evt_b1'), 'amount_mismatch', 'a smaller amount is rejected');
  perform test_helpers.expect_eq((select status::text from public.bookings where id = v_b), 'pending_payment', 'a mismatched payment does not confirm the booking');
  perform test_helpers.expect_eq((select status::text from public.payments where id = v_p), 'failed', 'a mismatched attempt is marked failed');
  if not (select needs_review from public.payments where id = v_p) then raise exception 'FAIL: mismatch not flagged'; end if;
  raise notice 'PASS: a mismatch is flagged for review';

  perform test_helpers.expect_eq(test_helpers.apply('order_B2', 'pay_B2', 'captured', 49900, 'evt_b2', 'USD'), 'amount_mismatch', 'a different currency is rejected');
  perform test_helpers.expect_eq((select status::text from public.bookings where id = v_b2), 'pending_payment', 'a wrong-currency payment does not confirm the booking');

  -- A larger amount is a mismatch too.
  perform test_helpers.expect_eq(
    test_helpers.apply('order_B2', 'pay_B3', 'captured', 99900, 'evt_b3'), 'amount_mismatch', 'a larger amount is rejected');
  perform test_helpers.expect_eq(test_helpers.apply('order_NOPE', 'pay_X', 'captured', 49900, 'evt_x'), 'unknown_order', 'an unknown order is reported, not applied');
  perform test_helpers.expect_eq((select outcome from public.payment_events where event_id = 'evt_x'), 'unknown_order', 'the unknown order is logged');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Failed, cancelled and pending attempts
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_b uuid := test_helpers.mk_booking('11111111-1111-1111-1111-111111111111', '01:00', '02:00', 22);
  v_p uuid := test_helpers.mk_attempt(v_b, 'order_C1');
begin
  perform test_helpers.expect_eq(test_helpers.apply('order_C1', 'pay_C0', 'authorized', 49900, 'evt_c0'), 'pending', 'an authorized-only payment changes nothing');
  perform test_helpers.expect_eq((select status::text from public.payments where id = v_p), 'pending', 'the attempt is still pending');

  perform test_helpers.expect_eq(test_helpers.apply('order_C1', 'pay_C1', 'failed', null, 'evt_c1'), 'failed', 'a failure marks the attempt failed');
  perform test_helpers.expect_eq((select failure_reason from public.payments where id = v_p), 'Card declined', 'the failure reason is kept');
  perform test_helpers.expect_eq((select status::text from public.bookings where id = v_b), 'pending_payment', 'a failed payment leaves the booking pending_payment');

  -- The customer can retry on the same gateway order and succeed.
  perform test_helpers.expect_eq(test_helpers.apply('order_C1', 'pay_C2', 'captured', 49900, 'evt_c2'), 'paid', 'a retry on the same order can still succeed');
  perform test_helpers.expect_eq((select status::text from public.bookings where id = v_b), 'confirmed', 'the booking is confirmed after the retry');
  perform test_helpers.expect_eq((select failure_reason from public.payments where id = v_p), null, 'the old failure reason is cleared on success');
end $$;
rollback;

begin;
do $$
declare
  v_b uuid := test_helpers.mk_booking('11111111-1111-1111-1111-111111111111', '01:00', '02:00', 23);
  v_p uuid := test_helpers.mk_attempt(v_b, 'order_D1');
begin
  update public.payments set status = 'cancelled' where id = v_p;
  perform test_helpers.expect_eq(test_helpers.apply('order_D1', 'pay_D1', 'failed', null, 'evt_d0'), 'ignored', 'a failure for a cancelled attempt is ignored');
  perform test_helpers.expect_eq(test_helpers.apply('order_D1', 'pay_D1', 'captured', 49900, 'evt_d1'), 'paid', 'money that arrives after "cancel" is still honoured');
  perform test_helpers.expect_eq((select status::text from public.bookings where id = v_b), 'confirmed', 'the booking is confirmed');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Money for a cancelled booking, or a second payment for a paid one
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_b uuid := test_helpers.mk_booking('11111111-1111-1111-1111-111111111111', '01:00', '02:00', 24);
  v_p uuid := test_helpers.mk_attempt(v_b, 'order_E1');
begin
  update public.bookings set status = 'cancelled', cancelled_at = now() where id = v_b;
  perform test_helpers.expect_eq((select status::text from public.payments where id = v_p), 'cancelled', 'cancelling a booking closes its open payment attempt');
  perform test_helpers.expect_eq(test_helpers.apply('order_E1', 'pay_E1', 'captured', 49900, 'evt_e1'), 'paid_review', 'a payment for a cancelled booking is recorded for a refund');
  perform test_helpers.expect_eq((select status::text from public.bookings where id = v_b), 'cancelled', 'the cancelled booking stays cancelled');
  perform test_helpers.expect_eq((select status::text from public.payments where id = v_p), 'successful', 'the money taken is recorded as successful');
  if not (select needs_review from public.payments where id = v_p) then raise exception 'FAIL: not flagged'; end if;
  raise notice 'PASS: it is flagged for review';
end $$;
rollback;

begin;
do $$
declare
  v_b uuid := test_helpers.mk_booking('11111111-1111-1111-1111-111111111111', '01:00', '02:00', 25);
  v_p uuid := test_helpers.mk_attempt(v_b, 'order_F1');
  v_p2 uuid;
begin
  perform test_helpers.apply('order_F1', 'pay_F1', 'captured', 49900, 'evt_f1');
  -- A new attempt can still be created for a paid booking (the backend refuses, the DB is the backstop).
  v_p2 := test_helpers.mk_attempt(v_b, 'order_F2');
  perform test_helpers.expect_eq(test_helpers.apply('order_F2', 'pay_F2', 'captured', 49900, 'evt_f2'), 'duplicate_payment', 'a second payment for a paid booking is not accepted');
  perform test_helpers.expect_eq((select status::text from public.payments where id = v_p2), 'failed', 'the second payment is not recorded as a success');
  if not (select needs_review from public.payments where id = v_p2) then raise exception 'FAIL: not flagged'; end if;
  raise notice 'PASS: the second payment is flagged for a refund';
  perform test_helpers.expect_eq((select status::text from public.payments where id = v_p), 'successful', 'the first payment is untouched');

  -- Cancelling a paid booking flags its payment for a refund decision.
  update public.bookings set status = 'cancelled', cancelled_at = now() where id = v_b;
  if not (select needs_review from public.payments where id = v_p) then raise exception 'FAIL: paid+cancelled not flagged'; end if;
  raise notice 'PASS: cancelling a paid booking flags the payment for review';
  perform test_helpers.expect_eq((select status::text from public.payments where id = v_p), 'successful', 'the payment record itself is unchanged');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Constraints and the update guard
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_b uuid := test_helpers.mk_booking('11111111-1111-1111-1111-111111111111', '01:00', '02:00', 26);
  v_p uuid := test_helpers.mk_attempt(v_b, 'order_G1');
  v_b2 uuid := test_helpers.mk_booking('22222222-2222-2222-2222-222222222222', '01:00', '02:00', 26);
  v_q uuid := test_helpers.mk_attempt(v_b2, 'order_G2');
begin
  perform test_helpers.expect_error(format($q$select test_helpers.mk_attempt(%L, 'order_G9')$q$, v_b), '23505', 'only one open attempt per booking');
  perform test_helpers.expect_error(format($q$update public.payments set amount = 1 where id = %L$q$, v_p), '23514', 'the amount cannot be changed');
  perform test_helpers.expect_error(format($q$update public.payments set booking_id = %L, customer_id = '22222222-2222-2222-2222-222222222222' where id = %L$q$, v_b2, v_p), '23514', 'the booking cannot be changed');
  perform test_helpers.expect_error(format($q$update public.payments set provider_order_id = 'other' where id = %L$q$, v_p), '23514', 'the gateway order cannot be changed');
  perform test_helpers.expect_error(format($q$update public.payments set status = 'successful' where id = %L$q$, v_p), '23514', 'a success needs a transaction reference and time');
  perform test_helpers.expect_error(format($q$update public.payments set needs_review = true where id = %L$q$, v_p), '23514', 'a review flag needs a reason');
  perform test_helpers.expect_error($q$insert into public.payments (booking_id, customer_id, provider, provider_order_id, amount) select id, customer_id, 'razorpay', 'order_G1', 10 from public.bookings limit 1$q$, '23505', 'a gateway order maps to one attempt only');

  perform test_helpers.apply('order_G1', 'pay_G1', 'captured', 49900, 'evt_g1');
  perform test_helpers.expect_error(format($q$update public.payments set status = 'failed' where id = %L$q$, v_p), '23514', 'a successful payment cannot become failed');
  perform test_helpers.expect_error(format($q$update public.payments set paid_at = now() - interval '1 day' where id = %L$q$, v_p), '23514', 'a successful payment cannot be edited');
  perform test_helpers.expect_error(format($q$update public.payments set status = 'pending' where id = %L$q$, v_p), '23514', 'a successful payment cannot go back to pending');

  -- failed -> cancelled is not a legal move
  perform test_helpers.apply('order_G2', 'pay_G2', 'failed', null, 'evt_g2');
  perform test_helpers.expect_error(format($q$update public.payments set status = 'cancelled' where id = %L$q$, v_q), '23514', 'a failed attempt cannot become cancelled');
  perform test_helpers.expect_error(format($q$update public.payments set status = 'pending' where id = %L$q$, v_q), '23514', 'a failed attempt cannot go back to pending');
  perform test_helpers.expect_error(
    $q$insert into public.payments (booking_id, customer_id, provider, provider_order_id, provider_payment_id, amount, status, paid_at)
       select id, customer_id, 'razorpay', 'order_G7', 'pay_G1', 499, 'successful', now() from public.bookings where customer_id = '22222222-2222-2222-2222-222222222222' limit 1$q$,
    '23505', 'a gateway transaction maps to one payment only');
  perform test_helpers.expect_error(
    $q$insert into public.payments (booking_id, customer_id, provider, amount, currency) select id, '11111111-1111-1111-1111-111111111111', 'razorpay', 10, 'INR' from public.bookings where customer_id = '22222222-2222-2222-2222-222222222222' limit 1$q$,
    '23503', 'a payment must belong to the booking''s own customer');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Who can see and do what
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  v_b uuid := test_helpers.mk_booking('11111111-1111-1111-1111-111111111111', '01:00', '02:00', 27);
  v_b2 uuid := test_helpers.mk_booking('22222222-2222-2222-2222-222222222222', '01:00', '02:00', 27);
begin
  perform test_helpers.mk_attempt(v_b, 'order_H1');
  perform test_helpers.mk_attempt(v_b2, 'order_H2');
  perform test_helpers.apply('order_H1', 'pay_H1', 'captured', 49900, 'evt_h1');
end $$;

select test_helpers.as_user('11111111-1111-1111-1111-111111111111');
do $$
begin
  perform test_helpers.expect_count($q$select id from public.payments where customer_id <> '11111111-1111-1111-1111-111111111111'$q$, 0, 'a customer sees no one else''s payments');
  perform test_helpers.expect_count($q$select id from public.payments where provider = 'razorpay'$q$, 1, 'a customer sees their own payment');
  perform test_helpers.expect_count($q$select 1 from public.payments where provider_payment_id = 'pay_H1'$q$, 1, 'a customer can read the transaction reference');
  perform test_helpers.expect_error('select needs_review from public.payments', '42501', 'a customer cannot read the internal review flag');
  perform test_helpers.expect_error('select review_reason from public.payments', '42501', 'a customer cannot read the review reason');
  perform test_helpers.expect_error($q$update public.payments set status = 'successful'$q$, '42501', 'a customer cannot mark a payment successful');
  perform test_helpers.expect_error($q$insert into public.payments (booking_id, customer_id, provider, amount) select id, customer_id, 'razorpay', 1 from public.bookings limit 1$q$, '42501', 'a customer cannot create payments');
  perform test_helpers.expect_error($q$delete from public.payments$q$, '42501', 'a customer cannot delete payments');
  perform test_helpers.expect_error($q$select * from public.apply_payment_event('razorpay','o','p','captured',1,'INR',null,null,'verify',null,'x')$q$, '42501', 'a customer cannot call apply_payment_event');
  perform test_helpers.expect_count('select 1 from public.payment_events', 0, 'a customer cannot read the event log');
end $$;
reset role;

select test_helpers.as_user('55555555-5555-5555-5555-555555555555');
do $$
begin
  perform test_helpers.expect_count($q$select id from public.payments where provider = 'razorpay'$q$, 2, 'an admin sees all payments');
  perform test_helpers.expect_count($q$select 1 from public.payment_events where provider = 'razorpay'$q$, 1, 'an admin can read the event log');
  perform test_helpers.expect_error($q$update public.payments set status = 'failed'$q$, '42501', 'an admin cannot edit payments over the API');
end $$;
reset role;

select test_helpers.as_user('33333333-3333-3333-3333-333333333333');
select test_helpers.expect_count('select 1 from public.payments', 0, 'a driver sees no payments');
select test_helpers.expect_count('select 1 from public.payment_events', 0, 'a driver sees no payment events');
reset role;

select test_helpers.as_user('00000000-0000-0000-0000-000000000000', 'anon');
select test_helpers.expect_error('select 1 from public.payments', '42501', 'anon cannot read payments');
select test_helpers.expect_error('select 1 from public.payment_events', '42501', 'anon cannot read events');
reset role;

select test_helpers.as_user('00000000-0000-0000-0000-000000000000', 'service_role');
select test_helpers.expect_eq(
  (select result from public.apply_payment_event('razorpay','order_H2','pay_H2','captured',49900,'INR','card',null,'webhook','evt_h2','payment.captured')),
  'paid', 'service_role can apply payment events');
reset role;
rollback;

select 'PHASE 5 DB CHECKS COMPLETED' as result;
