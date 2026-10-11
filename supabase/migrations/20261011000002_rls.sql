-- ReFripe — 2/6 : Row Level Security et privilèges
-- Principe : RLS activée partout ; privilèges par table/colonne au plus juste.
-- Toutes les écritures « métier » (offres, commandes, statuts, compteurs) passent
-- par des RPC security definer (migration 3) : aucune policy INSERT/UPDATE n'est
-- ouverte sur ces tables.

alter table public.profiles       enable row level security;
alter table public.preferences    enable row level security;
alter table public.listings       enable row level security;
alter table public.listing_views  enable row level security;
alter table public.wishlist       enable row level security;
alter table public.swipes         enable row level security;
alter table public.offer_threads  enable row level security;
alter table public.offer_rounds   enable row level security;
alter table public.orders         enable row level security;
alter table public.order_events   enable row level security;
alter table public.payments       enable row level security;
alter table public.payment_events enable row level security;
alter table public.conversations  enable row level security;
alter table public.messages       enable row level security;
alter table public.notifications  enable row level security;
alter table public.drops          enable row level security;

-- On repart de zéro (Supabase accorde ALL par défaut à anon/authenticated).
revoke all on
  public.profiles, public.preferences, public.listings, public.listing_views,
  public.wishlist, public.swipes, public.offer_threads, public.offer_rounds,
  public.orders, public.order_events, public.payments, public.payment_events,
  public.conversations, public.messages, public.notifications, public.drops,
  public.listings_public, public.my_conversations
from anon, authenticated;

-- ---------------------------------------------------------------------------
-- profiles : lecture publique SANS phone ; mise à jour de son propre profil
-- (pas de verified / rating / sales_count, gérés côté serveur).
-- ---------------------------------------------------------------------------
grant select (id, username, first_name, city, district, avatar_url, verified, rating,
              sales_count, response_time_minutes, created_at)
  on public.profiles to anon, authenticated;
grant update (username, first_name, city, district, avatar_url)
  on public.profiles to authenticated;

create policy profiles_select_all on public.profiles
  for select to anon, authenticated using (true);
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
-- INSERT : via la RPC complete_signup uniquement.

-- ---------------------------------------------------------------------------
-- preferences : strictement personnelles.
-- ---------------------------------------------------------------------------
grant select, insert, update, delete on public.preferences to authenticated;
create policy preferences_own on public.preferences
  for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- listings : la table n'est lisible QUE par la vendeuse (min_offer compris).
-- Tout le monde lit le catalogue via la vue listings_public (sans min_offer).
-- ---------------------------------------------------------------------------
grant select on public.listings to authenticated;
grant insert (id, seller_id, title, description, price, size_type, size_value, size_label,
              gender, condition, brand, color, tags, photos, defect_comment,
              is_last_piece, negotiable, min_offer, delivery_methods)
  on public.listings to authenticated;
grant update (title, description, price, min_offer, negotiable, delivery_methods,
              defect_comment, tags, photos, brand, color, is_last_piece)
  on public.listings to authenticated;

create policy listings_select_own on public.listings
  for select to authenticated using (seller_id = (select auth.uid()));
create policy listings_insert_own on public.listings
  for insert to authenticated
  with check (
    seller_id = (select auth.uid())
    and status = 'active'
    -- les photos doivent venir du dossier storage de la vendeuse
    and not exists (
      select 1 from unnest(photos) as p(path)
      where p.path not like ((select auth.uid())::text || '/%')
    )
  );
create policy listings_update_own on public.listings
  for update to authenticated
  using (seller_id = (select auth.uid()) and status = 'active')
  with check (
    seller_id = (select auth.uid())
    and not exists (
      select 1 from unnest(photos) as p(path)
      where p.path not like ((select auth.uid())::text || '/%')
        and p.path not like 'http%'
    )
  );

grant select on public.listings_public to anon, authenticated;

-- listing_views : écriture via RPC record_view, lecture via seller_stats.
-- (aucune policy => aucun accès direct)

-- ---------------------------------------------------------------------------
-- wishlist / swipes : personnelles.
-- ---------------------------------------------------------------------------
grant select, insert, delete on public.wishlist to authenticated;
create policy wishlist_own on public.wishlist
  for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

grant select, insert, update, delete on public.swipes to authenticated;
create policy swipes_own on public.swipes
  for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Négociation : lecture par les deux parties, écriture via make_offer/respond_offer.
-- ---------------------------------------------------------------------------
grant select on public.offer_threads, public.offer_rounds to authenticated;
create policy offer_threads_parties on public.offer_threads
  for select to authenticated
  using ((select auth.uid()) in (buyer_id, seller_id));
create policy offer_rounds_parties on public.offer_rounds
  for select to authenticated
  using (exists (
    select 1 from public.offer_threads t
    where t.id = offer_rounds.thread_id and (select auth.uid()) in (t.buyer_id, t.seller_id)
  ));

-- ---------------------------------------------------------------------------
-- Commandes : lecture par l'acheteuse et la vendeuse, écriture via RPC.
-- ---------------------------------------------------------------------------
grant select on public.orders, public.order_events to authenticated;
create policy orders_parties on public.orders
  for select to authenticated
  using ((select auth.uid()) in (buyer_id, seller_id));
create policy order_events_parties on public.order_events
  for select to authenticated
  using (exists (
    select 1 from public.orders o
    where o.id = order_events.order_id and (select auth.uid()) in (o.buyer_id, o.seller_id)
  ));

-- payments / payment_events : service_role uniquement (aucune policy).

-- ---------------------------------------------------------------------------
-- Messagerie
-- ---------------------------------------------------------------------------
grant select on public.conversations to authenticated;
grant select on public.my_conversations to authenticated;
create policy conversations_parties on public.conversations
  for select to authenticated
  using ((select auth.uid()) in (user_a, user_b));

grant select on public.messages to authenticated;
grant insert (conversation_id, sender_id, text) on public.messages to authenticated;
create policy messages_select_parties on public.messages
  for select to authenticated
  using (exists (
    select 1 from public.conversations c
    where c.id = messages.conversation_id and (select auth.uid()) in (c.user_a, c.user_b)
  ));
create policy messages_insert_own on public.messages
  for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and exists (
      select 1 from public.conversations c
      where c.id = messages.conversation_id and (select auth.uid()) in (c.user_a, c.user_b)
    )
  );

-- ---------------------------------------------------------------------------
-- Notifications : on ne lit que les siennes et on ne peut modifier que `read`.
-- ---------------------------------------------------------------------------
grant select on public.notifications to authenticated;
grant update (read) on public.notifications to authenticated;
create policy notifications_select_own on public.notifications
  for select to authenticated using (user_id = (select auth.uid()));
create policy notifications_update_own on public.notifications
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Drops : publics en lecture.
-- ---------------------------------------------------------------------------
grant select on public.drops to anon, authenticated;
create policy drops_select_all on public.drops
  for select to anon, authenticated using (true);
