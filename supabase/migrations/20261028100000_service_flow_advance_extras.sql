-- =============================================================================
-- Two-wheeler service flow: catalogue tabs, coupons, 20% advance payment,
-- extra charges that need the customer's approval, final bill and refund records.
--
-- 1. Catalogue: services get a tab (mechanic / package / repair / engine), an
--    optional repair group (Brakes, Cables...), a picture URL and a badge.
--    Packages get warranty, exclusions, a parts policy and an "original price".
-- 2. Coupons: coupons + coupon_redemptions. The backend computes the discount;
--    the database enforces the limits and records the redemption atomically.
-- 3. Bookings: coupon_code, discount_amount, advance_percent, advance_amount.
--    total_amount (estimated total) = package + chosen add-ons - discount.
-- 4. Payments: `kind` is 'advance' (collected when booking) or 'balance'
--    (collected after the service). One successful payment per booking AND kind.
-- 5. booking_extra_requests: extra parts/repairs found during the visit. They are
--    only billed once the customer approves; a driver cannot finish the job while
--    one is still waiting for an answer.
-- 6. payment_refunds: refunds are decided and made by an admin (outside the app,
--    in the payment gateway dashboard) and RECORDED here. Nothing is refunded
--    automatically and no refund rule is built in.
-- 7. garage_settings.refund_policy: the policy text the admin has configured.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Catalogue
-- -----------------------------------------------------------------------------
alter table public.services
  add column catalog_tab text not null default 'package',
  add column repair_group text,
  add column image_url text,
  add column badge text;

alter table public.services
  add constraint services_catalog_tab_valid
    check (catalog_tab in ('mechanic', 'package', 'repair', 'engine')),
  add constraint services_repair_group_valid
    check (repair_group is null or (btrim(repair_group) <> '' and char_length(repair_group) <= 30)),
  add constraint services_image_url_valid
    check (image_url is null or (image_url ~ '^https://' and char_length(image_url) <= 500)),
  add constraint services_badge_valid
    check (badge is null or (btrim(badge) <> '' and char_length(badge) <= 24));

create index services_tab_idx on public.services (vehicle_type, catalog_tab, display_order)
  where is_active;

alter table public.service_packages
  add column original_price numeric(10, 2),
  add column warranty_days integer,
  add column exclusions text[] not null default '{}',
  add column parts_policy text not null default 'service_only',
  add column parts_note text;

alter table public.service_packages
  add constraint service_packages_original_price_valid
    check (original_price is null or original_price >= price),
  add constraint service_packages_warranty_valid
    check (warranty_days is null or warranty_days between 1 and 3650),
  add constraint service_packages_parts_policy_valid
    check (parts_policy in ('service_only', 'parts_included', 'parts_extra')),
  add constraint service_packages_parts_note_valid
    check (parts_note is null or (btrim(parts_note) <> '' and char_length(parts_note) <= 300));

-- -----------------------------------------------------------------------------
-- 2. Coupons (backend only)
-- -----------------------------------------------------------------------------
create table public.coupons (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  description text,
  discount_type text not null,
  discount_value numeric(10, 2) not null,
  -- Cap for a percentage coupon (NULL = no cap).
  max_discount numeric(10, 2),
  min_order_amount numeric(10, 2) not null default 0,
  starts_at timestamptz,
  ends_at timestamptz,
  -- Total uses across all customers (NULL = unlimited), and uses per customer.
  usage_limit integer,
  per_customer_limit integer not null default 1,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint coupons_code_format check (code ~ '^[A-Z0-9_-]{3,20}$'),
  constraint coupons_description_length check (description is null or char_length(description) <= 200),
  constraint coupons_type_valid check (discount_type in ('percent', 'flat')),
  constraint coupons_value_positive check (discount_value > 0),
  constraint coupons_percent_range check (discount_type <> 'percent' or discount_value <= 100),
  constraint coupons_max_discount_positive check (max_discount is null or max_discount > 0),
  constraint coupons_min_order_non_negative check (min_order_amount >= 0),
  constraint coupons_window_order check (starts_at is null or ends_at is null or ends_at > starts_at),
  constraint coupons_usage_limit_positive check (usage_limit is null or usage_limit > 0),
  constraint coupons_per_customer_positive check (per_customer_limit > 0)
);

create unique index coupons_code_key on public.coupons (code);

create trigger coupons_set_updated_at
  before update on public.coupons
  for each row execute function public.set_updated_at();

alter table public.coupons enable row level security;
revoke all on table public.coupons from anon, authenticated;
grant all on table public.coupons to service_role;

-- -----------------------------------------------------------------------------
-- 3. Bookings: discount, advance and the new estimated total
-- -----------------------------------------------------------------------------
alter table public.bookings
  add column coupon_code text,
  add column discount_amount numeric(10, 2) not null default 0,
  add column advance_percent numeric(5, 2) not null default 20,
  -- 0 on older bookings, which were paid in full up front.
  add column advance_amount numeric(10, 2) not null default 0;

alter table public.bookings drop column total_amount;
alter table public.bookings
  add column total_amount numeric(10, 2)
    generated always as (package_price + extra_charges_total - discount_amount) stored;

alter table public.bookings
  add constraint bookings_discount_valid
    check (discount_amount >= 0 and discount_amount <= package_price + extra_charges_total),
  add constraint bookings_discount_has_coupon
    check (discount_amount = 0 or coupon_code is not null),
  add constraint bookings_advance_percent_range
    check (advance_percent >= 0 and advance_percent <= 100),
  add constraint bookings_advance_valid
    check (advance_amount >= 0
           and advance_amount <= package_price + extra_charges_total - discount_amount);

create table public.coupon_redemptions (
  id uuid primary key default gen_random_uuid(),
  coupon_id uuid not null references public.coupons (id) on delete restrict,
  booking_id uuid not null references public.bookings (id) on delete cascade,
  customer_id uuid not null references public.profiles (id) on delete cascade,
  amount numeric(10, 2) not null check (amount > 0),
  created_at timestamptz not null default now(),

  constraint coupon_redemptions_booking_key unique (booking_id)
);

create index coupon_redemptions_coupon_idx on public.coupon_redemptions (coupon_id);
create index coupon_redemptions_customer_idx on public.coupon_redemptions (customer_id, coupon_id);

alter table public.coupon_redemptions enable row level security;
revoke all on table public.coupon_redemptions from anon, authenticated;
grant all on table public.coupon_redemptions to service_role;

-- The price, discount and advance of a booking never change after creation.
create or replace function public.guard_booking_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status in ('completed', 'cancelled') then
    raise exception 'A % booking cannot be changed', old.status using errcode = '23514';
  end if;

  if not public.booking_status_transition_allowed(old.status, new.status) then
    raise exception 'A booking cannot move from % to %', old.status, new.status
      using errcode = '23514';
  end if;

  -- What was booked and what it cost never changes after creation.
  if new.booking_number is distinct from old.booking_number
     or new.customer_id is distinct from old.customer_id
     or new.service_id is distinct from old.service_id
     or new.package_id is distinct from old.package_id
     or new.vehicle_type is distinct from old.vehicle_type
     or new.service_name is distinct from old.service_name
     or new.package_name is distinct from old.package_name
     or new.package_inclusions is distinct from old.package_inclusions
     or new.estimated_duration_minutes is distinct from old.estimated_duration_minutes
     or new.package_price is distinct from old.package_price
     or new.extra_charges_total is distinct from old.extra_charges_total
     or new.discount_amount is distinct from old.discount_amount
     or new.coupon_code is distinct from old.coupon_code
     or new.advance_percent is distinct from old.advance_percent
     or new.advance_amount is distinct from old.advance_amount
     or new.customer_name is distinct from old.customer_name
     or new.customer_phone is distinct from old.customer_phone
     or new.client_request_id is distinct from old.client_request_id
     or new.created_at is distinct from old.created_at then
    raise exception 'The booked service, price and customer cannot be changed'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

-- create_booking now also stores the discount and advance, and (atomically, with a
-- lock on the coupon) enforces the coupon's limits and records the redemption.
-- Marker 'coupon_unavailable' (SQLSTATE 23P01) becomes a 409 in the API.
create or replace function public.create_booking(p_booking jsonb, p_charges jsonb default '[]'::jsonb)
returns setof public.bookings
language plpgsql
set search_path = ''
as $$
declare
  v_row public.bookings;
  v_extra numeric(10, 2);
  v_customer uuid := (p_booking ->> 'customer_id')::uuid;
  v_request uuid := nullif(p_booking ->> 'client_request_id', '')::uuid;
  v_code text := nullif(p_booking ->> 'coupon_code', '');
  v_discount numeric(10, 2) := coalesce(nullif(p_booking ->> 'discount_amount', '')::numeric, 0);
  v_coupon public.coupons;
  v_used integer;
  v_used_by_customer integer;
begin
  if v_request is not null then
    select * into v_row from public.bookings
    where customer_id = v_customer and client_request_id = v_request;
    if found then
      return next v_row;
      return;
    end if;
  end if;

  if v_code is not null then
    select * into v_coupon from public.coupons where code = v_code for update;
    if not found
       or not v_coupon.is_active
       or (v_coupon.starts_at is not null and now() < v_coupon.starts_at)
       or (v_coupon.ends_at is not null and now() > v_coupon.ends_at) then
      raise exception 'coupon_unavailable: this coupon is not valid right now'
        using errcode = '23P01';
    end if;
    select count(*) into v_used
      from public.coupon_redemptions r join public.bookings b on b.id = r.booking_id
      where r.coupon_id = v_coupon.id and b.status <> 'cancelled';
    select count(*) into v_used_by_customer
      from public.coupon_redemptions r join public.bookings b on b.id = r.booking_id
      where r.coupon_id = v_coupon.id and r.customer_id = v_customer and b.status <> 'cancelled';
    if (v_coupon.usage_limit is not null and v_used >= v_coupon.usage_limit)
       or v_used_by_customer >= v_coupon.per_customer_limit then
      raise exception 'coupon_unavailable: this coupon has been used up'
        using errcode = '23P01';
    end if;
  elsif v_discount <> 0 then
    raise exception 'A discount needs a coupon' using errcode = '23514';
  end if;

  select coalesce(sum((c ->> 'amount')::numeric)
                  filter (where (c ->> 'included_in_total')::boolean), 0)
  into v_extra
  from jsonb_array_elements(p_charges) c;

  insert into public.bookings (
    customer_id, service_id, package_id, vehicle_type, status,
    customer_name, customer_phone,
    address_line, landmark, city, state, pincode, service_area_id, latitude, longitude,
    scheduled_date, slot_start, slot_end,
    service_name, package_name, package_inclusions, estimated_duration_minutes,
    package_price, extra_charges_total, customer_notes, client_request_id,
    vehicle_registration, vehicle_make, vehicle_model, vehicle_nickname,
    coupon_code, discount_amount, advance_percent, advance_amount
  ) values (
    v_customer,
    (p_booking ->> 'service_id')::uuid,
    (p_booking ->> 'package_id')::uuid,
    (p_booking ->> 'vehicle_type')::public.vehicle_type,
    'pending_payment',
    p_booking ->> 'customer_name',
    p_booking ->> 'customer_phone',
    p_booking ->> 'address_line',
    nullif(p_booking ->> 'landmark', ''),
    p_booking ->> 'city',
    nullif(p_booking ->> 'state', ''),
    p_booking ->> 'pincode',
    nullif(p_booking ->> 'service_area_id', '')::uuid,
    nullif(p_booking ->> 'latitude', '')::numeric,
    nullif(p_booking ->> 'longitude', '')::numeric,
    (p_booking ->> 'scheduled_date')::date,
    (p_booking ->> 'slot_start')::time,
    (p_booking ->> 'slot_end')::time,
    p_booking ->> 'service_name',
    p_booking ->> 'package_name',
    coalesce(array(select jsonb_array_elements_text(p_booking -> 'package_inclusions')), '{}'),
    nullif(p_booking ->> 'estimated_duration_minutes', '')::integer,
    (p_booking ->> 'package_price')::numeric,
    v_extra,
    nullif(p_booking ->> 'customer_notes', ''),
    v_request,
    nullif(p_booking ->> 'vehicle_registration', ''),
    nullif(p_booking ->> 'vehicle_make', ''),
    nullif(p_booking ->> 'vehicle_model', ''),
    nullif(p_booking ->> 'vehicle_nickname', ''),
    v_code,
    v_discount,
    coalesce(nullif(p_booking ->> 'advance_percent', '')::numeric, 20),
    coalesce(nullif(p_booking ->> 'advance_amount', '')::numeric, 0)
  ) returning * into v_row;

  insert into public.booking_extra_charges
    (booking_id, extra_charge_id, charge_type, name, amount, included_in_total)
  select v_row.id,
         nullif(c ->> 'extra_charge_id', '')::uuid,
         (c ->> 'charge_type')::public.extra_charge_type,
         c ->> 'name',
         nullif(c ->> 'amount', '')::numeric,
         coalesce((c ->> 'included_in_total')::boolean, false)
  from jsonb_array_elements(p_charges) c;

  if v_code is not null then
    insert into public.coupon_redemptions (coupon_id, booking_id, customer_id, amount)
    values (v_coupon.id, v_row.id, v_customer, v_discount);
  end if;

  return next v_row;
  return;
end;
$$;

revoke all on function public.create_booking(jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.create_booking(jsonb, jsonb) to service_role;
revoke all on function public.guard_booking_update() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 4. Payments: advance and balance
-- -----------------------------------------------------------------------------
alter table public.payments
  add column kind text not null default 'advance';

alter table public.payments
  add constraint payments_kind_valid check (kind in ('advance', 'balance'));

drop index public.payments_one_successful_per_booking;
create unique index payments_one_successful_per_booking_kind
  on public.payments (booking_id, kind)
  where status = 'successful';

grant select (kind) on public.payments to authenticated;

create or replace function public.guard_payment_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.booking_id is distinct from old.booking_id
     or new.customer_id is distinct from old.customer_id
     or new.provider is distinct from old.provider
     or new.kind is distinct from old.kind
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

revoke all on function public.guard_payment_update() from public, anon, authenticated;

-- Same as before, except that "already paid" means "this KIND is already paid", and
-- only an ADVANCE payment confirms a booking (a balance payment settles a bill).
create or replace function public.apply_payment_event(
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
        where p.booking_id = v_pay.booking_id and p.kind = v_pay.kind
          and p.status = 'successful' and p.id <> v_pay.id
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
        if v_pay.kind = 'advance' and v_booking.status = 'pending_payment' then
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

-- -----------------------------------------------------------------------------
-- 5. Extra charges found during the visit (customer approval required)
-- -----------------------------------------------------------------------------
create table public.booking_extra_requests (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings (id) on delete cascade,
  charge_type public.extra_charge_type not null default 'other',
  name text not null,
  description text,
  amount numeric(10, 2) not null,
  status text not null default 'proposed',
  requested_by uuid references public.profiles (id) on delete set null,
  requested_by_role public.user_role not null,
  decided_at timestamptz,
  created_at timestamptz not null default now(),

  constraint booking_extra_requests_name_valid
    check (btrim(name) <> '' and char_length(name) <= 120),
  constraint booking_extra_requests_description_valid
    check (description is null or char_length(description) <= 500),
  constraint booking_extra_requests_amount_valid check (amount > 0 and amount <= 500000),
  constraint booking_extra_requests_status_valid
    check (status in ('proposed', 'approved', 'declined', 'withdrawn')),
  constraint booking_extra_requests_role_valid
    check (requested_by_role in ('driver', 'admin')),
  constraint booking_extra_requests_decided_matches_status
    check ((status in ('approved', 'declined')) = (decided_at is not null))
);

create index booking_extra_requests_booking_idx
  on public.booking_extra_requests (booking_id, created_at);
create index booking_extra_requests_open_idx
  on public.booking_extra_requests (booking_id) where status = 'proposed';

-- A request can only be raised, and answered, while the service is in progress.
create function public.guard_extra_request_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_status public.booking_status;
begin
  select status into v_status from public.bookings where id = new.booking_id;
  if v_status is distinct from 'in_progress' then
    raise exception 'Extra charges can only be requested while the service is in progress'
      using errcode = '23514';
  end if;
  if new.status <> 'proposed' or new.decided_at is not null then
    raise exception 'A new extra charge request must be waiting for approval'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger booking_extra_requests_guard_insert
  before insert on public.booking_extra_requests
  for each row execute function public.guard_extra_request_insert();

create function public.guard_extra_request_update()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_status public.booking_status;
begin
  if new.booking_id is distinct from old.booking_id
     or new.charge_type is distinct from old.charge_type
     or new.name is distinct from old.name
     or new.description is distinct from old.description
     or new.amount is distinct from old.amount
     or new.requested_by_role is distinct from old.requested_by_role
     or new.created_at is distinct from old.created_at then
    raise exception 'An extra charge request cannot be edited' using errcode = '23514';
  end if;
  if new.status = old.status then
    return new;
  end if;
  if old.status <> 'proposed' then
    raise exception 'This extra charge request has already been answered' using errcode = '23514';
  end if;
  if new.status in ('approved', 'declined') then
    select status into v_status from public.bookings where id = new.booking_id;
    if v_status is distinct from 'in_progress' then
      raise exception 'Extra charges can only be answered while the service is in progress'
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

create trigger booking_extra_requests_guard_update
  before update on public.booking_extra_requests
  for each row execute function public.guard_extra_request_update();

-- New notification kinds.
alter table public.notifications drop constraint notifications_kind_known;
alter table public.notifications add constraint notifications_kind_known check (kind in (
  'booking_confirmed', 'payment_failed', 'driver_assigned', 'driver_changed',
  'driver_removed', 'driver_on_the_way', 'service_started', 'service_completed',
  'booking_cancelled', 'extra_charge_requested', 'refund_recorded'
));

create function public.on_extra_request_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_booking public.bookings;
begin
  select * into v_booking from public.bookings where id = new.booking_id;
  perform public.notify_customer(v_booking, 'extra_charge_requested', 'Approval needed',
    'Extra work was found for ' || public.booking_label(v_booking) || ': ' || new.name
    || ' (Rs ' || to_char(new.amount, 'FM999999990.00') || '). Open the booking to approve or decline.');
  return null;
end;
$$;

create trigger booking_extra_requests_notify
  after insert on public.booking_extra_requests
  for each row execute function public.on_extra_request_created();

-- A cancelled booking withdraws any request still waiting for an answer.
create or replace function public.on_booking_cancelled()
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
  update public.booking_extra_requests set status = 'withdrawn'
    where booking_id = new.id and status = 'proposed';
  return new;
end;
$$;

revoke all on function public.on_booking_cancelled() from public, anon, authenticated;
revoke all on function public.guard_extra_request_insert() from public, anon, authenticated;
revoke all on function public.guard_extra_request_update() from public, anon, authenticated;
revoke all on function public.on_extra_request_created() from public, anon, authenticated;

alter table public.booking_extra_requests enable row level security;
revoke all on table public.booking_extra_requests from anon, authenticated;
grant select on table public.booking_extra_requests to authenticated;
grant all on table public.booking_extra_requests to service_role;

-- Whoever may see the booking may see its requests (same rule as the charge snapshot).
create policy booking_extra_requests_select_via_booking
  on public.booking_extra_requests for select to authenticated
  using (exists (select 1 from public.bookings b where b.id = booking_extra_requests.booking_id));

-- The driver cannot finish a job while the customer has not answered a request.
create or replace function public.driver_update_status(
  p_booking_id uuid,
  p_driver_id uuid,
  p_status public.booking_status
)
returns table (result text, booking_status public.booking_status)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_booking public.bookings;
  v_active boolean;
begin
  select * into v_booking from public.bookings where id = p_booking_id for update;
  if not found then
    return query select 'booking_not_found'::text, null::public.booking_status;
    return;
  end if;

  if not exists (
    select 1 from public.driver_assignments da
    where da.booking_id = p_booking_id and da.driver_id = p_driver_id and da.is_active
  ) then
    return query select 'not_assigned'::text, null::public.booking_status;
    return;
  end if;

  select is_active into v_active from public.profiles
    where id = p_driver_id and role = 'driver';
  if v_active is not true then
    return query select 'driver_inactive'::text, v_booking.status;
    return;
  end if;

  if v_booking.status = p_status then
    return query select 'unchanged'::text, v_booking.status;
    return;
  end if;
  if v_booking.status = 'cancelled' then
    return query select 'booking_cancelled'::text, v_booking.status;
    return;
  end if;

  if not (
       (v_booking.status = 'assigned'    and p_status = 'on_the_way')
    or (v_booking.status = 'on_the_way'  and p_status = 'in_progress')
    or (v_booking.status = 'in_progress' and p_status = 'completed')
  ) then
    return query select 'invalid_transition'::text, v_booking.status;
    return;
  end if;

  if p_status = 'completed' and exists (
    select 1 from public.booking_extra_requests r
    where r.booking_id = p_booking_id and r.status = 'proposed'
  ) then
    return query select 'extras_pending'::text, v_booking.status;
    return;
  end if;

  update public.bookings
    set status = p_status,
        completed_at = case when p_status = 'completed' then now() else completed_at end
    where id = p_booking_id;
  return query select 'updated'::text, p_status;
end;
$$;

-- -----------------------------------------------------------------------------
-- 6. Refund records (an admin refunds in the gateway dashboard, then records it)
-- -----------------------------------------------------------------------------
create table public.payment_refunds (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments (id) on delete restrict,
  booking_id uuid not null references public.bookings (id) on delete restrict,
  amount numeric(10, 2) not null check (amount > 0),
  note text,
  recorded_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),

  constraint payment_refunds_note_valid check (note is null or char_length(note) <= 300)
);

create index payment_refunds_payment_idx on public.payment_refunds (payment_id);
create index payment_refunds_booking_idx on public.payment_refunds (booking_id);

alter table public.payment_refunds enable row level security;
revoke all on table public.payment_refunds from anon, authenticated;
grant all on table public.payment_refunds to service_role;

-- Records a refund the admin has already made, never more than the payment was.
-- result: recorded | payment_not_found | payment_not_successful | exceeds_payment
create function public.record_payment_refund(
  p_payment_id uuid,
  p_amount numeric,
  p_note text,
  p_admin uuid
)
returns table (result text, refund_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pay public.payments;
  v_booking public.bookings;
  v_done numeric;
  v_id uuid;
begin
  select * into v_pay from public.payments where id = p_payment_id for update;
  if not found then
    return query select 'payment_not_found'::text, null::uuid;
    return;
  end if;
  if v_pay.status <> 'successful' then
    return query select 'payment_not_successful'::text, null::uuid;
    return;
  end if;
  select coalesce(sum(amount), 0) into v_done
    from public.payment_refunds where payment_id = p_payment_id;
  if p_amount <= 0 or v_done + p_amount > v_pay.amount then
    return query select 'exceeds_payment'::text, null::uuid;
    return;
  end if;

  insert into public.payment_refunds (payment_id, booking_id, amount, note, recorded_by)
  values (p_payment_id, v_pay.booking_id, p_amount, nullif(btrim(p_note), ''), p_admin)
  returning id into v_id;

  -- The admin has dealt with it: clear the "needs a decision" flag.
  update public.payments set needs_review = false, review_reason = null
    where id = p_payment_id and needs_review;

  select * into v_booking from public.bookings where id = v_pay.booking_id;
  perform public.notify_customer(v_booking, 'refund_recorded', 'Refund processed',
    'A refund of Rs ' || to_char(p_amount, 'FM999999990.00') || ' was recorded for '
    || public.booking_label(v_booking) || '.');

  return query select 'recorded'::text, v_id;
end;
$$;

revoke all on function public.record_payment_refund(uuid, numeric, text, uuid)
  from public, anon, authenticated;
grant execute on function public.record_payment_refund(uuid, numeric, text, uuid) to service_role;

-- -----------------------------------------------------------------------------
-- 7. The refund policy text the admin configured (empty = none configured)
-- -----------------------------------------------------------------------------
alter table public.garage_settings
  add column refund_policy text not null default ''
    check (char_length(refund_policy) <= 1000);
