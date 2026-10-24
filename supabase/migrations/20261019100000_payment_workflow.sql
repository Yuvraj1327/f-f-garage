-- =============================================================================
-- Migration 9: payment workflow (Razorpay, but nothing here is Razorpay-specific)
-- =============================================================================
-- Builds on the `payments` table from migration 5.
--
--   * payment_status gains 'cancelled' (the customer closed checkout).
--   * payments gains method, livemode (test vs live money), receipt and the
--     needs_review flag for money that needs a human (refund, mismatch).
--   * payment_events: an audit log of every verified gateway callback; the unique
--     (provider, event_id) makes webhook replays harmless.
--   * apply_payment_event(): THE ONLY way a payment becomes successful and a booking
--     becomes confirmed. One transaction, row locks on the payment and the booking,
--     idempotent, with the amount and currency checked against what was ordered.
--   * guard_payment_update(): legal status changes and immutable columns.
--   * Cancelling a booking cancels its open payment attempt and flags a paid booking
--     for a refund decision (refunds themselves are not automated yet).
--
-- NOTE: the new enum value is not used by any statement that runs in this file
-- (it is only referenced inside function bodies), so this works inside the
-- single-transaction migration runners.
-- =============================================================================

alter type public.payment_status add value if not exists 'cancelled';

alter table public.payments
  add column method text,
  add column receipt text,
  add column livemode boolean not null default false,
  add column needs_review boolean not null default false,
  add column review_reason text;

alter table public.payments
  add constraint payments_method_valid
    check (method is null or (btrim(method) <> '' and char_length(method) <= 40)),
  add constraint payments_receipt_valid
    check (receipt is null or (btrim(receipt) <> '' and char_length(receipt) <= 40)),
  add constraint payments_failure_reason_valid
    check (failure_reason is null or char_length(failure_reason) <= 500),
  add constraint payments_review_reason_valid
    check (review_reason is null or char_length(review_reason) <= 500),
  add constraint payments_review_has_reason
    check (not needs_review or review_reason is not null);

-- One open attempt per booking, so two taps cannot create two live orders.
create unique index payments_one_pending_per_booking
  on public.payments (booking_id)
  where status = 'pending';
create index payments_review_idx
  on public.payments (created_at desc)
  where needs_review;
create index payments_receipt_idx on public.payments (receipt) where receipt is not null;

-- -----------------------------------------------------------------------------
-- Audit log of gateway callbacks
-- -----------------------------------------------------------------------------
create table public.payment_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  source text not null,
  event_id text,
  event_type text not null,
  payment_id uuid references public.payments (id) on delete restrict,
  provider_order_id text,
  provider_payment_id text,
  outcome text not null default 'received',
  detail jsonb,
  created_at timestamptz not null default now(),

  constraint payment_events_source_valid check (source in ('webhook', 'verify')),
  constraint payment_events_provider_not_blank check (btrim(provider) <> ''),
  constraint payment_events_event_id_not_blank check (event_id is null or btrim(event_id) <> '')
);

-- A replayed webhook (same gateway event id) can only be logged once.
create unique index payment_events_provider_event_key
  on public.payment_events (provider, event_id)
  where event_id is not null;
create index payment_events_payment_idx on public.payment_events (payment_id, created_at);
create index payment_events_order_idx on public.payment_events (provider_order_id);

alter table public.payment_events enable row level security;
revoke all on table public.payment_events from anon, authenticated;
grant select on table public.payment_events to authenticated;
grant all on table public.payment_events to service_role;
create policy payment_events_select_admin
  on public.payment_events for select to authenticated
  using ((select public.is_admin()));

-- Customers may read their own payments, but not the internal review columns.
revoke select on table public.payments from authenticated;
grant select (id, booking_id, customer_id, provider, provider_order_id, provider_payment_id,
              amount, currency, status, failure_reason, paid_at, created_at, updated_at,
              method, receipt, livemode)
  on public.payments to authenticated;

-- -----------------------------------------------------------------------------
-- Legal changes to a payment row
-- -----------------------------------------------------------------------------
create function public.guard_payment_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.booking_id is distinct from old.booking_id
     or new.customer_id is distinct from old.customer_id
     or new.provider is distinct from old.provider
     or new.amount is distinct from old.amount
     or new.currency is distinct from old.currency
     or new.receipt is distinct from old.receipt
     or new.livemode is distinct from old.livemode
     or new.created_at is distinct from old.created_at
     or (old.provider_order_id is not null
         and new.provider_order_id is distinct from old.provider_order_id) then
    raise exception 'The booking, amount, currency and gateway order of a payment cannot be changed'
      using errcode = '23514';
  end if;

  if old.status = 'successful' then
    -- A successful payment is final; only the review flag may still be raised.
    if new.status is distinct from old.status
       or new.provider_payment_id is distinct from old.provider_payment_id
       or new.paid_at is distinct from old.paid_at
       or new.method is distinct from old.method
       or new.failure_reason is distinct from old.failure_reason then
      raise exception 'A successful payment cannot be changed' using errcode = '23514';
    end if;
    return new;
  end if;

  if new.status <> old.status and not (
       (old.status = 'pending' and new.status in ('successful', 'failed', 'cancelled'))
    or (old.status in ('failed', 'cancelled') and new.status = 'successful')
  ) then
    raise exception 'A payment cannot move from % to %', old.status, new.status
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger payments_guard_update
  before update on public.payments
  for each row execute function public.guard_payment_update();

-- -----------------------------------------------------------------------------
-- The one place a payment succeeds and a booking is confirmed
-- -----------------------------------------------------------------------------
-- p_outcome: 'captured' (money taken), 'failed', or anything else (e.g. 'authorized'),
-- which changes nothing. Amounts are in paise (the gateway's unit).
--
-- result:
--   paid               payment successful, booking confirmed
--   paid_review        payment successful but the booking was already cancelled (refund)
--   already_processed  same payment id seen before; nothing changed
--   duplicate_payment  a second payment for a booking that is already paid (refund)
--   amount_mismatch    gateway amount/currency differs from the order; not accepted
--   failed             attempt marked failed
--   pending            nothing to change yet
--   ignored            a failure for a payment that already succeeded / was cancelled
--   duplicate_event    this gateway event id was already handled
--   unknown_order      no payment attempt for that gateway order
create function public.apply_payment_event(
  p_provider text,
  p_order_id text,
  p_payment_id text,
  p_outcome text,
  p_amount_paise bigint,
  p_currency text,
  p_method text,
  p_failure text,
  p_source text,
  p_event_id text,
  p_event_type text,
  p_detail jsonb default null
)
returns table (
  result text,
  payment_id uuid,
  payment_status public.payment_status,
  booking_id uuid,
  booking_status public.booking_status
)
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_event uuid;
  v_pay public.payments;
  v_booking public.bookings;
  v_result text;
  v_other uuid;
begin
  -- 1. Log the callback; a replayed webhook stops here.
  if p_event_id is not null then
    insert into public.payment_events
      (provider, source, event_id, event_type, provider_order_id, provider_payment_id, detail)
    values (p_provider, p_source, p_event_id, p_event_type, p_order_id, p_payment_id, p_detail)
    on conflict (provider, event_id) where event_id is not null do nothing
    returning id into v_event;
    if v_event is null then
      return query
        select 'duplicate_event'::text, e.payment_id, p.status, p.booking_id, b.status
        from public.payment_events e
        left join public.payments p on p.id = e.payment_id
        left join public.bookings b on b.id = p.booking_id
        where e.provider = p_provider and e.event_id = p_event_id;
      return;
    end if;
  else
    insert into public.payment_events
      (provider, source, event_type, provider_order_id, provider_payment_id, detail)
    values (p_provider, p_source, p_event_type, p_order_id, p_payment_id, p_detail)
    returning id into v_event;
  end if;

  -- 2. Find and lock the attempt.
  select * into v_pay
  from public.payments p
  where p.provider = p_provider and p.provider_order_id = p_order_id
  for update;
  if not found then
    update public.payment_events set outcome = 'unknown_order' where id = v_event;
    return query select 'unknown_order'::text, null::uuid, null::public.payment_status,
                        null::uuid, null::public.booking_status;
    return;
  end if;

  if p_outcome = 'captured' then
    if p_amount_paise is distinct from (v_pay.amount * 100)::bigint
       or p_currency is distinct from v_pay.currency then
      -- Never accept a payment that is not exactly what was ordered.
      if v_pay.status = 'successful' then
        update public.payments set needs_review = true,
          review_reason = left('Gateway reported a different amount for a second payment', 500)
          where id = v_pay.id;
      else
        update public.payments set
          status = 'failed',
          failure_reason = left(format('Amount mismatch: ordered %s %s, gateway reported %s paise %s',
                                       v_pay.amount, v_pay.currency, p_amount_paise, p_currency), 500),
          provider_payment_id = coalesce(p_payment_id, provider_payment_id),
          needs_review = true,
          review_reason = 'The gateway reported money taken in a different amount than the order. Check and refund if needed.'
          where id = v_pay.id;
      end if;
      v_result := 'amount_mismatch';

    elsif v_pay.status = 'successful' then
      if v_pay.provider_payment_id = p_payment_id then
        v_result := 'already_processed';
      else
        update public.payments set needs_review = true,
          review_reason = 'A second payment was captured for this order. Refund the extra payment.'
          where id = v_pay.id;
        v_result := 'duplicate_payment';
      end if;

    else
      select * into v_booking from public.bookings b where b.id = v_pay.booking_id for update;
      select p.id into v_other from public.payments p
        where p.booking_id = v_pay.booking_id and p.status = 'successful' and p.id <> v_pay.id
        limit 1;
      if v_other is not null then
        update public.payments set
          status = 'failed',
          failure_reason = 'The booking was already paid by another payment',
          provider_payment_id = coalesce(p_payment_id, provider_payment_id),
          method = coalesce(p_method, method),
          needs_review = true,
          review_reason = 'Money was captured for a booking that is already paid. Refund this payment.'
          where id = v_pay.id;
        v_result := 'duplicate_payment';
      else
        update public.payments set
          status = 'successful',
          provider_payment_id = p_payment_id,
          method = coalesce(p_method, method),
          paid_at = now(),
          failure_reason = null
          where id = v_pay.id;
        if v_booking.status = 'pending_payment' then
          update public.bookings set status = 'confirmed', confirmed_at = now()
            where id = v_booking.id;
          v_result := 'paid';
        elsif v_booking.status = 'cancelled' then
          update public.payments set needs_review = true,
            review_reason = 'Payment received for a booking that was cancelled. Refund this payment.'
            where id = v_pay.id;
          v_result := 'paid_review';
        else
          v_result := 'paid';
        end if;
      end if;
    end if;

  elsif p_outcome = 'failed' then
    if v_pay.status in ('successful', 'cancelled') then
      v_result := 'ignored';
    else
      update public.payments set
        status = 'failed',
        failure_reason = left(coalesce(nullif(btrim(p_failure), ''), 'The payment failed'), 500),
        provider_payment_id = coalesce(p_payment_id, provider_payment_id),
        method = coalesce(p_method, method)
        where id = v_pay.id;
      v_result := 'failed';
    end if;

  else
    v_result := 'pending';
  end if;

  select * into v_pay from public.payments p where p.id = v_pay.id;
  select * into v_booking from public.bookings b where b.id = v_pay.booking_id;
  update public.payment_events set outcome = v_result, payment_id = v_pay.id where id = v_event;
  return query select v_result, v_pay.id, v_pay.status, v_booking.id, v_booking.status;
end;
$$;

revoke all on function public.apply_payment_event(
  text, text, text, text, bigint, text, text, text, text, text, text, jsonb
) from public, anon, authenticated;
grant execute on function public.apply_payment_event(
  text, text, text, text, bigint, text, text, text, text, text, text, jsonb
) to service_role;
revoke all on function public.guard_payment_update() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- When a booking is cancelled: close its open attempt, flag a paid one for refund
-- -----------------------------------------------------------------------------
create function public.on_booking_cancelled()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  update public.payments set status = 'cancelled'
    where booking_id = new.id and status = 'pending';
  update public.payments set needs_review = true,
      review_reason = 'The booking was cancelled after it was paid. Decide on a refund.'
    where booking_id = new.id and status = 'successful' and not needs_review;
  return new;
end;
$$;

create trigger bookings_on_cancelled
  after update of status on public.bookings
  for each row
  when (new.status = 'cancelled' and old.status <> 'cancelled')
  execute function public.on_booking_cancelled();

revoke all on function public.on_booking_cancelled() from public, anon, authenticated;
