-- =============================================================================
-- Garage business details, editable by an admin in the app.
--
-- One row (id is always true). While there is no row, the API keeps using the
-- GARAGE_* environment variables, so existing installs behave as before. Once
-- an admin saves the details, the row wins. Only the backend (service role)
-- reads and writes it; the app never touches the table directly.
-- =============================================================================
create table public.garage_settings (
  id boolean primary key default true check (id),
  name text not null default 'F&F Two Wheeler Garage'
    check (btrim(name) <> '' and char_length(name) <= 120),
  phone text not null default '' check (char_length(phone) <= 20),
  whatsapp text not null default '' check (char_length(whatsapp) <= 20),
  email text not null default '' check (char_length(email) <= 254),
  address text not null default '' check (char_length(address) <= 300),
  hours text not null default '' check (char_length(hours) <= 120),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id) on delete set null
);

alter table public.garage_settings enable row level security;
revoke all on table public.garage_settings from anon, authenticated;
grant all on table public.garage_settings to service_role;
