-- =============================================================================
-- Saved vehicles (two-wheelers only) and the vehicle on a booking.
--
-- customer_vehicles: each customer's own list. Only the backend (service role)
-- reads and writes it; ownership is checked in the API. A customer cannot save
-- the same registration twice (stored upper-case, no spaces).
-- bookings gain four optional snapshot columns: what was booked stays readable
-- even after the customer edits or deletes the saved vehicle.
-- =============================================================================
create table public.customer_vehicles (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles (id) on delete cascade,
  vehicle_type public.vehicle_type not null,
  registration_number text not null check (registration_number ~ '^[A-Z0-9]{6,12}$'),
  make text not null check (btrim(make) <> '' and char_length(make) <= 40),
  model text not null check (btrim(model) <> '' and char_length(model) <= 40),
  nickname text check (nickname is null or (btrim(nickname) <> '' and char_length(nickname) <= 30)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index customer_vehicles_registration_key
  on public.customer_vehicles (customer_id, registration_number);
create index customer_vehicles_customer_idx
  on public.customer_vehicles (customer_id, created_at);

create trigger customer_vehicles_set_updated_at
  before update on public.customer_vehicles
  for each row execute function public.set_updated_at();

alter table public.customer_vehicles enable row level security;
revoke all on table public.customer_vehicles from anon, authenticated;
grant all on table public.customer_vehicles to service_role;

alter table public.bookings
  add column vehicle_registration text,
  add column vehicle_make text,
  add column vehicle_model text,
  add column vehicle_nickname text;

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
begin
  if v_request is not null then
    select * into v_row from public.bookings
    where customer_id = v_customer and client_request_id = v_request;
    if found then
      return next v_row;
      return;
    end if;
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
    vehicle_registration, vehicle_make, vehicle_model, vehicle_nickname
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
    nullif(p_booking ->> 'vehicle_nickname', '')
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

  return next v_row;
  return;
end;
$$;

-- Backend only: not reachable through the public REST API.

revoke all on function public.create_booking(jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.create_booking(jsonb, jsonb) to service_role;
