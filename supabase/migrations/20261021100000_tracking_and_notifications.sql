-- =============================================================================
-- Phase 7: booking tracking (status history) and in-app notifications.
--
--   booking_status_events  one row each time a booking enters a status; the
--                          customer's progress timeline is built from it.
--   notifications          what the customer is told (confirmed, payment failed,
--                          driver assigned/changed/removed, on the way, started,
--                          completed, cancelled).
--
-- Both are written ONLY by triggers on bookings, driver_assignments and payments,
-- so every path that changes a booking (customer, admin API, driver API, payment
-- confirmation, SQL functions) is recorded the same way and nothing can be
-- announced that did not happen. API roles can read their own rows and nothing
-- else; marking read goes through mark_notifications_read (service role only).
-- Push (FCM) is not part of this phase: these rows are what a sender would read.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Status history
-- -----------------------------------------------------------------------------
create table public.booking_status_events (
  id bigint generated always as identity primary key,
  booking_id uuid not null references public.bookings (id) on delete cascade,
  status public.booking_status not null,
  created_at timestamptz not null default now()
);

create index booking_status_events_booking_idx
  on public.booking_status_events (booking_id, id);

-- Bookings that exist already get the history we can reconstruct.
insert into public.booking_status_events (booking_id, status, created_at)
select id, 'pending_payment', created_at from public.bookings;

insert into public.booking_status_events (booking_id, status, created_at)
select id, 'confirmed', confirmed_at from public.bookings where confirmed_at is not null;

insert into public.booking_status_events (booking_id, status, created_at)
select b.id, b.status,
       coalesce(
         case b.status
           when 'completed' then b.completed_at
           when 'cancelled' then b.cancelled_at
         end,
         (select max(da.assigned_at) from public.driver_assignments da where da.booking_id = b.id),
         b.updated_at)
from public.bookings b
where b.status not in ('pending_payment', 'confirmed');

-- -----------------------------------------------------------------------------
-- Notifications
-- -----------------------------------------------------------------------------
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  -- Order of creation (created_at can tie inside one transaction).
  seq bigint generated always as identity,
  user_id uuid not null references public.profiles (id) on delete cascade,
  booking_id uuid references public.bookings (id) on delete cascade,
  kind text not null,
  title text not null,
  body text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz,

  constraint notifications_kind_known check (kind in (
    'booking_confirmed', 'payment_failed', 'driver_assigned', 'driver_changed',
    'driver_removed', 'driver_on_the_way', 'service_started', 'service_completed',
    'booking_cancelled'
  )),
  constraint notifications_text_not_blank check (btrim(title) <> '' and btrim(body) <> '')
);

create index notifications_user_created_idx
  on public.notifications (user_id, seq desc);
create index notifications_user_unread_idx
  on public.notifications (user_id) where read_at is null;
create index notifications_booking_idx on public.notifications (booking_id);

-- -----------------------------------------------------------------------------
-- Writers (triggers). The code and service name are the booking's own snapshot.
-- -----------------------------------------------------------------------------
create function public.notify_customer(
  p_booking public.bookings,
  p_kind text,
  p_title text,
  p_body text
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.notifications (user_id, booking_id, kind, title, body)
  values (p_booking.customer_id, p_booking.id, p_kind, p_title, p_body);
$$;

create function public.booking_label(p_booking public.bookings)
returns text
language sql
immutable
set search_path = ''
as $$
  select 'FF-' || lpad(p_booking.booking_number::text, 6, '0') || ' (' || p_booking.service_name || ')';
$$;

create function public.on_booking_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.booking_status_events (booking_id, status, created_at)
  values (new.id, new.status, new.created_at);
  return null;
end;
$$;

create trigger bookings_record_created
  after insert on public.bookings
  for each row execute function public.on_booking_created();

create function public.on_booking_status_changed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_label text := public.booking_label(new);
begin
  insert into public.booking_status_events (booking_id, status) values (new.id, new.status);

  if new.status = 'confirmed' and old.status = 'pending_payment' then
    perform public.notify_customer(new, 'booking_confirmed', 'Booking confirmed',
      'Payment received for ' || v_label || '. We will assign a driver soon.');
  elsif new.status = 'confirmed' and old.status = 'assigned' then
    perform public.notify_customer(new, 'driver_removed', 'Driver being arranged',
      'The driver for ' || v_label || ' was removed. We are arranging another driver.');
  elsif new.status = 'on_the_way' then
    perform public.notify_customer(new, 'driver_on_the_way', 'Your driver is on the way',
      'Your driver is on the way for ' || v_label || '.');
  elsif new.status = 'in_progress' then
    perform public.notify_customer(new, 'service_started', 'Service started',
      'The service for ' || v_label || ' has started.');
  elsif new.status = 'completed' then
    perform public.notify_customer(new, 'service_completed', 'Service completed',
      'The service for ' || v_label || ' is complete. Thank you for choosing F&F Garage.');
  elsif new.status = 'cancelled' then
    perform public.notify_customer(new, 'booking_cancelled', 'Booking cancelled',
      v_label || ' was cancelled.');
  end if;
  return null;
end;
$$;

create trigger bookings_record_status_change
  after update of status on public.bookings
  for each row when (old.status is distinct from new.status)
  execute function public.on_booking_status_changed();

create function public.on_driver_assigned()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_booking public.bookings;
  v_name text;
  v_earlier boolean;
begin
  select * into v_booking from public.bookings where id = new.booking_id;
  select coalesce(nullif(btrim(full_name), ''), 'A driver') into v_name
    from public.profiles where id = new.driver_id;
  select exists (
    select 1 from public.driver_assignments
    where booking_id = new.booking_id and id <> new.id
  ) into v_earlier;

  if v_earlier then
    perform public.notify_customer(v_booking, 'driver_changed', 'Driver changed',
      v_name || ' will now do ' || public.booking_label(v_booking) || '.');
  else
    perform public.notify_customer(v_booking, 'driver_assigned', 'Driver assigned',
      v_name || ' is assigned to ' || public.booking_label(v_booking) || '.');
  end if;
  return null;
end;
$$;

create trigger driver_assignments_notify
  after insert on public.driver_assignments
  for each row when (new.is_active)
  execute function public.on_driver_assigned();

create function public.on_payment_failed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_booking public.bookings;
begin
  select * into v_booking from public.bookings where id = new.booking_id;
  -- Only while the customer is still waiting to pay: a failed retry on a booking
  -- that is already paid or cancelled is not news.
  if v_booking.status = 'pending_payment' then
    perform public.notify_customer(v_booking, 'payment_failed', 'Payment failed',
      'Your payment for ' || public.booking_label(v_booking)
      || ' did not go through. You can try again from the booking.');
  end if;
  return null;
end;
$$;

create trigger payments_notify_failed_on_insert
  after insert on public.payments
  for each row when (new.status = 'failed')
  execute function public.on_payment_failed();

create trigger payments_notify_failed_on_update
  after update of status on public.payments
  for each row when (new.status = 'failed' and old.status is distinct from 'failed')
  execute function public.on_payment_failed();

-- Marks the user's notifications as read: the given ids, or all when null.
create function public.mark_notifications_read(p_user_id uuid, p_ids uuid[] default null)
returns table (updated integer)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_count integer;
begin
  update public.notifications n
     set read_at = now()
   where n.user_id = p_user_id
     and n.read_at is null
     and (p_ids is null or n.id = any (p_ids));
  get diagnostics v_count = row_count;
  return query select v_count;
end;
$$;

-- -----------------------------------------------------------------------------
-- RLS and grants: read your own, nothing else.
-- -----------------------------------------------------------------------------
alter table public.booking_status_events enable row level security;
alter table public.notifications enable row level security;

revoke all on table public.booking_status_events from anon, authenticated;
revoke all on table public.notifications from anon, authenticated;
grant select on table public.booking_status_events to authenticated;
grant select on table public.notifications to authenticated;
grant all on table public.booking_status_events to service_role;
grant all on table public.notifications to service_role;

create policy booking_status_events_select_own
  on public.booking_status_events for select to authenticated
  using (exists (
    select 1 from public.bookings b
    where b.id = booking_status_events.booking_id and b.customer_id = (select auth.uid())
  ) and (select public.current_user_role()) is not null);

create policy booking_status_events_select_admin
  on public.booking_status_events for select to authenticated
  using ((select public.is_admin()));

create policy notifications_select_own
  on public.notifications for select to authenticated
  using (user_id = (select auth.uid()) and (select public.current_user_role()) is not null);

revoke all on function public.notify_customer(public.bookings, text, text, text)
  from public, anon, authenticated;
revoke all on function public.booking_label(public.bookings) from public, anon, authenticated;
revoke all on function public.on_booking_created() from public, anon, authenticated;
revoke all on function public.on_booking_status_changed() from public, anon, authenticated;
revoke all on function public.on_driver_assigned() from public, anon, authenticated;
revoke all on function public.on_payment_failed() from public, anon, authenticated;
revoke all on function public.mark_notifications_read(uuid, uuid[]) from public, anon, authenticated;
grant execute on function public.mark_notifications_read(uuid, uuid[]) to service_role;
