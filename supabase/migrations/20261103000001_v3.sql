-- ReFripe — v3 : type d'article, réservation 2 h, code de remise, avis, modération,
-- suppression de compte, photos dans le chat, nouvelles notifications.
-- Voir docs/DESIGN-v3.md (règles) et docs/BACKEND.md § 9 (résumé).
--
-- Conventions inchangées : fonctions security definer + search_path = '', erreurs
-- `raise exception '<message FR>' using hint = '<code>'`, écritures métier via RPC.
--
-- Note : les nouvelles valeurs de l'enum notification_kind ne sont utilisées que dans
-- des corps de fonctions plpgsql (évalués à l'exécution), jamais directement dans cette
-- migration : `alter type ... add value` reste donc sûr dans une transaction.

-- ===========================================================================
-- 1. Types
-- ===========================================================================
create type public.item_type as enum (
  'robe', 'pagne', 'ensemble', 'haut', 'chemise', 'pantalon', 'jean', 'jupe',
  'chaussures', 'sac', 'accessoire', 'autre'
);
create type public.report_reason as enum ('counterfeit', 'prohibited', 'misleading', 'offensive', 'scam', 'other');

alter type public.notification_kind add value if not exists 'offer_received';
alter type public.notification_kind add value if not exists 'offer_accepted';
alter type public.notification_kind add value if not exists 'offer_refused';
alter type public.notification_kind add value if not exists 'new_sale';

-- ===========================================================================
-- 2. Colonnes
-- ===========================================================================

-- Annonces : type d'article + réservation de 2 h après une offre acceptée.
alter table public.listings
  add column item_type      public.item_type not null default 'autre',
  add column reserved_until timestamptz,
  add column reserved_for   uuid references public.profiles (id) on delete set null;
create index listings_item_type_idx on public.listings (item_type) where status = 'active';
create index listings_district_idx  on public.listings (district) where status = 'active';

grant insert (item_type) on public.listings to authenticated;
grant update (item_type) on public.listings to authenticated;

-- Profils : nombre d'avis (rating = moyenne, maintenus par trigger) + suppression de compte.
alter table public.profiles
  add column review_count integer not null default 0 check (review_count >= 0),
  add column deleted_at   timestamptz;
grant select (review_count) on public.profiles to anon, authenticated;

-- Le profil d'un compte supprimé reste en « pierre tombale » anonymisée (les commandes passées
-- le référencent) : il ne doit donc plus disparaître en cascade avec auth.users.
alter table public.profiles drop constraint if exists profiles_id_fkey;

-- Commandes : code de remise (acheteuse uniquement), libération du séquestre, référence de paiement.
alter table public.orders
  add column handoff_code      text check (handoff_code ~ '^[0-9]{4}$'),
  add column handoff_attempts  integer not null default 0,
  add column escrow_release_at timestamptz,
  add column payment_reference text;

-- La vendeuse lit la commande mais JAMAIS handoff_code : privilèges par colonne.
-- L'acheteuse obtient son code via la RPC my_handoff_codes().
revoke select on public.orders from authenticated;
grant select (id, listing_id, seller_id, buyer_id, offer_thread_id, listing_title, listing_photo, buyer_name,
              item_price, delivery_fee, delivery, payment, status, status_changed_at, delivered_at, created_at,
              escrow_release_at, payment_reference)
  on public.orders to authenticated;

-- Messages : photo (chemin dans le bucket chat-photos) ; texte vide autorisé pour une photo.
alter table public.messages add column photo_url text;
alter table public.messages drop constraint if exists messages_text_check;
alter table public.messages add constraint messages_content check (
  char_length(text) <= 2000
  and (char_length(btrim(text)) >= 1 or photo_url is not null)
);
grant insert (photo_url) on public.messages to authenticated;

-- ===========================================================================
-- 3. Nouvelles tables : avis, signalements, blocages
-- ===========================================================================
create table public.reviews (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.orders (id) on delete cascade,
  reviewer_id uuid not null references public.profiles (id) on delete cascade,
  reviewee_id uuid not null references public.profiles (id) on delete cascade,
  rating      smallint not null check (rating between 1 and 5),
  comment     text not null default '' check (char_length(comment) <= 500),
  created_at  timestamptz not null default now(),
  constraint reviews_one_per_order unique (order_id),
  constraint reviews_parties check (reviewer_id <> reviewee_id)
);
create index reviews_reviewee_idx on public.reviews (reviewee_id, created_at desc);

create table public.reports (
  id               uuid primary key default gen_random_uuid(),
  reporter_id      uuid not null references public.profiles (id) on delete cascade,
  listing_id       uuid references public.listings (id) on delete set null,
  reported_user_id uuid references public.profiles (id) on delete cascade,
  reason           public.report_reason not null,
  details          text not null default '' check (char_length(details) <= 1000),
  status           text not null default 'open' check (status in ('open', 'reviewed', 'dismissed')),
  created_at       timestamptz not null default now(),
  constraint reports_target check (listing_id is not null or reported_user_id is not null),
  constraint reports_not_self check (reported_user_id is distinct from reporter_id)
);
create index reports_open_idx on public.reports (created_at desc) where status = 'open';

create table public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocks_not_self check (blocker_id <> blocked_id)
);
create index blocks_blocked_idx on public.blocks (blocked_id);

alter table public.reviews enable row level security;
alter table public.reports enable row level security;
alter table public.blocks  enable row level security;
revoke all on public.reviews, public.reports, public.blocks from anon, authenticated;

-- Avis : publics en lecture ; écriture via submit_review uniquement.
grant select on public.reviews to anon, authenticated;
create policy reviews_select_all on public.reviews
  for select to anon, authenticated using (true);

-- Signalements : je crée et je relis les miens ; la modération passe par service_role.
grant select on public.reports to authenticated;
grant insert (reporter_id, listing_id, reported_user_id, reason, details) on public.reports to authenticated;
create policy reports_select_own on public.reports
  for select to authenticated using (reporter_id = (select auth.uid()));
create policy reports_insert_own on public.reports
  for insert to authenticated with check (reporter_id = (select auth.uid()));

-- Blocages : strictement personnels.
grant select, insert, delete on public.blocks to authenticated;
create policy blocks_own on public.blocks
  for all to authenticated
  using (blocker_id = (select auth.uid())) with check (blocker_id = (select auth.uid()));

-- Blocage dans un sens ou dans l'autre (lisible malgré la RLS de blocks : security definer).
-- Utilisé dans des policies / vues security invoker : exécutable par authenticated.
create function private.is_blocked(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.blocks b
     where (b.blocker_id = p_a and b.blocked_id = p_b)
        or (b.blocker_id = p_b and b.blocked_id = p_a)
  );
$$;

-- ===========================================================================
-- 4. Vues
-- ===========================================================================

-- Catalogue public : + item_type, reserved_until, reserved_for (jamais min_offer).
-- Les annonces d'un membre bloqué (dans un sens ou dans l'autre) disparaissent.
-- Vue « definer » (propriétaire postgres) : elle lit blocks sans passer par la RLS.
-- Colonnes ajoutées en fin de liste (exigence de create or replace view).
create or replace view public.listings_public
with (security_barrier = true) as
select
  l.id, l.seller_id, l.title, l.description, l.price, l.old_price,
  l.size_type, l.size_value, l.size_label, l.gender, l.condition, l.brand, l.color,
  l.tags, l.city, l.district, l.photos, l.defect_comment, l.views_count,
  l.favorites_count, l.is_last_piece, l.negotiable, l.delivery_methods,
  l.status, l.created_at,
  l.item_type,
  case when l.reserved_until > now() then l.reserved_until end as reserved_until,
  case when l.reserved_until > now() then l.reserved_for end as reserved_for
from public.listings l
where l.status <> 'removed'
  and not exists (
    select 1 from public.blocks b
     where (b.blocker_id = (select auth.uid()) and b.blocked_id = l.seller_id)
        or (b.blocker_id = l.seller_id and b.blocked_id = (select auth.uid()))
  );

-- Conversations : masquées quand l'une des deux a bloqué l'autre.
create or replace view public.my_conversations
with (security_invoker = true) as
select
  c.id,
  c.listing_id,
  case when c.user_a = (select auth.uid()) then c.user_b else c.user_a end as other_user_id,
  c.last_message,
  c.last_message_at,
  case when c.user_a = (select auth.uid()) then c.unread_a else c.unread_b end as unread_count
from public.conversations c
where (select auth.uid()) in (c.user_a, c.user_b)
  and not private.is_blocked(c.user_a, c.user_b);

-- Plus de message (texte ou photo) entre deux membres bloqués ; la photo vient de mon dossier.
drop policy if exists messages_insert_own on public.messages;
create policy messages_insert_own on public.messages
  for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and (photo_url is null or photo_url like ((select auth.uid())::text || '/%'))
    and exists (
      select 1 from public.conversations c
      where c.id = messages.conversation_id
        and (select auth.uid()) in (c.user_a, c.user_b)
        and not private.is_blocked(c.user_a, c.user_b)
    )
  );

-- ===========================================================================
-- 5. Helpers internes
-- ===========================================================================

-- Code de remise à 4 chiffres (aléatoire cryptographique).
create function private.new_handoff_code()
returns text
language sql
volatile
set search_path = ''
as $$
  select lpad(((get_byte(b, 0) * 65536 + get_byte(b, 1) * 256 + get_byte(b, 2)) % 10000)::text, 4, '0')
    from (select extensions.gen_random_bytes(3) as b) as r;
$$;

-- "14:05" (Abidjan et Dakar sont en UTC+0)
create function private.hhmm(p_at timestamptz)
returns text
language sql
immutable
set search_path = ''
as $$
  select to_char(p_at at time zone 'UTC', 'HH24:MI');
$$;

create or replace function private.profile_json(p_id uuid)
returns jsonb
language sql stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.id, 'username', p.username, 'first_name', p.first_name,
    'city', p.city, 'district', p.district, 'avatar_url', p.avatar_url,
    'verified', p.verified, 'rating', p.rating, 'sales_count', p.sales_count,
    'response_time_minutes', p.response_time_minutes, 'created_at', p.created_at,
    'review_count', p.review_count
  )
  from public.profiles p where p.id = p_id;
$$;

-- ---------------------------------------------------------------------------
-- Machine à états (remplace la v1) :
--   • SHIPPED → DELIVERED : acheteuse (réception déclarée) ou system (confirm_handoff).
--     La vendeuse ne peut plus passer seule une commande à DELIVERED.
--   • SHIPPED : génère handoff_code ; DELIVERED : escrow_release_at = +72 h.
-- ---------------------------------------------------------------------------
create or replace function private.transition_order(
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
    when v_from in ('PAID', 'AWAITING_SHIPMENT') and p_to = 'CANCELLED' then p_actor in ('buyer', 'seller', 'system')
    when v_from = 'AWAITING_SHIPMENT' and p_to = 'SHIPPED'          then p_actor in ('seller', 'system')
    when v_from = 'SHIPPED'          and p_to = 'DELIVERED'         then p_actor in ('buyer', 'system')
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
    if v_from = 'SHIPPED' and p_to = 'DELIVERED' and p_actor = 'seller' then
      raise exception 'Saisis le code de remise de l’acheteuse pour confirmer la remise.' using hint = 'handoff_code_required';
    end if;
    raise exception 'Action impossible : la commande est « % ».', private.order_status_label(v_from)
      using hint = 'invalid_transition';
  end if;

  perform set_config('refripe.actor', p_actor, true);

  update public.orders
     set status = p_to,
         status_changed_at = now(),
         delivered_at = case when p_to = 'DELIVERED' then now() else delivered_at end,
         handoff_code = case when p_to = 'SHIPPED' then private.new_handoff_code() else handoff_code end,
         handoff_attempts = case when p_to = 'SHIPPED' then 0 else handoff_attempts end,
         escrow_release_at = case when p_to = 'DELIVERED' then now() + interval '72 hours' else escrow_release_at end
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
-- 6. Triggers
-- ===========================================================================

-- Offre acceptée (vendeuse, ou acheteuse qui accepte une contre-offre) → annonce réservée 2 h
-- pour cette acheteuse. Refusé si elle est déjà réservée pour une autre.
create function private.offer_threads_reserve()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  l public.listings;
begin
  select * into l from public.listings where id = new.listing_id for update;
  if l.reserved_for is not null and l.reserved_for <> new.buyer_id and l.reserved_until > now() then
    raise exception 'Article déjà réservé pour une autre acheteuse jusqu’à %.', private.hhmm(l.reserved_until)
      using hint = 'listing_reserved';
  end if;
  update public.listings
     set reserved_until = now() + interval '2 hours', reserved_for = new.buyer_id
   where id = new.listing_id;
  return null;
end;
$$;

create trigger offer_threads_reserve after update of status on public.offer_threads
  for each row
  when (new.status = 'accepted' and old.status is distinct from new.status)
  execute function private.offer_threads_reserve();

-- create_order : refusé pour les autres pendant la réservation. La réservation est conservée :
-- si l'acheteuse annule (changement de moyen de paiement) puis recommande, l'article l'attend encore.
create function private.orders_check_reservation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  l public.listings;
begin
  select * into l from public.listings where id = new.listing_id;
  if l.reserved_for is not null and l.reserved_for <> new.buyer_id and l.reserved_until > now() then
    raise exception 'Réservé pour une autre acheteuse jusqu’à %.', private.hhmm(l.reserved_until)
      using hint = 'listing_reserved';
  end if;
  if private.is_blocked(new.buyer_id, new.seller_id) then
    raise exception 'Tu ne peux pas acheter à ce membre.' using hint = 'blocked';
  end if;
  return new;
end;
$$;

create trigger orders_check_reservation before insert on public.orders
  for each row execute function private.orders_check_reservation();

-- Avis → profiles.rating (moyenne) et review_count.
create function private.reviews_refresh_rating()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if tg_op = 'DELETE' then v_id := old.reviewee_id; else v_id := new.reviewee_id; end if;
  update public.profiles p
     set rating = coalesce((select round(avg(r.rating)::numeric, 2)::double precision
                              from public.reviews r where r.reviewee_id = v_id), 0),
         review_count = (select count(*)::int from public.reviews r where r.reviewee_id = v_id),
         updated_at = now()
   where p.id = v_id;
  return null;
end;
$$;

create trigger reviews_refresh_rating after insert or delete on public.reviews
  for each row execute function private.reviews_refresh_rating();

-- Négociation : notifications avec les nouveaux types (remplace la v1).
create or replace function private.offer_rounds_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  t public.offer_threads;
  v_title text;
  v_seller text;
  v_buyer text;
begin
  select * into t from public.offer_threads where id = new.thread_id;
  select title into v_title from public.listings where id = t.listing_id;
  select username into v_seller from public.profiles where id = t.seller_id;
  select username into v_buyer from public.profiles where id = t.buyer_id;

  if new.party = 'seller' then
    if new.action = 'counter' then
      perform private.notify(t.buyer_id, 'counter_offer', 'Contre-offre reçue',
        v_seller || ' te propose ' || private.fcfa(new.amount) || ' pour « ' || v_title || ' »', t.listing_id);
    elsif new.action = 'accept' then
      perform private.notify(t.buyer_id, 'offer_accepted', 'Offre acceptée',
        v_seller || ' accepte ' || private.fcfa(new.amount) || ' pour « ' || v_title
          || ' ». Article réservé pour toi 2 h.', t.listing_id);
    else
      perform private.notify(t.buyer_id, 'offer_refused', 'Offre refusée',
        v_seller || ' a refusé ton offre pour « ' || v_title || ' »', t.listing_id);
    end if;
  else
    if new.action = 'accept' then
      perform private.notify(t.seller_id, 'offer_accepted', 'Contre-offre acceptée',
        v_buyer || ' accepte ' || private.fcfa(new.amount) || ' pour « ' || v_title || ' »', t.listing_id);
    else
      perform private.notify(t.seller_id, 'offer_received', 'Nouvelle offre',
        v_buyer || ' propose ' || private.fcfa(new.amount) || ' pour « ' || v_title || ' »', t.listing_id);
    end if;
  end if;
  return null;
end;
$$;

-- Messages : aperçu « Photo » pour un message photo (remplace la v1).
create or replace function private.messages_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.conversations;
  v_recipient uuid;
  v_sender text;
  v_prev public.messages;
  v_minutes integer;
  v_preview text := case when btrim(new.text) = '' and new.photo_url is not null then 'Photo'
                         else left(btrim(new.text), 140) end;
begin
  select * into c from public.conversations where id = new.conversation_id for update;
  v_recipient := case when c.user_a = new.sender_id then c.user_b else c.user_a end;

  select * into v_prev from public.messages
   where conversation_id = new.conversation_id and id <> new.id and created_at <= new.created_at
   order by created_at desc limit 1;
  if v_prev.id is not null and v_prev.sender_id <> new.sender_id then
    v_minutes := least(1440, greatest(0, (extract(epoch from new.created_at - v_prev.created_at) / 60)::int));
    update public.profiles
       set response_time_minutes = case
             when response_time_minutes is null then v_minutes
             else round(response_time_minutes * 0.8 + v_minutes * 0.2)::int
           end
     where id = new.sender_id;
  end if;

  update public.conversations
     set last_message = v_preview,
         last_message_at = new.created_at,
         last_sender_id = new.sender_id,
         unread_a = case when user_a = v_recipient then unread_a + 1 else unread_a end,
         unread_b = case when user_b = v_recipient then unread_b + 1 else unread_b end
   where id = c.id;

  select username into v_sender from public.profiles where id = new.sender_id;

  update public.notifications
     set body = v_sender || ' : ' || v_preview, created_at = now()
   where user_id = v_recipient and conversation_id = c.id and kind = 'message' and not read;
  if not found then
    perform private.notify(v_recipient, 'message', 'Nouveau message',
                           v_sender || ' : ' || v_preview, c.listing_id, null, c.id);
  end if;
  return null;
end;
$$;

-- Commandes : new_sale côté vendeuse au paiement, code de remise à l'expédition (remplace la v1).
create or replace function private.orders_after_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor text := coalesce(nullif(current_setting('refripe.actor', true), ''), 'system');
  v_me uuid := auth.uid();
  v_total text := private.fcfa(new.item_price + new.delivery_fee);
  v_item text := '« ' || new.listing_title || ' »';
  v_buyer_title text;
  v_buyer_body text;
  v_seller_title text;
  v_seller_body text;
  v_seller_kind public.notification_kind := 'order_update';
begin
  if v_actor not in ('buyer', 'seller', 'system') then
    v_actor := 'system';
  end if;
  insert into public.order_events (order_id, status, actor) values (new.id, new.status, v_actor);

  case new.status
    when 'AWAITING_SHIPMENT' then
      v_buyer_title := 'Paiement confirmé';
      v_buyer_body := 'Tes ' || v_total || ' pour ' || v_item || ' sont sécurisés en séquestre.';
      v_seller_title := 'Nouvelle vente';
      v_seller_body := v_item || ' a été payé (' || private.fcfa(new.item_price) || '). Prépare la remise.';
      v_seller_kind := 'new_sale';
    when 'SHIPPED' then
      v_buyer_title := 'Colis expédié';
      v_buyer_body := v_item || ' est en route. Montre ton code de remise à la réception.';
    when 'BUYER_VALIDATION' then
      v_buyer_title := 'Confirme la réception';
      v_buyer_body := v_item || ' t’a été remis. Sans réponse sous 72 h, les fonds seront libérés à la vendeuse.';
      v_seller_title := 'Remise confirmée';
      v_seller_body := v_item || ' a été remis. Les fonds seront libérés après confirmation (72 h max).';
    when 'COMPLETED' then
      v_buyer_title := 'Commande terminée';
      v_buyer_body := 'Merci ! ' || v_item || ' est à toi. Tu peux noter la vendeuse.';
      v_seller_title := 'Fonds libérés';
      v_seller_body := private.fcfa(new.item_price) || ' pour ' || v_item || ' sont libérés sur ton compte.';
    when 'CANCELLED' then
      v_buyer_title := 'Commande annulée';
      v_buyer_body := 'La commande de ' || v_item || ' a été annulée. Tout paiement prélevé est remboursé.';
      v_seller_title := 'Commande annulée';
      v_seller_body := 'La commande de ' || v_item || ' a été annulée. L’article est de nouveau en vente.';
    when 'DISPUTED' then
      v_buyer_title := 'Litige ouvert';
      v_buyer_body := 'Notre équipe médiation examine la commande de ' || v_item || ' (réponse sous 48 h).';
      v_seller_title := 'Litige ouvert';
      v_seller_body := 'Un litige a été signalé sur ' || v_item || '. Les fonds restent en séquestre.';
    when 'RETURN_PENDING' then
      v_seller_title := 'Demande de retour';
      v_seller_body := 'L’acheteuse souhaite retourner ' || v_item || '.';
      v_buyer_title := 'Retour en cours';
      v_buyer_body := 'Ton retour de ' || v_item || ' est enregistré.';
    when 'REFUNDED' then
      v_buyer_title := 'Remboursement effectué';
      v_buyer_body := v_total || ' recrédités sur ton compte ' || case new.payment when 'wave' then 'Wave' else 'Orange Money' end || '.';
    else
      null; -- PAID, DELIVERED : états intermédiaires enchaînés automatiquement
  end case;

  if v_buyer_title is not null and new.buyer_id is distinct from v_me then
    perform private.notify(new.buyer_id, 'order_update', v_buyer_title, v_buyer_body, new.listing_id, new.id);
  end if;
  if v_seller_title is not null and new.seller_id is distinct from v_me then
    perform private.notify(new.seller_id, v_seller_kind, v_seller_title, v_seller_body, new.listing_id, new.id);
  end if;
  return null;
end;
$$;

-- ===========================================================================
-- 7. RPC
-- ===========================================================================

-- Paiement confirmé (service_role) : + payment_reference (remplace la v1).
create or replace function public.confirm_payment(
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
    return o.status::text;
  end if;
  if p_amount is distinct from (o.item_price + o.delivery_fee) then
    raise exception 'amount_mismatch: attendu %, reçu %', o.item_price + o.delivery_fee, p_amount
      using hint = 'amount_mismatch';
  end if;

  update public.payments
     set state = 'succeeded', provider_ref = coalesce(p_provider_ref, provider_ref), updated_at = now()
   where order_id = p_order_id and provider = p_provider and state = 'pending';

  update public.orders
     set payment_reference = coalesce(nullif(p_provider_ref, ''), 'RF-' || upper(left(replace(p_order_id::text, '-', ''), 10)))
   where id = p_order_id;

  o := private.transition_order(p_order_id, 'PAID', 'system');
  return o.status::text;
end;
$$;

-- ---------------------------------------------------------------------------
-- Code de remise de mes achats expédiés (l'acheteuse seulement ; la vendeuse n'y a
-- jamais accès, cf. privilèges par colonne sur orders).
-- ---------------------------------------------------------------------------
create function public.my_handoff_codes(p_order_id uuid default null)
returns table (order_id uuid, handoff_code text)
language sql
stable
security definer
set search_path = ''
as $$
  select o.id, o.handoff_code
    from public.orders o
   where o.buyer_id = (select auth.uid())
     and o.handoff_code is not null
     and (p_order_id is null or o.id = p_order_id);
$$;

-- ---------------------------------------------------------------------------
-- Remise : la vendeuse (main propre) ou le système (relais, coursier via service_role)
-- saisit le code de l'acheteuse → DELIVERED → BUYER_VALIDATION, séquestre +72 h.
-- Retourne 'ok' | 'wrong_code' | 'locked' (pas d'exception sur un mauvais code : le
-- compteur d'essais doit être conservé ; 5 essais max).
-- ---------------------------------------------------------------------------
create function public.confirm_handoff(p_order_id uuid, p_code text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
  o public.orders;
begin
  select * into o from public.orders where id = p_order_id for update;
  if not found or (v_uid is not null and v_uid not in (o.buyer_id, o.seller_id)) then
    raise exception 'Commande introuvable.' using hint = 'not_found';
  end if;
  -- Sans utilisatrice : seul service_role (back-office relais / coursier) peut confirmer.
  if v_uid is null and v_role <> 'service_role' then
    raise exception 'Connecte-toi pour continuer.' using hint = 'not_authenticated';
  end if;
  if v_uid is not null and v_uid <> o.seller_id then
    raise exception 'Le code se donne à la vendeuse, au point relais ou au coursier.' using hint = 'forbidden';
  end if;
  if o.status <> 'SHIPPED' then
    raise exception 'Cette commande n’attend pas de remise (« % »).', private.order_status_label(o.status)
      using hint = 'invalid_transition';
  end if;
  if o.handoff_attempts >= 5 then
    return 'locked';
  end if;
  if o.handoff_code is null or regexp_replace(coalesce(p_code, ''), '[^0-9]', '', 'g') <> o.handoff_code then
    update public.orders set handoff_attempts = handoff_attempts + 1 where id = o.id;
    return case when o.handoff_attempts + 1 >= 5 then 'locked' else 'wrong_code' end;
  end if;

  perform private.transition_order(o.id, 'DELIVERED', 'system');
  return 'ok';
end;
$$;

-- ---------------------------------------------------------------------------
-- Avis : l'acheteuse note la vendeuse, une fois, après COMPLETED.
-- ---------------------------------------------------------------------------
create function public.submit_review(p_order_id uuid, p_rating integer, p_comment text default '')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
  o public.orders;
  r public.reviews;
begin
  select * into o from public.orders where id = p_order_id;
  if not found or v_uid not in (o.buyer_id, o.seller_id) then
    raise exception 'Commande introuvable.' using hint = 'not_found';
  end if;
  if o.buyer_id <> v_uid then
    raise exception 'Seule l’acheteuse peut noter la vendeuse.' using hint = 'forbidden';
  end if;
  if o.status <> 'COMPLETED' then
    raise exception 'Tu pourras noter la vendeuse une fois la commande terminée.' using hint = 'invalid_state';
  end if;
  if p_rating is null or p_rating not between 1 and 5 then
    raise exception 'Choisis une note de 1 à 5 étoiles.' using hint = 'invalid_rating';
  end if;

  insert into public.reviews (order_id, reviewer_id, reviewee_id, rating, comment)
  values (o.id, v_uid, o.seller_id, p_rating, left(btrim(coalesce(p_comment, '')), 500))
  on conflict (order_id) do nothing
  returning * into r;
  if r.id is null then
    raise exception 'Tu as déjà noté cette commande.' using hint = 'already_reviewed';
  end if;
  return to_jsonb(r);
end;
$$;

-- ---------------------------------------------------------------------------
-- Suppression de compte (App Store 5.1.1(v)). Appelée par l'Edge Function
-- `delete-account` avec le JWT de l'utilisatrice, qui supprime ensuite les fichiers
-- Storage et l'utilisateur auth (service_role : impossible depuis SQL).
-- Refusée tant que de l'argent est en séquestre ; les commandes passées sont
-- conservées (comptabilité) avec un profil anonymisé.
-- ---------------------------------------------------------------------------
create function public.delete_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
  r record;
begin
  if exists (
    select 1 from public.orders o
     where v_uid in (o.buyer_id, o.seller_id)
       and o.status in ('PAID', 'AWAITING_SHIPMENT', 'SHIPPED', 'DELIVERED', 'BUYER_VALIDATION', 'DISPUTED', 'RETURN_PENDING')
  ) then
    raise exception 'Termine tes commandes en cours avant de supprimer ton compte.' using hint = 'orders_in_progress';
  end if;

  for r in
    select o.id from public.orders o
     where v_uid in (o.buyer_id, o.seller_id) and o.status = 'PAYMENT_PENDING'
  loop
    perform private.transition_order(r.id, 'CANCELLED', 'system');
  end loop;

  update public.offer_threads set status = 'expired', updated_at = now()
   where status = 'pending' and v_uid in (buyer_id, seller_id);

  -- Annonces : supprimées si aucune commande ne les référence, sinon retirées.
  delete from public.listings l
   where l.seller_id = v_uid
     and not exists (select 1 from public.orders o where o.listing_id = l.id);
  update public.listings set status = 'removed', photos = '{}', reserved_until = null, reserved_for = null
   where seller_id = v_uid;

  update public.orders set buyer_name = 'Compte supprimé' where buyer_id = v_uid;

  delete from public.preferences where user_id = v_uid;
  delete from public.wishlist where user_id = v_uid;
  delete from public.swipes where user_id = v_uid;
  delete from public.blocks where blocker_id = v_uid or blocked_id = v_uid;
  delete from public.notifications where user_id = v_uid;
  delete from public.reports where reporter_id = v_uid;

  update public.profiles
     set username = 'supprime_' || left(replace(v_uid::text, '-', ''), 12),
         first_name = '',
         district = '',
         avatar_url = null,
         phone = null,
         verified = false,
         response_time_minutes = null,
         deleted_at = now()
   where id = v_uid;
end;
$$;

-- ---------------------------------------------------------------------------
-- Pile de swipe : identique à la v1 (les blocages sont filtrés par listings_public),
-- recréée pour suivre les nouvelles colonnes de la vue.
-- ---------------------------------------------------------------------------
create or replace function public.swipe_deck(p_limit integer default 40)
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
-- Séquestre : libération à escrow_release_at (remplace la v1).
-- ---------------------------------------------------------------------------
create or replace function private.release_escrow()
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
       and coalesce(escrow_release_at, coalesce(delivered_at, status_changed_at) + interval '72 hours') < now()
     order by escrow_release_at nulls first
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

-- ===========================================================================
-- 8. Storage : photos du chat
-- Bucket public (URL non devinables : <uid>/<conversation>/<uuid>.jpg) ; écriture
-- limitée au dossier de l'expéditrice. Choix assumé : pas d'URL signée à rafraîchir.
-- ===========================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-photos', 'chat-photos', true, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'image/heic'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create policy "chat-photos: lecture publique"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'chat-photos');

create policy "chat-photos: upload dans son dossier"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'chat-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "chat-photos: suppression dans son dossier"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'chat-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- ===========================================================================
-- 9. Privilèges d'exécution
-- ===========================================================================
revoke all on all functions in schema private from public, anon, authenticated;
revoke all on function
  public.my_handoff_codes(uuid),
  public.confirm_handoff(uuid, text),
  public.submit_review(uuid, integer, text),
  public.delete_account()
from public, anon, authenticated;

-- is_blocked est appelée par la policy messages_insert_own et la vue my_conversations
-- (security invoker) : authenticated doit pouvoir l'exécuter. Le schéma private
-- n'est pas exposé par PostgREST.
grant usage on schema private to authenticated;
grant execute on function private.is_blocked(uuid, uuid) to authenticated;

grant execute on function
  public.my_handoff_codes(uuid),
  public.confirm_handoff(uuid, text),
  public.submit_review(uuid, integer, text),
  public.delete_account()
to authenticated;

grant execute on function public.confirm_handoff(uuid, text) to service_role;
