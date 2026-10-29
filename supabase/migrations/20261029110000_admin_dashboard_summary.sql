-- =============================================================================
-- Admin dashboard figures in one query: bookings per status, money collected
-- and refunded, and active drivers. Read-only; only the backend (service role)
-- can call it. SAFE TO RERUN (create or replace).
-- =============================================================================
create or replace function public.admin_dashboard_summary()
returns table (
  by_status jsonb,
  collected numeric,
  refunded numeric,
  active_drivers integer
)
language sql
stable
set search_path = ''
as $$
  select
    coalesce(
      (select jsonb_object_agg(s.status, s.n)
         from (select b.status::text as status, count(*)::integer as n
                 from public.bookings b group by b.status) s),
      '{}'::jsonb
    ),
    coalesce((select sum(p.amount) from public.payments p
               where p.status = 'successful'), 0),
    coalesce((select sum(r.amount) from public.payment_refunds r), 0),
    (select count(*)::integer from public.profiles f
      where f.role = 'driver' and f.is_active);
$$;

revoke all on function public.admin_dashboard_summary() from public, anon, authenticated;
grant execute on function public.admin_dashboard_summary() to service_role;
