-- Stripe point grants are written only by the verified server-side webhook.
-- Keep this table inaccessible to browser roles; service_role calls the RPC below.
create table if not exists public.pocony_stripe_point_grants (
  id bigint generated always as identity primary key,
  stripe_event_id text not null unique,
  checkout_session_id text not null unique,
  user_uid text not null references public.pocony_users(uid),
  points integer not null check (points in (115, 365)),
  created_at timestamptz not null default now()
);

alter table public.pocony_stripe_point_grants enable row level security;

create or replace function public.grant_pocony_points_from_stripe(
  p_stripe_event_id text,
  p_checkout_session_id text,
  p_user_uid text,
  p_points integer
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_stripe_event_id is null or length(trim(p_stripe_event_id)) = 0
     or p_checkout_session_id is null or length(trim(p_checkout_session_id)) = 0
     or p_points not in (115, 365) then
    raise exception 'Invalid Stripe point grant';
  end if;

  insert into public.pocony_stripe_point_grants
    (stripe_event_id, checkout_session_id, user_uid, points)
  values
    (p_stripe_event_id, p_checkout_session_id, p_user_uid, p_points)
  on conflict do nothing;

  if not found then
    return false;
  end if;

  update public.pocony_users
     set points = coalesce(points, 0) + p_points
   where uid = p_user_uid;

  if not found then
    raise exception 'Pocony user not found';
  end if;

  return true;
end;
$$;

revoke all on function public.grant_pocony_points_from_stripe(text, text, text, integer) from public, anon, authenticated;
grant execute on function public.grant_pocony_points_from_stripe(text, text, text, integer) to service_role;
