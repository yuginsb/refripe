-- ReFripe — 6/6 : tâches planifiées (pg_cron)
-- Activer l'extension pg_cron dans le dashboard (Database → Extensions) si la
-- commande ci-dessous est refusée sur le projet hébergé.

create extension if not exists pg_cron;

-- ---------------------------------------------------------------------------
-- Séquestre : libération automatique 72 h après la livraison (Catalog.escrowAutoReleaseHours)
-- ---------------------------------------------------------------------------
create function private.release_escrow()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  n integer := 0;
begin
  for r in
    select id from public.orders
     where status in ('DELIVERED', 'BUYER_VALIDATION')
       and coalesce(delivered_at, status_changed_at) < now() - interval '72 hours'
     order by delivered_at
     limit 500
  loop
    begin
      perform private.transition_order(r.id, 'COMPLETED', 'system');
      n := n + 1;
    exception when others then
      raise warning 'release_escrow: commande % ignorée (%)', r.id, sqlerrm;
    end;
  end loop;
  return n;
end;
$$;

-- ---------------------------------------------------------------------------
-- Commandes jamais payées : annulées après 30 min, l'annonce redevient active.
-- ---------------------------------------------------------------------------
create function private.cancel_unpaid_orders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  n integer := 0;
begin
  for r in
    select id from public.orders
     where status = 'PAYMENT_PENDING' and created_at < now() - interval '30 minutes'
     limit 500
  loop
    begin
      update public.payments set state = 'failed', updated_at = now()
       where order_id = r.id and state = 'pending';
      perform private.transition_order(r.id, 'CANCELLED', 'system');
      n := n + 1;
    exception when others then
      raise warning 'cancel_unpaid_orders: commande % ignorée (%)', r.id, sqlerrm;
    end;
  end loop;
  return n;
end;
$$;

-- ---------------------------------------------------------------------------
-- Négociations : un fil sans réponse depuis 48 h expire ; idem si l'article
-- n'est plus en vente.
-- ---------------------------------------------------------------------------
create function private.expire_offer_threads()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  n integer;
begin
  update public.offer_threads t
     set status = 'expired', updated_at = now()
   where t.status = 'pending'
     and (
       t.updated_at < now() - interval '48 hours'
       or exists (select 1 from public.listings l where l.id = t.listing_id and l.status <> 'active')
     );
  get diagnostics n = row_count;
  return n;
end;
$$;

-- ---------------------------------------------------------------------------
-- Drops : garantit qu'un prochain créneau existe (12:00 / 19:00 UTC) et met en
-- avant la vendeuse la plus active de la semaine.
-- ---------------------------------------------------------------------------
create function private.rotate_drop()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_slot timestamptz;
  v_seller uuid;
  v_name text;
begin
  delete from public.drops where starts_at < now() - interval '7 days';
  if exists (select 1 from public.drops where starts_at > now()) then
    return;
  end if;

  v_slot := private.next_drop_slot(now());

  select l.seller_id, p.username into v_seller, v_name
    from public.listings l
    join public.profiles p on p.id = l.seller_id
   where l.status = 'active' and l.created_at > now() - interval '7 days'
   group by l.seller_id, p.username
   order by count(*) desc, max(l.created_at) desc
   limit 1;

  insert into public.drops (starts_at, title, seller_id)
  values (
    v_slot,
    case when v_name is not null then v_name || ' vide son dressing' else 'Nouveaux arrivages' end,
    v_seller
  )
  on conflict (starts_at) do nothing;
end;
$$;

-- ---------------------------------------------------------------------------
-- Rappel de série (« Série de N jours ») à 17:00 UTC pour les personnes actives
-- hier mais pas encore aujourd'hui.
-- ---------------------------------------------------------------------------
create function private.send_streak_reminders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  n integer;
begin
  insert into public.notifications (user_id, kind, title, body)
  select p.user_id, 'streak', 'Série de ' || p.streak_days || ' jours',
         'Continue à découvrir aujourd’hui pour garder ta série'
    from public.preferences p
   where p.streak_days >= 2
     and p.last_active_day >= date_trunc('day', now(), 'UTC') - interval '1 day'
     and p.last_active_day <  date_trunc('day', now(), 'UTC')
     and not exists (
       select 1 from public.notifications n2
        where n2.user_id = p.user_id and n2.kind = 'streak'
          and n2.created_at >= date_trunc('day', now(), 'UTC')
     );
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke all on all functions in schema private from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Planification (cron.schedule avec un nom = création ou mise à jour)
-- ---------------------------------------------------------------------------
select cron.schedule('refripe-release-escrow',       '*/15 * * * *', $$select private.release_escrow()$$);
select cron.schedule('refripe-cancel-unpaid-orders', '*/5 * * * *',  $$select private.cancel_unpaid_orders()$$);
select cron.schedule('refripe-expire-offers',        '*/30 * * * *', $$select private.expire_offer_threads()$$);
select cron.schedule('refripe-rotate-drop',          '*/10 * * * *', $$select private.rotate_drop()$$);
select cron.schedule('refripe-streak-reminders',     '0 17 * * *',   $$select private.send_streak_reminders()$$);

-- Premier drop immédiatement disponible.
select private.rotate_drop();
