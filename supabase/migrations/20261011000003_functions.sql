-- ReFripe — 3/6 : helpers internes et RPC
-- Convention d'erreur : `raise exception '<message FR affichable>' using hint = '<code>'`.
-- Le client Swift lit `hint` (offer_limit_reached, not_authenticated, not_found, ...)
-- et affiche `message` sinon. Les apostrophes des messages sont typographiques (’).

-- ===========================================================================
-- Helpers internes (schéma private, non exposé)
-- ===========================================================================

create function private.require_uid()
returns uuid
language plpgsql stable
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Connecte-toi pour continuer.' using hint = 'not_authenticated';
  end if;
  return v_uid;
end;
$$;

-- 17000 -> '17 000 FCFA' (espace fine insécable, comme Fmt.fcfa côté Swift)
create function private.fcfa(p_value integer)
returns text
language sql immutable
set search_path = ''
as $$
  select replace(to_char(p_value, 'FM999,999,999,990'), ',', U&'\202F') || ' FCFA';
$$;

-- Miroir exact de DeliveryMethod.fee (Core/Catalog.swift)
create function private.delivery_fee(p_method public.delivery_method)
returns integer
language sql immutable
set search_path = ''
as $$
  select case p_method
    when 'relais' then 1000
    when 'main_propre' then 0
    when 'yango' then 2500
  end;
$$;

-- Miroir de OfferRules.step(for:)
create function private.offer_step(p_price integer)
returns integer
language sql immutable
set search_path = ''
as $$
  select case when p_price >= 6000 then 500 else 250 end;
$$;

-- Miroir de OrderStatus.label (pour les messages d'erreur / notifications)
create function private.order_status_label(p_status public.order_status)
returns text
language sql immutable
set search_path = ''
as $$
  select case p_status
    when 'PAYMENT_PENDING' then 'Paiement en attente'
    when 'PAID' then 'Paiement confirmé'
    when 'AWAITING_SHIPMENT' then 'Préparation du colis'
    when 'SHIPPED' then 'Colis expédié'
    when 'DELIVERED' then 'Arrivé au point de retrait'
    when 'BUYER_VALIDATION' then 'En attente de confirmation'
    when 'COMPLETED' then 'Commande terminée'
    when 'CANCELLED' then 'Annulée'
    when 'DISPUTED' then 'Litige en cours'
    when 'RETURN_PENDING' then 'Retour en cours'
    when 'REFUNDED' then 'Remboursée'
  end;
$$;

create function private.notify(
  p_user uuid,
  p_kind public.notification_kind,
  p_title text,
  p_body text,
  p_listing uuid default null,
  p_order uuid default null,
  p_conversation uuid default null
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.notifications (user_id, kind, title, body, listing_id, order_id, conversation_id)
  values (p_user, p_kind, p_title, p_body, p_listing, p_order, p_conversation);
$$;

-- Prochain créneau de drop : 12:00 et 19:00 UTC (= heure d'Abidjan et de Dakar).
create function private.next_drop_slot(p_after timestamptz)
returns timestamptz
language sql stable
set search_path = ''
as $$
  select min(s) from (values
    (date_trunc('day', p_after, 'UTC') + interval '12 hours'),
    (date_trunc('day', p_after, 'UTC') + interval '19 hours'),
    (date_trunc('day', p_after, 'UTC') + interval '1 day 12 hours')
  ) as v(s)
  where s > p_after;
$$;

create function private.profile_json(p_id uuid)
returns jsonb
language sql stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.id, 'username', p.username, 'first_name', p.first_name,
    'city', p.city, 'district', p.district, 'avatar_url', p.avatar_url,
    'verified', p.verified, 'rating', p.rating, 'sales_count', p.sales_count,
    'response_time_minutes', p.response_time_minutes, 'created_at', p.created_at
  )
  from public.profiles p where p.id = p_id;
$$;

-- ---------------------------------------------------------------------------
-- Machine à états des commandes.
-- p_actor : 'buyer' | 'seller' | 'system' (webhook, cron, médiation).
-- L'événement order_events et les notifications sont produits par le trigger
-- AFTER UPDATE sur orders (migration 4), qui lit l'acteur dans refripe.actor.
-- ---------------------------------------------------------------------------
create function private.transition_order(
  p_order_id uuid,
  p_to public.order_status,
  p_actor text
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  o public.orders;
  v_from public.order_status;
  v_allowed boolean;
begin
  select * into o from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'Commande introuvable.' using hint = 'not_found';
  end if;

  v_from := o.status;
  if v_from = p_to then
    return o; -- idempotent
  end if;

  v_allowed := case
    when v_from = 'PAYMENT_PENDING'  and p_to = 'PAID'              then p_actor = 'system'
    when v_from = 'PAYMENT_PENDING'  and p_to = 'CANCELLED'         then true
    when v_from = 'PAID'             and p_to = 'AWAITING_SHIPMENT' then p_actor = 'system'
    when v_from in ('PAID', 'AWAITING_SHIPMENT') and p_to = 'CANCELLED' then p_actor in ('seller', 'system')
    when v_from = 'AWAITING_SHIPMENT' and p_to = 'SHIPPED'          then p_actor in ('seller', 'system')
    when v_from = 'SHIPPED'          and p_to = 'DELIVERED'         then true
    when v_from = 'SHIPPED'          and p_to = 'DISPUTED'          then p_actor in ('buyer', 'system')
    when v_from = 'DELIVERED'        and p_to = 'BUYER_VALIDATION'  then p_actor = 'system'
    when v_from in ('DELIVERED', 'BUYER_VALIDATION') and p_to in ('COMPLETED', 'DISPUTED', 'RETURN_PENDING')
                                                                    then p_actor in ('buyer', 'system')
    when v_from = 'RETURN_PENDING'   and p_to = 'REFUNDED'          then p_actor in ('seller', 'system')
    when v_from = 'RETURN_PENDING'   and p_to = 'DISPUTED'          then true
    when v_from = 'DISPUTED'         and p_to in ('COMPLETED', 'REFUNDED') then p_actor = 'system'
    else false
  end;

  if not v_allowed then
    raise exception 'Action impossible : la commande est « % ».', private.order_status_label(v_from)
      using hint = 'invalid_transition';
  end if;

  perform set_config('refripe.actor', p_actor, true);

  update public.orders
     set status = p_to,
         status_changed_at = now(),
         delivered_at = case when p_to = 'DELIVERED' then now() else delivered_at end
   where id = p_order_id
  returning * into o;

  -- Effets de bord sur l'annonce et la vendeuse
  if p_to = 'COMPLETED' then
    update public.listings set status = 'sold', updated_at = now() where id = o.listing_id;
    update public.profiles set sales_count = sales_count + 1, updated_at = now() where id = o.seller_id;
  elsif p_to = 'CANCELLED' or (p_to = 'REFUNDED' and v_from = 'RETURN_PENDING') then
    update public.listings set status = 'active', updated_at = now()
     where id = o.listing_id and status = 'reserved';
  elsif p_to = 'REFUNDED' then
    -- remboursement après litige : l'annonce est retirée, la vendeuse la republiera
    update public.listings set status = 'removed', updated_at = now()
     where id = o.listing_id and status = 'reserved';
  end if;

  -- Enchaînements automatiques
  if p_to = 'PAID' then
    o := private.transition_order(p_order_id, 'AWAITING_SHIPMENT', 'system');
  elsif p_to = 'DELIVERED' then
    o := private.transition_order(p_order_id, 'BUYER_VALIDATION', 'system');
  end if;

  return o;
end;
$$;

-- ===========================================================================
-- RPC exposées (public)
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Inscription : crée/complète le profil (téléphone recopié depuis auth.users).
-- ---------------------------------------------------------------------------
create function public.complete_signup(
  p_username text,
  p_first_name text,
  p_city text,
  p_district text,
  p_is_adult boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
  v_username text := btrim(coalesce(p_username, ''));
begin
  if not coalesce(p_is_adult, false) then
    raise exception 'Tu dois confirmer avoir au moins 18 ans.' using hint = 'adult_required';
  end if;
  if v_username !~ '^[A-Za-z0-9_.]{3,30}$' then
    raise exception 'Pseudo invalide : 3 à 30 caractères (lettres, chiffres, _ ou .).' using hint = 'invalid_username';
  end if;
  if coalesce(p_city, '') not in ('Abidjan', 'Dakar') then
    raise exception 'ReFripe est disponible à Abidjan et à Dakar.' using hint = 'invalid_city';
  end if;
  if exists (select 1 from public.profiles where lower(username) = lower(v_username) and id <> v_uid) then
    raise exception 'Ce pseudo est déjà pris.' using hint = 'username_taken';
  end if;

  begin
    insert into public.profiles (id, username, first_name, city, district, phone)
    values (
      v_uid, v_username, btrim(coalesce(p_first_name, '')), p_city, btrim(coalesce(p_district, '')),
      (select u.phone from auth.users u where u.id = v_uid)
    )
    on conflict (id) do update
      set username = excluded.username,
          first_name = excluded.first_name,
          city = excluded.city,
          district = excluded.district,
          updated_at = now();
  exception when unique_violation then
    raise exception 'Ce pseudo est déjà pris.' using hint = 'username_taken';
  end;

  insert into public.preferences (user_id, is_adult_confirmed)
  values (v_uid, true)
  on conflict (user_id) do update set is_adult_confirmed = true, updated_at = now();

  return private.profile_json(v_uid);
end;
$$;

-- ---------------------------------------------------------------------------
-- Vue d'une annonce (dédoublonnée 30 min par visiteuse, jamais la vendeuse).
-- ---------------------------------------------------------------------------
create function public.record_view(p_listing_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_seller uuid;
begin
  if v_uid is null then
    return;
  end if;
  select seller_id into v_seller from public.listings where id = p_listing_id and status <> 'removed';
  if not found or v_seller = v_uid then
    return;
  end if;
  if exists (
    select 1 from public.listing_views
     where listing_id = p_listing_id and viewer_id = v_uid and viewed_at > now() - interval '30 minutes'
  ) then
    return;
  end if;
  insert into public.listing_views (listing_id, viewer_id) values (p_listing_id, v_uid);
  update public.listings set views_count = views_count + 1 where id = p_listing_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Pile de swipe : annonces actives, pas les miennes, pas encore swipées,
-- catégories préférées d'abord. Retourne les lignes de listings_public (sans min_offer).
-- ---------------------------------------------------------------------------
create function public.swipe_deck(p_limit integer default 40)
returns setof public.listings_public
language sql
stable
security invoker
set search_path = ''
as $$
  select lp.*
  from public.listings_public lp
  left join public.preferences p on p.user_id = (select auth.uid())
  where lp.status = 'active'
    and lp.seller_id is distinct from (select auth.uid())
    and not exists (
      select 1 from public.swipes s
      where s.user_id = (select auth.uid()) and s.listing_id = lp.id
    )
  order by
    case when cardinality(coalesce(p.categories, '{}')) > 0 and lp.gender = any (p.categories) then 0 else 1 end,
    lp.created_at desc
  limit greatest(1, least(coalesce(p_limit, 40), 100));
$$;

-- ---------------------------------------------------------------------------
-- Prochain drop (table drops, sinon prochain créneau calculé).
-- ---------------------------------------------------------------------------
create function public.next_drop()
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select min(d.starts_at) from public.drops d where d.starts_at > now()),
    private.next_drop_slot(now())
  );
$$;

-- ---------------------------------------------------------------------------
-- Négociation — acheteuse
-- Règles : annonce active et négociable, pas la sienne, montant < prix,
-- 3 offres max, une offre à la fois, chaque offre > la précédente.
-- Une offre >= à la contre-offre en cours vaut acceptation de cette contre-offre.
-- ---------------------------------------------------------------------------
create function public.make_offer(p_listing_id uuid, p_amount integer)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
  l public.listings;
  t public.offer_threads;
  v_last public.offer_rounds;
  v_count integer;
  v_last_buyer integer;
begin
  select * into l from public.listings where id = p_listing_id;
  if not found or l.status = 'removed' then
    raise exception 'Annonce introuvable.' using hint = 'not_found';
  end if;
  if l.seller_id = v_uid then
    raise exception 'Tu ne peux pas faire d’offre sur ta propre annonce.' using hint = 'own_listing';
  end if;
  if l.status <> 'active' then
    raise exception 'Cet article n’est plus disponible.' using hint = 'listing_unavailable';
  end if;
  if not l.negotiable then
    raise exception 'Cette annonce est à prix fixe.' using hint = 'not_negotiable';
  end if;
  if p_amount is null or p_amount <= 0 or p_amount >= l.price then
    raise exception 'Ton offre doit être inférieure au prix affiché (%).', private.fcfa(l.price)
      using hint = 'invalid_amount';
  end if;

  insert into public.offer_threads (listing_id, buyer_id, seller_id)
  values (l.id, v_uid, l.seller_id)
  on conflict (listing_id, buyer_id) do nothing;

  select * into t from public.offer_threads
   where listing_id = l.id and buyer_id = v_uid
   for update;

  if t.status = 'accepted' then
    raise exception 'Ton offre a déjà été acceptée : tu peux acheter au prix négocié.' using hint = 'already_accepted';
  end if;

  select count(*), max(amount) into v_count, v_last_buyer
    from public.offer_rounds where thread_id = t.id and party = 'buyer';
  if v_count >= 3 then
    raise exception 'Tu as déjà fait 3 offres sur cet article.' using hint = 'offer_limit_reached';
  end if;

  select * into v_last from public.offer_rounds
   where thread_id = t.id order by created_at desc, id desc limit 1;

  if t.status = 'pending' and v_last.party = 'buyer' then
    raise exception 'Attends la réponse de la vendeuse avant de refaire une offre.' using hint = 'awaiting_seller';
  end if;
  if v_last_buyer is not null and p_amount <= v_last_buyer then
    raise exception 'Ta nouvelle offre doit dépasser la précédente (%).', private.fcfa(v_last_buyer)
      using hint = 'invalid_amount';
  end if;

  if t.status = 'pending' and v_last.party = 'seller' and v_last.action = 'counter' and p_amount >= v_last.amount then
    insert into public.offer_rounds (thread_id, party, amount, action)
    values (t.id, 'buyer', v_last.amount, 'accept');
    update public.offer_threads set status = 'accepted', updated_at = now() where id = t.id;
  else
    insert into public.offer_rounds (thread_id, party, amount, action)
    values (t.id, 'buyer', p_amount, 'offer');
    update public.offer_threads set status = 'pending', updated_at = now() where id = t.id;
  end if;

  return t.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Négociation — vendeuse : accept | refuse | counter (montant strictement entre
-- la dernière offre et le prix affiché ; pas de contre-offre après la 3e offre).
-- ---------------------------------------------------------------------------
create function public.respond_offer(
  p_thread_id uuid,
  p_action public.offer_action,
  p_amount integer default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
  t public.offer_threads;
  l public.listings;
  v_last public.offer_rounds;
  v_count integer;
begin
  select * into t from public.offer_threads where id = p_thread_id for update;
  if not found or v_uid not in (t.buyer_id, t.seller_id) then
    raise exception 'Négociation introuvable.' using hint = 'not_found';
  end if;
  if t.seller_id <> v_uid then
    raise exception 'Seule la vendeuse peut répondre à cette offre.' using hint = 'forbidden';
  end if;
  if t.status <> 'pending' then
    raise exception 'Cette négociation est terminée.' using hint = 'thread_closed';
  end if;

  select * into l from public.listings where id = t.listing_id;
  if l.status <> 'active' then
    raise exception 'Cet article n’est plus disponible.' using hint = 'listing_unavailable';
  end if;

  select * into v_last from public.offer_rounds
   where thread_id = t.id order by created_at desc, id desc limit 1;
  if v_last.id is null or v_last.party <> 'buyer' then
    raise exception 'Attends la prochaine offre de l’acheteuse.' using hint = 'awaiting_buyer';
  end if;

  if p_action = 'accept' then
    insert into public.offer_rounds (thread_id, party, amount, action) values (t.id, 'seller', v_last.amount, 'accept');
    update public.offer_threads set status = 'accepted', updated_at = now() where id = t.id;
  elsif p_action = 'refuse' then
    insert into public.offer_rounds (thread_id, party, amount, action) values (t.id, 'seller', v_last.amount, 'refuse');
    update public.offer_threads set status = 'refused', updated_at = now() where id = t.id;
  elsif p_action = 'counter' then
    select count(*) into v_count from public.offer_rounds where thread_id = t.id and party = 'buyer';
    if v_count >= 3 then
      raise exception 'L’acheteuse a utilisé ses 3 offres : accepte ou refuse.' using hint = 'counter_not_allowed';
    end if;
    if p_amount is null or p_amount <= v_last.amount or p_amount >= l.price then
      raise exception 'La contre-offre doit être comprise entre % et % (exclus).',
        private.fcfa(v_last.amount), private.fcfa(l.price)
        using hint = 'invalid_amount';
    end if;
    insert into public.offer_rounds (thread_id, party, amount, action) values (t.id, 'seller', p_amount, 'counter');
    update public.offer_threads set updated_at = now() where id = t.id;
  else
    raise exception 'Action invalide.' using hint = 'invalid_action';
  end if;

  return t.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Commande : prix négocié si offre acceptée, frais = DeliveryMethod.fee,
-- livraison proposée par l'annonce, annonce -> reserved, statut PAYMENT_PENDING.
-- ---------------------------------------------------------------------------
create function public.create_order(
  p_listing_id uuid,
  p_delivery public.delivery_method,
  p_payment public.payment_method
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
  l public.listings;
  b public.profiles;
  v_thread uuid;
  v_accepted integer;
  v_order uuid;
begin
  select * into b from public.profiles where id = v_uid;
  if not found then
    raise exception 'Complète ton profil avant d’acheter.' using hint = 'profile_required';
  end if;

  select * into l from public.listings where id = p_listing_id for update;
  if not found or l.status = 'removed' then
    raise exception 'Annonce introuvable.' using hint = 'not_found';
  end if;
  if l.seller_id = v_uid then
    raise exception 'Tu ne peux pas acheter ta propre annonce.' using hint = 'own_listing';
  end if;
  if l.status <> 'active' then
    raise exception 'Cet article vient d’être réservé ou vendu.' using hint = 'listing_unavailable';
  end if;
  if p_delivery is null or not (p_delivery = any (l.delivery_methods)) then
    raise exception 'Ce mode de livraison n’est pas proposé pour cet article.' using hint = 'delivery_unavailable';
  end if;
  if p_payment is null then
    raise exception 'Choisis un moyen de paiement.' using hint = 'payment_required';
  end if;

  select t.id,
         (select r.amount from public.offer_rounds r
           where r.thread_id = t.id and r.action = 'accept'
           order by r.created_at desc limit 1)
    into v_thread, v_accepted
    from public.offer_threads t
   where t.listing_id = l.id and t.buyer_id = v_uid and t.status = 'accepted';

  insert into public.orders (
    listing_id, seller_id, buyer_id, offer_thread_id, listing_title, listing_photo, buyer_name,
    item_price, delivery_fee, delivery, payment
  ) values (
    l.id, l.seller_id, v_uid, v_thread, l.title, l.photos[1],
    coalesce(nullif(b.first_name, ''), b.username),
    least(coalesce(v_accepted, l.price), l.price),
    private.delivery_fee(p_delivery),
    p_delivery, p_payment
  )
  returning id into v_order;

  update public.listings set status = 'reserved', updated_at = now() where id = l.id;

  return v_order;
end;
$$;

-- ---------------------------------------------------------------------------
-- Avancement d'une commande par l'une des parties (rôle déduit de auth.uid()).
-- Vendeuse : AWAITING_SHIPMENT→SHIPPED, SHIPPED→DELIVERED, annulation avant
--            expédition, RETURN_PENDING→REFUNDED (retour reçu).
-- Acheteuse : DELIVERED/BUYER_VALIDATION→COMPLETED|DISPUTED|RETURN_PENDING,
--             SHIPPED→DELIVERED (réception), SHIPPED→DISPUTED, annulation avant paiement.
-- ---------------------------------------------------------------------------
create function public.advance_order(p_order_id uuid, p_status public.order_status)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
  o public.orders;
begin
  select * into o from public.orders where id = p_order_id;
  if not found or v_uid not in (o.buyer_id, o.seller_id) then
    raise exception 'Commande introuvable.' using hint = 'not_found';
  end if;
  perform private.transition_order(
    p_order_id, p_status,
    case when v_uid = o.buyer_id then 'buyer' else 'seller' end
  );
  return p_order_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Messagerie
-- ---------------------------------------------------------------------------
create function public.get_or_create_conversation(p_other_user uuid, p_listing_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
  v_a uuid;
  v_b uuid;
  v_id uuid;
begin
  if p_other_user is null or p_other_user = v_uid then
    raise exception 'Conversation impossible.' using hint = 'invalid_user';
  end if;
  if not exists (select 1 from public.profiles where id = p_other_user) then
    raise exception 'Utilisatrice introuvable.' using hint = 'not_found';
  end if;
  if p_listing_id is not null and not exists (select 1 from public.listings where id = p_listing_id) then
    raise exception 'Annonce introuvable.' using hint = 'not_found';
  end if;

  v_a := least(v_uid, p_other_user);
  v_b := greatest(v_uid, p_other_user);

  select id into v_id from public.conversations
   where user_a = v_a and user_b = v_b and listing_id is not distinct from p_listing_id;
  if found then
    return v_id;
  end if;

  begin
    insert into public.conversations (listing_id, user_a, user_b)
    values (p_listing_id, v_a, v_b)
    returning id into v_id;
  exception when unique_violation then
    select id into v_id from public.conversations
     where user_a = v_a and user_b = v_b and listing_id is not distinct from p_listing_id;
  end;
  return v_id;
end;
$$;

create function public.mark_conversation_read(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
begin
  update public.conversations
     set unread_a = case when user_a = v_uid then 0 else unread_a end,
         unread_b = case when user_b = v_uid then 0 else unread_b end
   where id = p_conversation_id and v_uid in (user_a, user_b);
  if not found then
    raise exception 'Conversation introuvable.' using hint = 'not_found';
  end if;
  update public.notifications
     set read = true
   where user_id = v_uid and conversation_id = p_conversation_id and not read;
end;
$$;

-- ---------------------------------------------------------------------------
-- Tableau de bord vendeuse. Renvoie un objet aux clés camelCase de SellerStats.
-- Mois en cours (à date) vs mois précédent ; vues de la semaine lundi→dimanche.
-- ---------------------------------------------------------------------------
create function public.seller_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
  m0 timestamptz := date_trunc('month', now(), 'UTC');
  m1 timestamptz := date_trunc('month', now(), 'UTC') - interval '1 month';
  w0 timestamptz := date_trunc('week', now(), 'UTC');
  v_sales integer; v_sales_prev integer;
  v_rev integer; v_rev_prev integer;
  v_views integer; v_views_prev integer;
  v_fav integer; v_fav_prev integer;
  v_week integer[];
  v_goal integer;
  v_tier text; v_next text; v_needed integer;
  v_views_delta text;
begin
  select count(*) filter (where o.created_at >= m0),
         count(*) filter (where o.created_at < m0),
         coalesce(sum(o.item_price) filter (where o.created_at >= m0), 0),
         coalesce(sum(o.item_price) filter (where o.created_at < m0), 0)
    into v_sales, v_sales_prev, v_rev, v_rev_prev
    from public.orders o
   where o.seller_id = v_uid
     and o.created_at >= m1
     and o.status not in ('PAYMENT_PENDING', 'CANCELLED', 'REFUNDED');

  select count(*) filter (where v.viewed_at >= m0),
         count(*) filter (where v.viewed_at < m0)
    into v_views, v_views_prev
    from public.listing_views v
    join public.listings l on l.id = v.listing_id
   where l.seller_id = v_uid and v.viewed_at >= m1;

  select count(*) filter (where w.created_at >= m0),
         count(*) filter (where w.created_at < m0)
    into v_fav, v_fav_prev
    from public.wishlist w
    join public.listings l on l.id = w.listing_id
   where l.seller_id = v_uid and w.created_at >= m1;

  select array_agg(coalesce(c.n, 0) order by d.i)
    into v_week
    from generate_series(0, 6) as d(i)
    left join (
      select (extract(isodow from v.viewed_at at time zone 'UTC'))::int - 1 as i, count(*)::int as n
        from public.listing_views v
        join public.listings l on l.id = v.listing_id
       where l.seller_id = v_uid and v.viewed_at >= w0
       group by 1
    ) c on c.i = d.i;

  -- Objectif : +20 % sur le mois dernier, arrondi à 5 000, minimum 50 000 FCFA.
  v_goal := greatest(50000, (ceil(v_rev_prev * 1.2 / 5000.0) * 5000)::int);

  -- Paliers mensuels (ventes du mois)
  if v_sales >= 15 then v_tier := 'Platine'; v_next := 'Platine'; v_needed := v_sales;
  elsif v_sales >= 7 then v_tier := 'Or'; v_next := 'Platine'; v_needed := 15;
  elsif v_sales >= 3 then v_tier := 'Argent'; v_next := 'Or'; v_needed := 7;
  else v_tier := 'Bronze'; v_next := 'Argent'; v_needed := 3;
  end if;

  if v_views_prev = 0 then
    v_views_delta := case when v_views > 0 then 'Nouveau ce mois-ci' else 'Pas encore de vues' end;
  else
    v_views_delta := case when v_views >= v_views_prev then '+' else '−' end
      || abs(round((v_views - v_views_prev) * 100.0 / v_views_prev))::int || ' % vs mois dernier';
  end if;

  return jsonb_build_object(
    'sales', v_sales,
    'salesDelta', case when v_sales >= v_sales_prev then '+' else '−' end
                  || abs(v_sales - v_sales_prev) || ' vs mois dernier',
    'revenue', v_rev,
    'revenueDelta', case when v_rev >= v_rev_prev then '+' else '−' end
                    || private.fcfa(abs(v_rev - v_rev_prev)) || ' vs mois dernier',
    'views', v_views,
    'viewsDelta', v_views_delta,
    'favorites', v_fav,
    'favoritesDelta', case when v_fav >= v_fav_prev then '+' else '−' end
                      || abs(v_fav - v_fav_prev) || ' vs mois dernier',
    'monthlyGoal', v_goal,
    'tier', v_tier,
    'nextTier', v_next,
    'tierSalesNow', v_sales,
    'tierSalesNeeded', v_needed,
    'weekViews', to_jsonb(v_week)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Recommandations vendeuse (règles simples inspirées de la maquette), max 4.
-- Renvoie un tableau d'objets aux clés de SellerRecommendation.
-- ---------------------------------------------------------------------------
create function public.seller_recommendations()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
  v_out jsonb := '[]'::jsonb;
  v_rt integer;
  r record;
  v_new_price integer;
  v_step integer;
  v_used uuid[] := '{}';
begin
  -- 1. Commande payée à expédier
  for r in
    select o.listing_id, o.listing_title, o.status_changed_at
      from public.orders o
     where o.seller_id = v_uid and o.status = 'AWAITING_SHIPMENT'
     order by o.status_changed_at
     limit 1
  loop
    v_out := v_out || jsonb_build_object(
      'id', gen_random_uuid(), 'symbol', 'shippingbox',
      'title', 'Expédie « ' || r.listing_title || ' »',
      'body', 'L’acheteuse a payé il y a ' || greatest(1, (extract(epoch from now() - r.status_changed_at) / 3600)::int)
              || ' h. Expédie vite : les fonds sont libérés plus tôt et ta note reste au top.',
      'cta', 'Voir l’annonce', 'listingId', r.listing_id);
  end loop;

  -- 2. Beaucoup de vues, pas de vente depuis 2 semaines -> baisse de prix
  for r in
    select l.id, l.title, l.price, l.views_count
      from public.listings l
     where l.seller_id = v_uid and l.status = 'active'
       and l.created_at < now() - interval '14 days'
       and l.views_count >= 50
     order by l.views_count desc
     limit 1
  loop
    v_step := private.offer_step(r.price);
    v_new_price := greatest(v_step, (round(r.price * 0.9 / v_step) * v_step)::int);
    if v_new_price < r.price then
      v_out := v_out || jsonb_build_object(
        'id', gen_random_uuid(), 'symbol', 'chart.line.downtrend.xyaxis',
        'title', 'Baisse le prix de « ' || r.title || ' »',
        'body', r.views_count || ' vues mais aucune vente depuis 2 semaines. Une baisse à '
                || private.fcfa(v_new_price) || ' le remettrait en avant dans les résultats de recherche.',
        'cta', 'Ajuster l’annonce', 'listingId', r.id);
      v_used := v_used || r.id;
    end if;
  end loop;

  -- 3. Moins de 4 photos
  for r in
    select l.id, l.title
      from public.listings l
     where l.seller_id = v_uid and l.status = 'active'
       and cardinality(l.photos) < 4 and not (l.id = any (v_used))
     order by l.views_count desc, l.created_at desc
     limit 1
  loop
    v_out := v_out || jsonb_build_object(
      'id', gen_random_uuid(), 'symbol', 'camera',
      'title', 'Ajoute des photos à « ' || r.title || ' »',
      'body', 'Les annonces avec 4 photos ou plus se vendent en moyenne 2× plus vite sur ReFripe.',
      'cta', 'Compléter l’annonce', 'listingId', r.id);
    v_used := v_used || r.id;
  end loop;

  -- 4. Article le plus vu -> partage WhatsApp
  for r in
    select l.id, l.title, l.views_count
      from public.listings l
     where l.seller_id = v_uid and l.status = 'active' and l.views_count >= 20
       and not (l.id = any (v_used))
     order by l.views_count desc
     limit 1
  loop
    v_out := v_out || jsonb_build_object(
      'id', gen_random_uuid(), 'symbol', 'megaphone',
      'title', 'Partage « ' || r.title || ' »',
      'body', 'C’est ton article le plus vu (' || r.views_count
              || ' vues) — un partage sur ton statut WhatsApp peut déclencher la vente cette semaine.',
      'cta', 'Voir l’annonce à partager', 'listingId', r.id);
  end loop;

  -- 5. Temps de réponse
  select response_time_minutes into v_rt from public.profiles where id = v_uid;
  if v_rt is not null and v_rt <= 15 then
    v_out := v_out || jsonb_build_object(
      'id', gen_random_uuid(), 'symbol', 'bolt',
      'title', 'Continue à répondre aussi vite',
      'body', 'Ton temps de réponse moyen (~' || greatest(v_rt, 1)
              || ' min) améliore ta visibilité dans Découvrir.',
      'cta', null, 'listingId', null);
  elsif v_rt is not null and v_rt > 60 then
    v_out := v_out || jsonb_build_object(
      'id', gen_random_uuid(), 'symbol', 'clock',
      'title', 'Réponds plus vite aux messages',
      'body', 'Ton temps de réponse moyen est d’environ ' || round(v_rt / 60.0)::int
              || ' h. Sous 15 min, les acheteuses achètent bien plus souvent.',
      'cta', null, 'listingId', null);
  end if;

  -- 6. Aucune annonce active
  if not exists (select 1 from public.listings where seller_id = v_uid and status = 'active') then
    v_out := v_out || jsonb_build_object(
      'id', gen_random_uuid(), 'symbol', 'plus.circle',
      'title', 'Publie un nouvel article',
      'body', 'Une annonce se crée en quelques minutes : photos, taille, prix, et c’est en ligne.',
      'cta', null, 'listingId', null);
  end if;

  return coalesce((
    select jsonb_agg(e.value order by e.ordinality)
      from jsonb_array_elements(v_out) with ordinality as e(value, ordinality)
     where e.ordinality <= 4
  ), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- Paiement (service_role uniquement : appelé par les Edge Functions)
-- ---------------------------------------------------------------------------
create function public.confirm_payment(
  p_order_id uuid,
  p_amount integer,
  p_provider text,
  p_provider_ref text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  o public.orders;
begin
  select * into o from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'order_not_found' using hint = 'not_found';
  end if;
  if o.status <> 'PAYMENT_PENDING' then
    -- Idempotent : déjà traité (ou annulé : remboursement manuel à prévoir)
    return o.status::text;
  end if;
  if p_amount is distinct from (o.item_price + o.delivery_fee) then
    raise exception 'amount_mismatch: attendu %, reçu %', o.item_price + o.delivery_fee, p_amount
      using hint = 'amount_mismatch';
  end if;

  update public.payments
     set state = 'succeeded', provider_ref = coalesce(p_provider_ref, provider_ref), updated_at = now()
   where order_id = p_order_id and provider = p_provider and state = 'pending';

  o := private.transition_order(p_order_id, 'PAID', 'system');
  return o.status::text;
end;
$$;

create function public.fail_payment(p_order_id uuid, p_provider text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  o public.orders;
begin
  select * into o from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'order_not_found' using hint = 'not_found';
  end if;
  update public.payments set state = 'failed', updated_at = now()
   where order_id = p_order_id and provider = p_provider and state = 'pending';
  if o.status = 'PAYMENT_PENDING' then
    o := private.transition_order(p_order_id, 'CANCELLED', 'system');
  end if;
  return o.status::text;
end;
$$;

-- ===========================================================================
-- Privilèges d'exécution (Postgres accorde EXECUTE à PUBLIC par défaut)
-- ===========================================================================
revoke all on all functions in schema private from public, anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;

grant execute on function
  public.complete_signup(text, text, text, text, boolean),
  public.record_view(uuid),
  public.swipe_deck(integer),
  public.make_offer(uuid, integer),
  public.respond_offer(uuid, public.offer_action, integer),
  public.create_order(uuid, public.delivery_method, public.payment_method),
  public.advance_order(uuid, public.order_status),
  public.get_or_create_conversation(uuid, uuid),
  public.mark_conversation_read(uuid),
  public.seller_stats(),
  public.seller_recommendations()
to authenticated;

grant execute on function public.next_drop() to anon, authenticated;

grant execute on function
  public.confirm_payment(uuid, integer, text, text),
  public.fail_payment(uuid, text)
to service_role;
