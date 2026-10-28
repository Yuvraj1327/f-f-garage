-- =============================================================================
-- TEST-ONLY. Service flow: coupons, advance/balance payments, extra charge
-- requests that need approval, refund records. Reuses fixtures/helpers of files
-- 01, 04, 05 and 06 (customers 1111/2222, driver 3333, admin 5555).
-- =============================================================================
\set ON_ERROR_STOP on
\set QUIET on

-- A booking payload with a coupon, discount and advance.
create or replace function test_helpers.coupon_json(
  p_customer uuid, p_start text, p_end text, p_day int, p_code text, p_discount numeric,
  p_advance numeric default 0)
returns jsonb language sql as $$
  select test_helpers.booking_json(p_customer, p_start, p_end, p_day)
    || jsonb_build_object('coupon_code', p_code, 'discount_amount', p_discount,
                          'advance_percent', 20, 'advance_amount', p_advance);
$$;
grant execute on all functions in schema test_helpers to public;

-- A booking that is paid (advance), assigned and in progress.
create or replace function test_helpers.mk_in_progress(p_customer uuid, p_start text, p_end text, p_day int)
returns uuid language plpgsql as $$
declare v uuid := test_helpers.mk_paid(p_customer, p_start, p_end, p_day);
begin
  perform test_helpers.assign(v, '33333333-3333-3333-3333-333333333333');
  perform test_helpers.drive(v, '33333333-3333-3333-3333-333333333333', 'on_the_way');
  perform test_helpers.drive(v, '33333333-3333-3333-3333-333333333333', 'in_progress');
  return v;
end $$;

create or replace function test_helpers.mk_extra(p_booking uuid, p_name text, p_amount numeric)
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into public.booking_extra_requests (booking_id, name, amount, requested_by_role, requested_by)
  values (p_booking, p_name, p_amount, 'driver', '33333333-3333-3333-3333-333333333333')
  returning id into v;
  return v;
end $$;
grant execute on all functions in schema test_helpers to public;

-- -----------------------------------------------------------------------------
-- Catalogue columns
-- -----------------------------------------------------------------------------
begin;
do $$
begin
  perform test_helpers.expect_eq(
    (select catalog_tab from public.services where id = 'a0000000-0000-0000-0000-000000000001'),
    'package', 'existing services default to the package tab');
  perform test_helpers.expect_error(
    $q$update public.services set catalog_tab = 'cars' where id = 'a0000000-0000-0000-0000-000000000001'$q$,
    '23514', 'an unknown catalogue tab is rejected');
  perform test_helpers.expect_error(
    $q$update public.services set image_url = 'http://insecure.example/x.jpg' where id = 'a0000000-0000-0000-0000-000000000001'$q$,
    '23514', 'a picture URL must be https');
  perform test_helpers.expect_error(
    $q$update public.service_packages set original_price = 100 where id = 'b0000000-0000-0000-0000-000000000001'$q$,
    '23514', 'the original price cannot be below the price');
  perform test_helpers.expect_error(
    $q$update public.service_packages set parts_policy = 'free' where id = 'b0000000-0000-0000-0000-000000000001'$q$,
    '23514', 'the parts policy must be a known value');
  update public.service_packages
    set original_price = 599, warranty_days = 7, exclusions = array['Spare parts'], parts_policy = 'parts_extra'
    where id = 'b0000000-0000-0000-0000-000000000001';
  perform test_helpers.expect_eq(
    (select warranty_days::text from public.service_packages where id = 'b0000000-0000-0000-0000-000000000001'),
    '7', 'warranty, exclusions and parts policy can be stored');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Coupons: discount, estimated total, limits
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  alice uuid := '11111111-1111-1111-1111-111111111111';
  bob uuid := '22222222-2222-2222-2222-222222222222';
  b public.bookings;
  b2 public.bookings;
begin
  insert into public.coupons (code, discount_type, discount_value, usage_limit, per_customer_limit)
  values ('FLAT50', 'flat', 50, 1, 1);
  insert into public.coupons (code, discount_type, discount_value, is_active)
  values ('OFF10', 'percent', 10, false);
  insert into public.coupons (code, discount_type, discount_value, ends_at, starts_at)
  values ('OLD20', 'flat', 20, now() - interval '1 day', now() - interval '2 days');

  select * into b from public.create_booking(
    test_helpers.coupon_json(alice, '10:00', '11:00', 50, 'FLAT50', 50, 99.80));
  perform test_helpers.expect_eq(b.total_amount::text, '449.00', 'the estimated total is package + add-ons - discount');
  perform test_helpers.expect_eq(b.advance_amount::text, '99.80', 'the advance is stored on the booking');
  perform test_helpers.expect_eq(b.coupon_code, 'FLAT50', 'the coupon code is stored');
  perform test_helpers.expect_eq(
    (select amount::text from public.coupon_redemptions where booking_id = b.id), '50.00',
    'the redemption is recorded');

  perform test_helpers.expect_error(
    format('select * from public.create_booking(%L::jsonb)',
           test_helpers.coupon_json(bob, '10:00', '11:00', 51, 'FLAT50', 50)::text),
    '23P01', 'a coupon with a total usage limit cannot be used past it');
  perform test_helpers.expect_error(
    format('select * from public.create_booking(%L::jsonb)',
           test_helpers.coupon_json(alice, '10:00', '11:00', 52, 'OFF10', 10)::text),
    '23P01', 'an inactive coupon is refused');
  perform test_helpers.expect_error(
    format('select * from public.create_booking(%L::jsonb)',
           test_helpers.coupon_json(alice, '10:00', '11:00', 52, 'OLD20', 20)::text),
    '23P01', 'an expired coupon is refused');
  perform test_helpers.expect_error(
    format('select * from public.create_booking(%L::jsonb)',
           test_helpers.coupon_json(alice, '10:00', '11:00', 52, 'NOPE99', 20)::text),
    '23P01', 'an unknown coupon is refused');
  perform test_helpers.expect_error(
    format('select * from public.create_booking(%L::jsonb)',
           (test_helpers.booking_json(alice, '10:00', '11:00', 52) || '{"discount_amount": 30}'::jsonb)::text),
    '23514', 'a discount without a coupon is refused');

  -- Per-customer limit, and cancelling gives the coupon back.
  update public.coupons set usage_limit = null where code = 'FLAT50';
  perform test_helpers.expect_error(
    format('select * from public.create_booking(%L::jsonb)',
           test_helpers.coupon_json(alice, '12:00', '13:00', 53, 'FLAT50', 50)::text),
    '23P01', 'a customer cannot use a once-per-customer coupon twice');
  update public.bookings set status = 'cancelled', cancelled_at = now() where id = b.id;
  select * into b2 from public.create_booking(
    test_helpers.coupon_json(alice, '12:00', '13:00', 53, 'FLAT50', 50));
  perform test_helpers.expect_eq(b2.total_amount::text, '449.00', 'a cancelled booking releases its coupon');
  perform test_helpers.expect_eq(
    (select count(*)::text from public.coupon_redemptions where coupon_id = (select id from public.coupons where code = 'FLAT50')),
    '2', 'both redemptions are kept for the record');

  -- Price fields are locked after creation.
  perform test_helpers.expect_error(
    format('update public.bookings set advance_amount = 1 where id = %L', b2.id),
    '23514', 'the advance cannot be changed after booking');
  perform test_helpers.expect_error(
    format('update public.bookings set discount_amount = 0 where id = %L', b2.id),
    '23514', 'the discount cannot be changed after booking');
  perform test_helpers.expect_error(
    format('select * from public.create_booking(%L::jsonb)',
           test_helpers.coupon_json(bob, '14:00', '15:00', 54, 'FLAT50', 5000)::text),
    '23514', 'a discount larger than the price is refused');
  perform test_helpers.expect_error(
    format('select * from public.create_booking(%L::jsonb)',
           test_helpers.coupon_json(bob, '14:00', '15:00', 54, 'FLAT50', 50, 9999)::text),
    '23514', 'an advance larger than the total is refused');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Advance and balance payments
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  alice uuid := '11111111-1111-1111-1111-111111111111';
  d1 uuid := '33333333-3333-3333-3333-333333333333';
  v_b uuid;
  v_x uuid;
  v_adv uuid;
  v_bal uuid;
begin
  -- Estimated 499, advance 99.80, then an approved extra of 200 -> final 699, balance 599.20.
  v_b := (select id from public.create_booking(
            test_helpers.coupon_json(alice, '16:00', '17:00', 60, null, 0, 99.80)));
  insert into public.payments (booking_id, customer_id, provider, provider_order_id, amount, currency, receipt, kind)
    values (v_b, alice, 'razorpay', 'order_ADV', 99.80, 'INR', 'FF-ADV', 'advance') returning id into v_adv;
  perform test_helpers.expect_eq(test_helpers.apply('order_ADV', 'pay_ADV', 'captured', 9980), 'paid', 'the advance is captured');
  perform test_helpers.expect_eq(test_helpers.status_of(v_b), 'confirmed', 'a paid advance confirms the booking');
  perform test_helpers.expect_eq(
    test_helpers.apply('order_ADV', 'pay_ADV', 'captured', 9980, 'evt_adv_again'), 'already_processed',
    'a repeated callback changes nothing');

  perform test_helpers.assign(v_b, d1);
  perform test_helpers.drive(v_b, d1, 'on_the_way');
  perform test_helpers.drive(v_b, d1, 'in_progress');

  v_x := test_helpers.mk_extra(v_b, 'Brake pad set', 200);
  perform test_helpers.expect_eq(
    (select string_agg(kind, ',' order by seq) from public.notifications where booking_id = v_b and kind = 'extra_charge_requested'),
    'extra_charge_requested', 'the customer is told an extra charge needs approval');
  perform test_helpers.expect_eq(test_helpers.drive(v_b, d1, 'completed'), 'extras_pending',
    'the driver cannot finish while a request is unanswered');
  perform test_helpers.expect_eq(test_helpers.status_of(v_b), 'in_progress', 'the booking stays in progress');

  update public.booking_extra_requests set status = 'approved', decided_at = now() where id = v_x;
  perform test_helpers.expect_eq(test_helpers.drive(v_b, d1, 'completed'), 'updated', 'finishing works once the request is answered');
  perform test_helpers.expect_eq(
    (select sum(amount)::text from public.booking_extra_requests where booking_id = v_b and status = 'approved'),
    '200.00', 'approved extras add up');

  -- Balance: its own attempt, its own success, the booking stays completed.
  insert into public.payments (booking_id, customer_id, provider, provider_order_id, amount, currency, receipt, kind)
    values (v_b, alice, 'razorpay', 'order_BAL', 599.20, 'INR', 'FF-BAL', 'balance') returning id into v_bal;
  perform test_helpers.expect_eq(test_helpers.apply('order_BAL', 'pay_BAL', 'captured', 59920), 'paid', 'the balance is captured');
  perform test_helpers.expect_eq(test_helpers.status_of(v_b), 'completed', 'a balance payment does not change the status');
  perform test_helpers.expect_eq(
    (select count(*)::text from public.payments where booking_id = v_b and status = 'successful'),
    '2', 'one advance and one balance payment are both successful');
  perform test_helpers.expect_error(
    format($q$insert into public.payments (booking_id, customer_id, provider, provider_order_id, provider_payment_id, amount, currency, kind, status, paid_at)
              values (%L, %L, 'razorpay', 'order_BAL2', 'pay_BAL2', 10, 'INR', 'balance', 'successful', now())$q$, v_b, alice),
    '23505', 'only one successful balance payment per booking');
  perform test_helpers.expect_error(
    format('update public.payments set kind = %L where id = %L', 'balance', v_adv),
    '23514', 'the kind of a payment cannot change');

  -- A second balance attempt is flagged, not silently accepted.
  insert into public.payments (booking_id, customer_id, provider, provider_order_id, amount, currency, receipt, kind)
    values (v_b, alice, 'razorpay', 'order_BAL3', 599.20, 'INR', 'FF-BAL3', 'balance');
  perform test_helpers.expect_eq(test_helpers.apply('order_BAL3', 'pay_BAL3', 'captured', 59920, 'evt_bal3'), 'duplicate_payment',
    'a second balance payment is a duplicate');
  perform test_helpers.expect_eq(
    (select needs_review::text from public.payments where provider_order_id = 'order_BAL3'), 'true',
    'the duplicate is flagged for review');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Extra charge requests
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  alice uuid := '11111111-1111-1111-1111-111111111111';
  v_early uuid := test_helpers.mk_paid(alice, '18:00', '19:00', 61);
  v_b uuid := test_helpers.mk_in_progress(alice, '20:00', '21:00', 61);
  v_x uuid;
begin
  perform test_helpers.expect_error(
    format($q$insert into public.booking_extra_requests (booking_id, name, amount, requested_by_role)
              values (%L, 'Chain', 100, 'driver')$q$, v_early),
    '23514', 'a request cannot be raised before the service is in progress');
  v_x := test_helpers.mk_extra(v_b, 'Chain set', 450);
  perform test_helpers.expect_eq((select status from public.booking_extra_requests where id = v_x), 'proposed', 'a new request waits for approval');
  perform test_helpers.expect_error(
    format($q$insert into public.booking_extra_requests (booking_id, name, amount, requested_by_role)
              values (%L, 'Free', 0, 'driver')$q$, v_b),
    '23514', 'an extra charge must be above zero');
  perform test_helpers.expect_error(
    format($q$insert into public.booking_extra_requests (booking_id, name, amount, requested_by_role)
              values (%L, 'Chain', 100, 'customer')$q$, v_b),
    '23514', 'only a driver or admin can request an extra charge');
  perform test_helpers.expect_error(
    format('update public.booking_extra_requests set amount = 1 where id = %L', v_x),
    '23514', 'a request cannot be edited');
  perform test_helpers.expect_error(
    format($q$update public.booking_extra_requests set status = 'approved' where id = %L$q$, v_x),
    '23514', 'an answer must be timestamped');

  update public.booking_extra_requests set status = 'declined', decided_at = now() where id = v_x;
  perform test_helpers.expect_error(
    format($q$update public.booking_extra_requests set status = 'approved', decided_at = now() where id = %L$q$, v_x),
    '23514', 'an answered request cannot be answered again');

  -- Cancelling the booking withdraws requests still waiting.
  v_x := test_helpers.mk_extra(v_b, 'Spark plug', 120);
  update public.bookings set status = 'cancelled', cancelled_at = now() where id = v_b;
  perform test_helpers.expect_eq((select status from public.booking_extra_requests where id = v_x), 'withdrawn',
    'a cancelled booking withdraws open requests');
end $$;
rollback;

-- Who can read the requests.
begin;
do $$
declare
  v_b uuid := test_helpers.mk_in_progress('11111111-1111-1111-1111-111111111111', '22:00', '23:00', 62);
begin
  perform test_helpers.mk_extra(v_b, 'Clutch plate', 300);
  perform set_config('test.booking', v_b::text, true);
end $$;
select test_helpers.as_user('11111111-1111-1111-1111-111111111111');
do $$ begin
  perform test_helpers.expect_count(
    format('select 1 from public.booking_extra_requests where booking_id = %L', current_setting('test.booking')),
    1, 'the customer sees the requests on their booking');
  perform test_helpers.expect_error(
    format($q$update public.booking_extra_requests set status = 'approved', decided_at = now() where booking_id = %L$q$, current_setting('test.booking')),
    '42501', 'the customer answers through the backend, not the database API');
end $$;
rollback;

begin;
do $$
declare
  v_b uuid := test_helpers.mk_in_progress('11111111-1111-1111-1111-111111111111', '22:00', '23:00', 63);
begin
  perform test_helpers.mk_extra(v_b, 'Clutch plate', 300);
  perform set_config('test.booking', v_b::text, true);
end $$;
select test_helpers.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin
  perform test_helpers.expect_count(
    format('select 1 from public.booking_extra_requests where booking_id = %L', current_setting('test.booking')),
    0, 'another customer sees nothing');
end $$;
rollback;

-- -----------------------------------------------------------------------------
-- Refund records
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  alice uuid := '11111111-1111-1111-1111-111111111111';
  admin uuid := '55555555-5555-5555-5555-555555555555';
  v_b uuid := test_helpers.mk_paid(alice, '08:00', '09:00', 70);
  v_p uuid;
  r record;
begin
  select id into v_p from public.payments where booking_id = v_b;
  update public.bookings set status = 'cancelled', cancelled_at = now() where id = v_b;
  perform test_helpers.expect_eq((select needs_review::text from public.payments where id = v_p), 'true',
    'cancelling a paid booking flags the payment for a decision');

  select * into r from public.record_payment_refund(v_p, 100, 'Refund made in the gateway dashboard', admin);
  perform test_helpers.expect_eq(r.result, 'recorded', 'a refund can be recorded');
  perform test_helpers.expect_eq((select needs_review::text from public.payments where id = v_p), 'false',
    'recording a refund clears the review flag');
  perform test_helpers.expect_eq(
    (select string_agg(kind, ',') from public.notifications where booking_id = v_b and kind = 'refund_recorded'),
    'refund_recorded', 'the customer is told about the refund');
  perform test_helpers.expect_eq(
    (select result from public.record_payment_refund(v_p, 500, null, admin)), 'exceeds_payment',
    'refunds cannot add up to more than the payment');
  perform test_helpers.expect_eq(
    (select result from public.record_payment_refund(v_p, 399, null, admin)), 'recorded',
    'the rest of the payment can still be refunded');
  perform test_helpers.expect_eq(
    (select result from public.record_payment_refund(v_p, 1, null, admin)), 'exceeds_payment',
    'a fully refunded payment cannot be refunded again');
  perform test_helpers.expect_eq(
    (select status::text from public.payments where id = v_p), 'successful',
    'the payment itself stays successful');
  perform test_helpers.expect_eq(
    (select result from public.record_payment_refund(gen_random_uuid(), 1, null, admin)), 'payment_not_found',
    'an unknown payment is reported');
end $$;
rollback;

-- Refund policy text
begin;
do $$
begin
  insert into public.garage_settings (id) values (true) on conflict do nothing;
  update public.garage_settings set refund_policy = 'Policy text';
  perform test_helpers.expect_eq((select refund_policy from public.garage_settings), 'Policy text', 'the refund policy text is stored');
  perform test_helpers.expect_error(
    $q$update public.garage_settings set refund_policy = repeat('x', 1001)$q$,
    '23514', 'the refund policy has a length limit');
end $$;
rollback;
