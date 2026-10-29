-- =============================================================================
-- TEST-ONLY. admin_dashboard_summary(): figures agree with the tables, and only
-- the service role may call it.
-- =============================================================================
\set ON_ERROR_STOP on
\set QUIET on

do $$
declare
  r record;
  n bigint;
  s numeric;
begin
  select * into r from public.admin_dashboard_summary();

  select coalesce(sum(value::int), 0) into n from jsonb_each_text(r.by_status);
  if n <> (select count(*) from public.bookings) then
    raise exception 'FAIL: status counts (%) do not add up to the bookings', n;
  end if;
  raise notice 'PASS: bookings per status add up to all bookings';

  select coalesce(sum(amount), 0) into s from public.payments where status = 'successful';
  if r.collected <> s then raise exception 'FAIL: collected % vs %', r.collected, s; end if;
  select coalesce(sum(amount), 0) into s from public.payment_refunds;
  if r.refunded <> s then raise exception 'FAIL: refunded % vs %', r.refunded, s; end if;
  raise notice 'PASS: money collected and refunded match the tables';

  select count(*) into n from public.profiles where role = 'driver' and is_active;
  if r.active_drivers <> n then raise exception 'FAIL: active drivers % vs %', r.active_drivers, n; end if;
  raise notice 'PASS: active drivers are counted';

  if has_function_privilege('authenticated', 'public.admin_dashboard_summary()', 'execute')
     or has_function_privilege('anon', 'public.admin_dashboard_summary()', 'execute') then
    raise exception 'FAIL: the summary must not be callable by signed-in users';
  end if;
  if not has_function_privilege('service_role', 'public.admin_dashboard_summary()', 'execute') then
    raise exception 'FAIL: the backend must be able to call the summary';
  end if;
  raise notice 'PASS: only the service role can call the summary';
end
$$;
