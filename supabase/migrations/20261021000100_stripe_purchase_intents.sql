-- A one-time intent binds a signed-in Pocony user and selected pack to a
-- specific Stripe Payment Link before the browser leaves for Checkout.
create table if not exists public.pocony_stripe_purchase_intents (
  id uuid primary key default gen_random_uuid(),
  uid text not null references public.pocony_users(uid),
  payment_link_id text not null,
  points integer not null check (points in (115, 365)),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  checkout_session_id text unique
);

alter table public.pocony_stripe_purchase_intents enable row level security;

create or replace function public.complete_pocony_stripe_purchase(
  p_stripe_event_id text,
  p_checkout_session_id text,
  p_intent_id uuid,
  p_payment_link_id text
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  purchase public.pocony_stripe_purchase_intents%rowtype;
begin
  select * into purchase
    from public.pocony_stripe_purchase_intents
   where id = p_intent_id
   for update;

  if not found then
    raise exception 'Purchase intent not found';
  end if;

  if purchase.payment_link_id <> p_payment_link_id then
    raise exception 'Payment link does not match purchase intent';
  end if;

  if purchase.completed_at is not null then
    if purchase.checkout_session_id = p_checkout_session_id then
      return false;
    end if;
    raise exception 'Purchase intent has already been used';
  end if;

  insert into public.pocony_stripe_point_grants
    (stripe_event_id, checkout_session_id, user_uid, points)
  values
    (p_stripe_event_id, p_checkout_session_id, purchase.uid, purchase.points)
  on conflict do nothing;

  if not found then
    return false;
  end if;

  update public.pocony_users
     set points = coalesce(points, 0) + purchase.points
   where uid = purchase.uid;

  if not found then
    raise exception 'Pocony user not found';
  end if;

  update public.pocony_stripe_purchase_intents
     set completed_at = now(), checkout_session_id = p_checkout_session_id
   where id = p_intent_id;

  return true;
end;
$$;

revoke all on function public.complete_pocony_stripe_purchase(text, text, uuid, text) from public, anon, authenticated;
grant execute on function public.complete_pocony_stripe_purchase(text, text, uuid, text) to service_role;
