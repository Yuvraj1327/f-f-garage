-- =============================================================================
-- Migration 5 of 5: payments
-- =============================================================================
-- One row per payment ATTEMPT. A booking can have several failed attempts but
-- at most one successful payment.
--
-- Written only by the backend (service_role) after it verifies the result with
-- the gateway server-side. The gateway is not chosen yet, so `provider` is free
-- text and the provider reference columns are generic.
--
-- Duplicate-processing protection lives in the database:
--   * (provider, provider_order_id)   unique  - one row per gateway order
--   * (provider, provider_payment_id) unique  - one row per gateway transaction,
--                                               so a replayed webhook cannot
--                                               create a second success
--   * one 'successful' payment per booking (partial unique index)
--   * (customer_id, idempotency_key)  unique  - safe client retries on initiate
-- =============================================================================

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null,
  customer_id uuid not null,
  provider text not null,
  provider_order_id text,
  provider_payment_id text,
  idempotency_key text,
  amount numeric(10, 2) not null,
  currency text not null default 'INR',
  status public.payment_status not null default 'pending',
  failure_reason text,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- customer_id must be the booking's customer.
  constraint payments_booking_customer_fk
    foreign key (booking_id, customer_id)
    references public.bookings (id, customer_id)
    on delete restrict,

  constraint payments_provider_not_blank check (btrim(provider) <> ''),
  constraint payments_amount_positive check (amount > 0),
  constraint payments_currency_format check (currency ~ '^[A-Z]{3}$'),
  -- A success must carry the gateway transaction reference and a timestamp.
  constraint payments_successful_has_reference check (
    status <> 'successful' or (paid_at is not null and provider_payment_id is not null)
  ),
  constraint payments_paid_at_only_when_successful check (
    status = 'successful' or paid_at is null
  )
);

comment on table public.payments is
  'Payment attempts for bookings. Written by the backend after server-side gateway verification.';

create unique index payments_provider_order_key
  on public.payments (provider, provider_order_id)
  where provider_order_id is not null;
create unique index payments_provider_payment_key
  on public.payments (provider, provider_payment_id)
  where provider_payment_id is not null;
create unique index payments_customer_idempotency_key
  on public.payments (customer_id, idempotency_key)
  where idempotency_key is not null;
create unique index payments_one_successful_per_booking
  on public.payments (booking_id)
  where status = 'successful';

create index payments_booking_idx on public.payments (booking_id);
create index payments_customer_created_idx on public.payments (customer_id, created_at desc);
create index payments_status_created_idx on public.payments (status, created_at desc);

create trigger payments_set_updated_at
  before update on public.payments
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- RLS + grants: SELECT only. Drivers have no access to payments at all.
-- -----------------------------------------------------------------------------
alter table public.payments enable row level security;

revoke all on table public.payments from anon, authenticated;
grant select on table public.payments to authenticated;
grant all on table public.payments to service_role;

create policy payments_select_own
  on public.payments for select to authenticated
  using (
    customer_id = (select auth.uid())
    and (select public.current_user_role()) is not null
  );

create policy payments_select_admin
  on public.payments for select to authenticated
  using ((select public.is_admin()));
