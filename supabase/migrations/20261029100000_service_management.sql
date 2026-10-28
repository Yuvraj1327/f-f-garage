-- =============================================================================
-- Service management: managed categories, the 3 default services, richer
-- service/package fields, and a Storage bucket for service pictures.
--
-- 1. service_categories: admin-managed (create, rename, reorder, disable; never
--    deleted). Each belongs to one tab of the customer screen (mechanic /
--    package / repair / engine). Services point at one through category_id; the
--    older text columns (category, repair_group, catalog_tab) are kept in step
--    by the backend so nothing that reads them breaks.
-- 2. services: short description, banner and thumbnail pictures, part pictures,
--    the makes/models they support (empty = every vehicle), and system_key for
--    the 3 built-in services (so renaming one never creates a duplicate).
-- 3. service_packages: per-package advance %, repeat interval, labour charge and
--    the parts the package includes.
-- 4. Seeds the 3 default services for bikes and for scooters, and the default
--    categories. Existing rows are adopted by name, never duplicated.
-- 5. Storage bucket "service-images" (public read; only the backend writes).
--
-- SAFE TO RERUN: nothing is dropped, every statement checks first.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Categories
-- -----------------------------------------------------------------------------
create table if not exists public.service_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  tab text not null default 'repair',
  icon_key text,
  display_order integer not null default 0,
  is_active boolean not null default true,
  -- Set on the categories the app relies on as a home for a whole tab.
  system_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.service_categories
  drop constraint if exists service_categories_name_valid,
  drop constraint if exists service_categories_tab_valid,
  drop constraint if exists service_categories_icon_valid,
  drop constraint if exists service_categories_order_valid;
alter table public.service_categories
  add constraint service_categories_name_valid
    check (btrim(name) <> '' and char_length(name) between 2 and 40),
  add constraint service_categories_tab_valid
    check (tab in ('mechanic', 'package', 'repair', 'engine')),
  add constraint service_categories_icon_valid
    check (icon_key is null or char_length(icon_key) <= 30),
  add constraint service_categories_order_valid
    check (display_order between 0 and 10000);

create unique index if not exists service_categories_name_key
  on public.service_categories (lower(btrim(name)));
create unique index if not exists service_categories_system_key_key
  on public.service_categories (system_key) where system_key is not null;

drop trigger if exists service_categories_set_updated_at on public.service_categories;
create trigger service_categories_set_updated_at
  before update on public.service_categories
  for each row execute function public.set_updated_at();

alter table public.service_categories enable row level security;
revoke all on table public.service_categories from anon, authenticated;
grant select, insert, update, delete on table public.service_categories to authenticated;
grant all on table public.service_categories to service_role;

drop policy if exists service_categories_select_active on public.service_categories;
create policy service_categories_select_active
  on public.service_categories for select to authenticated
  using (is_active);
drop policy if exists service_categories_admin_all on public.service_categories;
create policy service_categories_admin_all
  on public.service_categories for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- Default categories (matched by name, so a rename or a rerun adds nothing).
insert into public.service_categories (name, tab, icon_key, display_order, system_key)
select v.name, v.tab, v.icon_key, v.display_order, v.system_key
from (values
  ('Book a Mechanic',     'mechanic', 'mechanic',   10, 'tab_mechanic'),
  ('Service Packages',    'package',  'service',    20, 'tab_package'),
  ('Engine Repair',       'engine',   'engine',     30, 'tab_engine'),
  ('Brakes',              'repair',   'brakes',     40, null),
  ('Battery',             'repair',   'battery',    50, null),
  ('Cables',              'repair',   'cables',     60, null),
  ('Lights',              'repair',   'lights',     70, null),
  ('Filters',             'repair',   'filters',    80, null),
  ('Lubricants & Fluids', 'repair',   'lubricants', 90, null),
  ('Chain',               'repair',   'chain',     100, null),
  ('Other Repairs',       'repair',   'other',     110, 'other_repairs')
) as v (name, tab, icon_key, display_order, system_key)
where not exists (
  select 1 from public.service_categories c
  where lower(btrim(c.name)) = lower(v.name)
     or (v.system_key is not null and c.system_key = v.system_key)
);

-- -----------------------------------------------------------------------------
-- 2. Services
-- -----------------------------------------------------------------------------
alter table public.services
  add column if not exists category_id uuid references public.service_categories (id) on delete restrict,
  add column if not exists system_key text,
  add column if not exists short_description text,
  add column if not exists banner_url text,
  add column if not exists thumbnail_url text,
  add column if not exists part_image_urls text[] not null default '{}',
  add column if not exists supported_makes text[] not null default '{}',
  add column if not exists supported_models text[] not null default '{}';

alter table public.services
  drop constraint if exists services_short_description_valid,
  drop constraint if exists services_banner_url_valid,
  drop constraint if exists services_thumbnail_url_valid,
  drop constraint if exists services_part_images_valid,
  drop constraint if exists services_supported_valid,
  drop constraint if exists services_system_key_valid;
alter table public.services
  add constraint services_short_description_valid
    check (short_description is null
           or (btrim(short_description) <> '' and char_length(short_description) <= 140)),
  add constraint services_banner_url_valid
    check (banner_url is null or (banner_url ~ '^https://' and char_length(banner_url) <= 500)),
  add constraint services_thumbnail_url_valid
    check (thumbnail_url is null or (thumbnail_url ~ '^https://' and char_length(thumbnail_url) <= 500)),
  add constraint services_part_images_valid
    check (cardinality(part_image_urls) <= 8),
  add constraint services_supported_valid
    check (cardinality(supported_makes) <= 60 and cardinality(supported_models) <= 200),
  add constraint services_system_key_valid
    check (system_key is null or system_key in
           ('book_mechanic', 'check_vehicle', 'mechanic_consultation'));

create unique index if not exists services_system_key_vehicle_key
  on public.services (system_key, vehicle_type) where system_key is not null;
create index if not exists services_category_id_idx on public.services (category_id);

-- The old single picture becomes the thumbnail.
update public.services set thumbnail_url = image_url
where thumbnail_url is null and image_url is not null;

-- -----------------------------------------------------------------------------
-- 3. Packages
-- -----------------------------------------------------------------------------
alter table public.service_packages
  add column if not exists advance_percent numeric(5, 2),
  add column if not exists repeat_interval_days integer,
  add column if not exists labour_charge numeric(10, 2),
  add column if not exists included_parts text[] not null default '{}';

alter table public.service_packages
  drop constraint if exists service_packages_advance_valid,
  drop constraint if exists service_packages_repeat_valid,
  drop constraint if exists service_packages_labour_valid,
  drop constraint if exists service_packages_parts_count_valid;
alter table public.service_packages
  add constraint service_packages_advance_valid
    check (advance_percent is null or (advance_percent >= 1 and advance_percent <= 100)),
  add constraint service_packages_repeat_valid
    check (repeat_interval_days is null or repeat_interval_days between 1 and 3650),
  add constraint service_packages_labour_valid
    check (labour_charge is null or (labour_charge >= 0 and labour_charge <= price)),
  add constraint service_packages_parts_count_valid
    check (cardinality(included_parts) <= 30);

-- -----------------------------------------------------------------------------
-- 4. The 3 default services, for bikes and for scooters
-- -----------------------------------------------------------------------------
-- Services already named like a default (any case) adopt its system_key instead
-- of being duplicated.
update public.services s
set system_key = d.system_key
from (values
  ('book_mechanic',         'book a mechanic'),
  ('check_vehicle',         'check my vehicle'),
  ('mechanic_consultation', 'mechanic consultation (via call)')
) as d (system_key, lowered_name)
where s.system_key is null
  and lower(btrim(s.name)) = d.lowered_name
  and not exists (
    select 1 from public.services o
    where o.system_key = d.system_key and o.vehicle_type = s.vehicle_type
  );

do $$
declare
  v_type public.vehicle_type;
  v_def record;
  v_category uuid;
  v_service uuid;
begin
  select id into v_category from public.service_categories where system_key = 'tab_mechanic';
  for v_type in select unnest(enum_range(null::public.vehicle_type)) loop
    for v_def in
      select * from (values
        ('book_mechanic', 'Book a Mechanic',
         'Not sure what''s wrong with your vehicle? Book an expert for a professional diagnosis. '
         || 'Our technician will identify the root cause, provide a transparent repair estimate, '
         || 'and get you back on the road with total peace of mind.',
         'Book an expert for a professional diagnosis and repair estimate.',
         299::numeric, 30, 7, 'Trending', 10,
         array['Professional diagnosis', 'Root cause identification', 'Transparent repair estimate']),
        ('check_vehicle', 'Check My Vehicle',
         'Book this service to have an expert mechanic visit your location and thoroughly '
         || 'inspect your vehicle.',
         'A complete vehicle inspection by an expert mechanic at your doorstep.',
         299::numeric, 60, null::integer, null::text, 20,
         array['Complete vehicle inspection', 'Brakes, tyres and lights check',
               'Inspection summary and advice']),
        ('mechanic_consultation', 'Mechanic Consultation (Via Call)',
         'Is your vehicle behaving strangely? Connect with a senior technician for remote '
         || 'guidance and advice.',
         'Talk to a senior technician on a call.',
         29::numeric, 15, null::integer, null::text, 30,
         array['Call with a senior technician', 'Troubleshooting advice'])
      ) as t (system_key, name, description, short_description, price, minutes, warranty,
              badge, display_order, inclusions)
    loop
      if exists (
        select 1 from public.services
        where vehicle_type = v_type
          and (system_key = v_def.system_key or lower(btrim(name)) = lower(v_def.name))
      ) then
        continue;
      end if;

      insert into public.services (
        name, vehicle_type, category, description, short_description, catalog_tab,
        badge, display_order, system_key, category_id
      ) values (
        v_def.name, v_type, 'Book a Mechanic', v_def.description, v_def.short_description,
        'mechanic', v_def.badge, v_def.display_order, v_def.system_key, v_category
      ) returning id into v_service;

      insert into public.service_packages (
        service_id, name, description, price, inclusions, estimated_duration_minutes,
        warranty_days, display_order
      ) values (
        v_service, 'Standard', null, v_def.price, v_def.inclusions, v_def.minutes,
        v_def.warranty, 0
      );
    end loop;
  end loop;
end
$$;

-- Existing services get a category: a name match first (repair group, else the
-- old category text), then the home category of their tab.
update public.services s
set category_id = c.id
from public.service_categories c
where s.category_id is null
  and c.tab = s.catalog_tab
  and lower(btrim(c.name)) = lower(btrim(coalesce(s.repair_group, s.category)));

update public.services s
set category_id = c.id
from public.service_categories c
where s.category_id is null
  and c.system_key = case s.catalog_tab
    when 'mechanic' then 'tab_mechanic'
    when 'package' then 'tab_package'
    when 'engine' then 'tab_engine'
    else 'other_repairs'
  end;

-- -----------------------------------------------------------------------------
-- 5. Storage bucket for service pictures
-- -----------------------------------------------------------------------------
-- Public read (the app shows the pictures by link); no policy lets a signed-in
-- user write, so only the backend (service role) can upload or delete. The
-- table is only there on Supabase, hence the check.
do $$
begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('service-images', 'service-images', true, 5242880,
            array['image/jpeg', 'image/png', 'image/webp'])
    on conflict (id) do nothing;
  end if;
end
$$;
