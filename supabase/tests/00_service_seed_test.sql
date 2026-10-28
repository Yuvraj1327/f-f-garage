-- =============================================================================
-- TEST-ONLY. The default services and categories seeded by the migrations. Runs
-- first, on the freshly migrated database (file 01 then clears the catalogue).
-- =============================================================================
\set ON_ERROR_STOP on
\set QUIET on

do $$
declare
  n bigint;
begin
  select count(*) into n from public.services where system_key is not null;
  if n <> 6 then raise exception 'FAIL: expected 3 default services x 2 vehicle types, got %', n; end if;
  raise notice 'PASS: the 3 default services exist for bikes and for scooters';

  select count(*) into n from public.services s
  where system_key is not null
    and (select count(*) from public.service_packages p where p.service_id = s.id and p.is_active) = 1;
  if n <> 6 then raise exception 'FAIL: each default service needs one active package, got %', n; end if;
  raise notice 'PASS: each default service has a bookable package';

  select count(*) into n from public.services
  where system_key = 'book_mechanic' and vehicle_type = 'bike' and name = 'Book a Mechanic'
    and catalog_tab = 'mechanic' and category_id is not null;
  if n <> 1 then raise exception 'FAIL: Book a Mechanic is not in the mechanic tab'; end if;
  raise notice 'PASS: defaults sit in the Book a Mechanic category';

  select count(*) into n from public.service_categories where is_active;
  if n < 11 then raise exception 'FAIL: default categories missing (%)', n; end if;
  raise notice 'PASS: the default categories are seeded';

  select count(*) into n from public.service_categories
  where lower(name) in ('brakes', 'battery', 'cables', 'lights', 'filters', 'chain',
                        'lubricants & fluids', 'other repairs', 'engine repair', 'service packages');
  if n <> 10 then raise exception 'FAIL: named categories missing (%)', n; end if;
  raise notice 'PASS: Brakes, Battery, Cables, Lights, Filters, Lubricants, Chain, Other Repairs exist';

  select count(*) into n from public.services where category_id is null;
  if n <> 0 then raise exception 'FAIL: % services without a category', n; end if;
  raise notice 'PASS: every service has a category';

  begin
    insert into public.services (name, vehicle_type, system_key)
    values ('Dup', 'bike', 'book_mechanic');
    raise exception 'FAIL: a second default service of the same kind was accepted';
  exception when unique_violation then
    raise notice 'PASS: a default service cannot be duplicated';
  end;

  begin
    insert into public.service_categories (name, tab) values ('  BRAKES ', 'repair');
    raise exception 'FAIL: duplicate category name accepted';
  exception when unique_violation then
    raise notice 'PASS: category names are unique ignoring case';
  end;

  begin
    insert into public.service_packages (service_id, name, price, advance_percent)
    select id, 'X', 100, 0 from public.services where system_key = 'check_vehicle' limit 1;
    raise exception 'FAIL: 0 percent advance accepted';
  exception when check_violation then
    raise notice 'PASS: advance percent must be 1 to 100';
  end;

  begin
    insert into public.service_packages (service_id, name, price, labour_charge)
    select id, 'Y', 100, 150 from public.services where system_key = 'check_vehicle' limit 1;
    raise exception 'FAIL: labour above the price accepted';
  exception when check_violation then
    raise notice 'PASS: labour charge cannot exceed the price';
  end;

  begin
    update public.services set banner_url = 'http://x/y.jpg' where system_key = 'check_vehicle';
    raise exception 'FAIL: non-https banner accepted';
  exception when check_violation then
    raise notice 'PASS: picture links must be https';
  end;
end
$$;
