-- =============================================================================
-- Phase 6: driver assignment and driver status updates.
--
-- Everything that changes who is assigned, or moves a booking through the driver
-- steps, goes through the functions below (service role only). Each runs in one
-- transaction with the booking row locked, so two admins or an admin and a driver
-- cannot race each other, and the booking status and its assignment never disagree.
--
--   assign_driver(booking, driver, admin)   confirmed -> assigned, or reassign
--   unassign_driver(booking, admin)         assigned  -> confirmed
--   driver_update_status(booking, driver, status)
--                                           assigned -> on_the_way -> in_progress -> completed
--
-- Expected refusals come back as a `result` value instead of an exception so the
-- backend can answer with the right message:
--   booking_not_found, driver_not_found, driver_inactive, not_paid, not_assignable,
--   driver_busy, not_unassignable, not_assigned, booking_cancelled, invalid_transition
-- Success values: assigned, reassigned, unchanged, unassigned, updated.
-- Customers, drivers and admins cannot call these through the REST API (no grants);
-- API roles still have SELECT only on bookings and driver_assignments.
-- =============================================================================

-- One more lookup the driver app uses: "my open work, by date".
create index if not exists driver_assignments_driver_booking_idx
  on public.driver_assignments (driver_id, booking_id);

-- -----------------------------------------------------------------------------
-- assign_driver
-- -----------------------------------------------------------------------------
create function public.assign_driver(
  p_booking_id uuid,
  p_driver_id uuid,
  p_admin_id uuid
)
returns table (result text, assignment_id uuid, booking_status public.booking_status)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_booking public.bookings;
  v_driver public.profiles;
  v_current public.driver_assignments;
  v_new_id uuid;
begin
  select * into v_booking from public.bookings where id = p_booking_id for update;
  if not found then
    return query select 'booking_not_found'::text, null::uuid, null::public.booking_status;
    return;
  end if;

  select * into v_driver from public.profiles where id = p_driver_id and role = 'driver';
  if not found then
    return query select 'driver_not_found'::text, null::uuid, v_booking.status;
    return;
  end if;

  select * into v_current from public.driver_assignments da
    where da.booking_id = p_booking_id and da.is_active for update;

  -- Asking for the driver who already has the booking changes nothing (safe retry).
  if found and v_current.driver_id = p_driver_id
     and v_booking.status in ('assigned', 'on_the_way', 'in_progress', 'completed') then
    return query select 'unchanged'::text, v_current.id, v_booking.status;
    return;
  end if;

  if not v_driver.is_active then
    return query select 'driver_inactive'::text, null::uuid, v_booking.status;
    return;
  end if;

  if v_booking.status not in ('confirmed', 'assigned', 'on_the_way') then
    return query select 'not_assignable'::text, null::uuid, v_booking.status;
    return;
  end if;

  -- Only a booking with a verified payment gets a driver.
  if not exists (
    select 1 from public.payments p
    where p.booking_id = p_booking_id and p.status = 'successful'
  ) then
    return query select 'not_paid'::text, null::uuid, v_booking.status;
    return;
  end if;

  -- A driver cannot be in two places at once.
  if exists (
    select 1
    from public.driver_assignments da
    join public.bookings b on b.id = da.booking_id
    where da.driver_id = p_driver_id
      and da.is_active
      and b.id <> p_booking_id
      and b.status in ('assigned', 'on_the_way', 'in_progress')
      and b.scheduled_date = v_booking.scheduled_date
      and b.slot_start < v_booking.slot_end
      and b.slot_end > v_booking.slot_start
  ) then
    return query select 'driver_busy'::text, null::uuid, v_booking.status;
    return;
  end if;

  if v_current.id is not null then
    update public.driver_assignments
      set is_active = false, unassigned_at = now()
      where id = v_current.id;
  end if;

  insert into public.driver_assignments (booking_id, driver_id, assigned_by)
    values (p_booking_id, p_driver_id, p_admin_id)
    returning id into v_new_id;

  if v_booking.status = 'confirmed' then
    update public.bookings set status = 'assigned' where id = p_booking_id;
    return query select 'assigned'::text, v_new_id, 'assigned'::public.booking_status;
  else
    return query select 'reassigned'::text, v_new_id, v_booking.status;
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- unassign_driver: back to confirmed, only before the driver has set off
-- -----------------------------------------------------------------------------
create function public.unassign_driver(p_booking_id uuid, p_admin_id uuid)
returns table (result text, booking_status public.booking_status)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_booking public.bookings;
  v_current public.driver_assignments;
begin
  select * into v_booking from public.bookings where id = p_booking_id for update;
  if not found then
    return query select 'booking_not_found'::text, null::public.booking_status;
    return;
  end if;

  select * into v_current from public.driver_assignments da
    where da.booking_id = p_booking_id and da.is_active for update;

  if v_booking.status = 'confirmed' and v_current.id is null then
    return query select 'unchanged'::text, v_booking.status;
    return;
  end if;
  if v_booking.status <> 'assigned' then
    return query select 'not_unassignable'::text, v_booking.status;
    return;
  end if;

  if v_current.id is not null then
    update public.driver_assignments
      set is_active = false, unassigned_at = now()
      where id = v_current.id;
  end if;
  update public.bookings set status = 'confirmed' where id = p_booking_id;
  return query select 'unassigned'::text, 'confirmed'::public.booking_status;
end;
$$;

-- -----------------------------------------------------------------------------
-- driver_update_status: the driver's own steps, on their own booking only
-- -----------------------------------------------------------------------------
create function public.driver_update_status(
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

  -- The booking must be (or have been) this driver's. A booking that was reassigned
  -- away is no longer theirs to change.
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

  update public.bookings
    set status = p_status,
        completed_at = case when p_status = 'completed' then now() else completed_at end
    where id = p_booking_id;
  return query select 'updated'::text, p_status;
end;
$$;

-- -----------------------------------------------------------------------------
-- Lists for the driver app and the admin: a driver's bookings, newest work first
-- -----------------------------------------------------------------------------
--   scope 'open'    assigned, on_the_way, in_progress  (soonest visit first)
--   scope 'history' completed and cancelled            (latest visit first)
-- A completed or cancelled booking keeps its assignment row active on purpose: it is
-- the driver's record of the job (and of a visit that was called off).
create function public.driver_booking_ids(
  p_driver_id uuid,
  p_scope text,
  p_limit integer,
  p_offset integer
)
returns table (booking_id uuid, total bigint)
language plpgsql
stable
set search_path = ''
as $$
#variable_conflict use_column
begin
  if p_scope not in ('open', 'history') then
    raise exception 'scope must be open or history' using errcode = '22023';
  end if;
  return query
    with mine as (
      select b.id, b.scheduled_date, b.slot_start, b.booking_number
      from public.driver_assignments da
      join public.bookings b on b.id = da.booking_id
      where da.driver_id = p_driver_id
        and da.is_active
        and ((p_scope = 'open' and b.status in ('assigned', 'on_the_way', 'in_progress'))
          or (p_scope = 'history' and b.status in ('completed', 'cancelled')))
    )
    select m.id, count(*) over ()
    from mine m
    order by
      case when p_scope = 'open' then m.scheduled_date end asc,
      case when p_scope = 'open' then m.slot_start end asc,
      case when p_scope = 'history' then m.scheduled_date end desc,
      case when p_scope = 'history' then m.slot_start end desc,
      m.booking_number asc
    limit greatest(p_limit, 0) offset greatest(p_offset, 0);
end;
$$;

-- How many open bookings each driver has (drivers with none are left out).
create function public.driver_workload()
returns table (driver_id uuid, open_bookings bigint)
language sql
stable
set search_path = ''
as $$
  select da.driver_id, count(*)
  from public.driver_assignments da
  join public.bookings b on b.id = da.booking_id
  where da.is_active and b.status in ('assigned', 'on_the_way', 'in_progress')
  group by da.driver_id;
$$;

revoke all on function public.assign_driver(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.unassign_driver(uuid, uuid) from public, anon, authenticated;
revoke all on function public.driver_update_status(uuid, uuid, public.booking_status)
  from public, anon, authenticated;
grant execute on function public.assign_driver(uuid, uuid, uuid) to service_role;
grant execute on function public.unassign_driver(uuid, uuid) to service_role;
grant execute on function public.driver_update_status(uuid, uuid, public.booking_status)
  to service_role;
revoke all on function public.driver_booking_ids(uuid, text, integer, integer)
  from public, anon, authenticated;
revoke all on function public.driver_workload() from public, anon, authenticated;
grant execute on function public.driver_booking_ids(uuid, text, integer, integer) to service_role;
grant execute on function public.driver_workload() to service_role;
