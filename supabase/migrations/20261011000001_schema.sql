-- ReFripe — 1/6 : schéma (enums, tables, index, vues)
-- Les enums reprennent exactement les rawValue Swift de ReFripe/Core/Models.swift.

create extension if not exists pgcrypto with schema extensions;

-- Schéma interne (non exposé par PostgREST) : helpers, machine à états, jobs cron.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to postgres, service_role;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type public.gender            as enum ('femme', 'homme', 'enfant', 'bebe');
create type public.item_condition    as enum ('new_with_tags', 'excellent', 'very_good', 'good', 'fair');
create type public.size_type         as enum ('haut', 'pantalon', 'chaussures', 'enfant', 'unique');
create type public.delivery_method   as enum ('relais', 'main_propre', 'yango');
create type public.payment_method    as enum ('wave', 'orange_money');
create type public.listing_status    as enum ('active', 'reserved', 'sold', 'removed');
create type public.offer_party       as enum ('buyer', 'seller');
create type public.offer_action      as enum ('offer', 'counter', 'accept', 'refuse');
create type public.offer_status      as enum ('pending', 'accepted', 'refused', 'expired');
create type public.order_status      as enum (
  'PAYMENT_PENDING', 'PAID', 'AWAITING_SHIPMENT', 'SHIPPED', 'DELIVERED',
  'BUYER_VALIDATION', 'COMPLETED', 'CANCELLED', 'DISPUTED', 'RETURN_PENDING', 'REFUNDED'
);
create type public.notification_kind as enum (
  'counter_offer', 'price_drop', 'new_in_size', 'message', 'streak', 'order_update'
);
create type public.payment_state     as enum ('pending', 'succeeded', 'failed');

-- ---------------------------------------------------------------------------
-- Profils (1:1 avec auth.users). `phone` n'est lisible que par service_role.
-- ---------------------------------------------------------------------------
create table public.profiles (
  id                    uuid primary key references auth.users (id) on delete cascade,
  username              text not null,
  first_name            text not null default '',
  city                  text not null default 'Abidjan',
  district              text not null default '',
  avatar_url            text,
  verified              boolean not null default false,
  rating                double precision not null default 0 check (rating between 0 and 5),
  sales_count           integer not null default 0 check (sales_count >= 0),
  response_time_minutes integer check (response_time_minutes >= 0),
  phone                 text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint profiles_username_format check (username ~ '^[A-Za-z0-9_.]{3,30}$'),
  constraint profiles_city check (city in ('Abidjan', 'Dakar'))
);
create unique index profiles_username_lower_key on public.profiles (lower(username));

-- Préférences privées (onboarding, gamification). `sizes` = {"haut":"M","pantalon":"38",...}
create table public.preferences (
  user_id               uuid primary key references public.profiles (id) on delete cascade,
  categories            public.gender[] not null default '{}',
  sizes                 jsonb not null default '{"haut":"M","pantalon":"38","chaussures":"40"}',
  brands                text[] not null default '{}',
  is_adult_confirmed    boolean not null default false,
  onboarding_completed  boolean not null default false,
  intro_guide_seen      boolean not null default false,
  swipe_coach_seen      boolean not null default false,
  streak_days           integer not null default 0 check (streak_days >= 0),
  last_active_day       timestamptz,
  updated_at            timestamptz not null default now(),
  constraint preferences_sizes_object check (jsonb_typeof(sizes) = 'object')
);
create index preferences_categories_idx on public.preferences using gin (categories);

-- ---------------------------------------------------------------------------
-- Annonces. `min_offer` est le plancher privé de la vendeuse : jamais exposé
-- aux autres (voir la vue listings_public et la policy SELECT propriétaire).
-- `size_value` = valeur brute ("M", "42", "4 ans") pour l'alerte new_in_size.
-- `photos` = chemins dans le bucket listing-photos ("<uid>/<listing>/0.jpg")
-- ou URL absolues (seed).
-- ---------------------------------------------------------------------------
create table public.listings (
  id               uuid primary key default gen_random_uuid(),
  seller_id        uuid not null references public.profiles (id) on delete cascade,
  title            text not null check (char_length(title) between 3 and 80),
  description      text not null default '' check (char_length(description) <= 2000),
  price            integer not null check (price between 100 and 10000000),
  old_price        integer check (old_price > 0),
  size_type        public.size_type not null,
  size_value       text not null default '',
  size_label       text not null default '',
  gender           public.gender not null,
  condition        public.item_condition not null,
  brand            text not null default '',
  color            text not null default '',
  tags             text[] not null default '{}',
  city             text not null default '',
  district         text not null default '',
  photos           text[] not null default '{}' check (cardinality(photos) <= 8),
  defect_comment   text check (char_length(defect_comment) <= 500),
  views_count      integer not null default 0,
  favorites_count  integer not null default 0,
  is_last_piece    boolean not null default false,
  negotiable       boolean not null default false,
  min_offer        integer,
  delivery_methods public.delivery_method[] not null default '{relais}' check (cardinality(delivery_methods) between 1 and 3),
  status           public.listing_status not null default 'active',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint listings_min_offer check (min_offer is null or (min_offer > 0 and min_offer < price))
);
create index listings_feed_idx   on public.listings (status, created_at desc);
create index listings_seller_idx on public.listings (seller_id, created_at desc);
create index listings_gender_idx on public.listings (gender) where status = 'active';

-- Vues d'annonces (journal, pour les stats vendeuse).
create table public.listing_views (
  id         bigint generated always as identity primary key,
  listing_id uuid not null references public.listings (id) on delete cascade,
  viewer_id  uuid references public.profiles (id) on delete set null,
  viewed_at  timestamptz not null default now()
);
create index listing_views_listing_idx on public.listing_views (listing_id, viewed_at desc);
create index listing_views_viewer_idx  on public.listing_views (viewer_id, listing_id, viewed_at desc);

create table public.wishlist (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  listing_id uuid not null references public.listings (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, listing_id)
);
create index wishlist_listing_idx on public.wishlist (listing_id);

create table public.swipes (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  listing_id uuid not null references public.listings (id) on delete cascade,
  liked      boolean not null,
  created_at timestamptz not null default now(),
  primary key (user_id, listing_id)
);

-- ---------------------------------------------------------------------------
-- Négociation : un fil par (annonce, acheteuse), 3 offres acheteuse max.
-- ---------------------------------------------------------------------------
create table public.offer_threads (
  id         uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings (id) on delete cascade,
  buyer_id   uuid not null references public.profiles (id) on delete cascade,
  seller_id  uuid not null references public.profiles (id) on delete cascade,
  status     public.offer_status not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint offer_threads_unique unique (listing_id, buyer_id),
  constraint offer_threads_parties check (buyer_id <> seller_id)
);
create index offer_threads_buyer_idx  on public.offer_threads (buyer_id, updated_at desc);
create index offer_threads_seller_idx on public.offer_threads (seller_id, updated_at desc);

create table public.offer_rounds (
  id         uuid primary key default gen_random_uuid(),
  thread_id  uuid not null references public.offer_threads (id) on delete cascade,
  party      public.offer_party not null,  -- OfferRound.by
  amount     integer not null check (amount > 0),
  action     public.offer_action not null,
  created_at timestamptz not null default clock_timestamp()
);
create index offer_rounds_thread_idx on public.offer_rounds (thread_id, created_at);

-- ---------------------------------------------------------------------------
-- Commandes & séquestre
-- ---------------------------------------------------------------------------
create table public.orders (
  id                uuid primary key default gen_random_uuid(),
  listing_id        uuid not null references public.listings (id) on delete restrict,
  seller_id         uuid not null references public.profiles (id) on delete restrict,
  buyer_id          uuid not null references public.profiles (id) on delete restrict,
  offer_thread_id   uuid references public.offer_threads (id) on delete set null,
  listing_title     text not null,
  listing_photo     text,
  buyer_name        text not null,
  item_price        integer not null check (item_price > 0),
  delivery_fee      integer not null check (delivery_fee >= 0),
  delivery          public.delivery_method not null,
  payment           public.payment_method not null,
  status            public.order_status not null default 'PAYMENT_PENDING',
  status_changed_at timestamptz not null default now(),
  delivered_at      timestamptz,
  created_at        timestamptz not null default now(),
  constraint orders_parties check (buyer_id <> seller_id)
);
create index orders_buyer_idx  on public.orders (buyer_id, created_at desc);
create index orders_seller_idx on public.orders (seller_id, created_at desc);
create index orders_status_idx on public.orders (status, status_changed_at);
-- Une seule commande « vivante » par annonce.
create unique index orders_one_open_per_listing on public.orders (listing_id)
  where status not in ('CANCELLED', 'REFUNDED');

create table public.order_events (
  id         bigint generated always as identity primary key,
  order_id   uuid not null references public.orders (id) on delete cascade,
  status     public.order_status not null,
  actor      text not null default 'system' check (actor in ('buyer', 'seller', 'system')),
  created_at timestamptz not null default clock_timestamp()
);
create index order_events_order_idx on public.order_events (order_id, id);

-- Sessions de paiement (service_role uniquement).
create table public.payments (
  id            uuid primary key default gen_random_uuid(),
  order_id      uuid not null references public.orders (id) on delete cascade,
  provider      text not null,           -- 'sandbox' | 'wave' | 'orange_money'
  amount        integer not null check (amount > 0),
  currency      text not null default 'XOF',
  state         public.payment_state not null default 'pending',
  session_id    text,
  provider_ref  text,
  checkout_url  text,
  notif_token   text,
  raw           jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index payments_order_idx on public.payments (order_id);
create unique index payments_session_key on public.payments (provider, session_id) where session_id is not null;

-- Journal des webhooks reçus (idempotence).
create table public.payment_events (
  id          bigint generated always as identity primary key,
  provider    text not null,
  event_id    text not null,
  order_id    uuid references public.orders (id) on delete set null,
  payload     jsonb not null,
  received_at timestamptz not null default now(),
  constraint payment_events_unique unique (provider, event_id)
);

-- ---------------------------------------------------------------------------
-- Messagerie : conversation à deux, rattachée (ou non) à une annonce.
-- user_a < user_b (ordre canonique) ; un compteur de non-lus par participant.
-- ---------------------------------------------------------------------------
create table public.conversations (
  id              uuid primary key default gen_random_uuid(),
  listing_id      uuid references public.listings (id) on delete set null,
  user_a          uuid not null references public.profiles (id) on delete cascade,
  user_b          uuid not null references public.profiles (id) on delete cascade,
  last_message    text not null default '',
  last_message_at timestamptz not null default now(),
  last_sender_id  uuid,
  unread_a        integer not null default 0,
  unread_b        integer not null default 0,
  created_at      timestamptz not null default now(),
  constraint conversations_order check (user_a < user_b)
);
create unique index conversations_pair_listing_key
  on public.conversations (user_a, user_b, coalesce(listing_id, '00000000-0000-0000-0000-000000000000'::uuid));
create index conversations_user_b_idx on public.conversations (user_b);

create table public.messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id       uuid not null references public.profiles (id) on delete cascade,
  text            text not null check (char_length(btrim(text)) between 1 and 2000),
  created_at      timestamptz not null default clock_timestamp()
);
create index messages_conversation_idx on public.messages (conversation_id, created_at);

-- ---------------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------------
create table public.notifications (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles (id) on delete cascade,
  kind            public.notification_kind not null,
  title           text not null,
  body            text not null default '',
  read            boolean not null default false,
  listing_id      uuid references public.listings (id) on delete set null,
  order_id        uuid references public.orders (id) on delete set null,
  conversation_id uuid references public.conversations (id) on delete set null,
  created_at      timestamptz not null default now()
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);
create index notifications_unread_idx on public.notifications (user_id) where not read;

-- ---------------------------------------------------------------------------
-- Drops (« nouveaux arrivages ») : le prochain créneau est affiché en compte à rebours.
-- ---------------------------------------------------------------------------
create table public.drops (
  id         uuid primary key default gen_random_uuid(),
  starts_at  timestamptz not null unique,
  title      text not null default 'Nouveaux arrivages',
  seller_id  uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Vues
-- ---------------------------------------------------------------------------

-- Catalogue public : toutes les colonnes SAUF min_offer, annonces non retirées.
-- Vue volontairement « definer » (security_invoker = false, propriétaire postgres) :
-- la table listings n'autorise le SELECT qu'à la vendeuse, cette vue est la seule
-- porte d'entrée publique et elle n'expose pas min_offer.
create view public.listings_public
with (security_barrier = true) as
select
  l.id, l.seller_id, l.title, l.description, l.price, l.old_price,
  l.size_type, l.size_value, l.size_label, l.gender, l.condition, l.brand, l.color,
  l.tags, l.city, l.district, l.photos, l.defect_comment, l.views_count,
  l.favorites_count, l.is_last_piece, l.negotiable, l.delivery_methods,
  l.status, l.created_at
from public.listings l
where l.status <> 'removed';

-- Conversations vues depuis l'utilisatrice connectée (otherUserId / unreadCount).
create view public.my_conversations
with (security_invoker = true) as
select
  c.id,
  c.listing_id,
  case when c.user_a = (select auth.uid()) then c.user_b else c.user_a end as other_user_id,
  c.last_message,
  c.last_message_at,
  case when c.user_a = (select auth.uid()) then c.unread_a else c.unread_b end as unread_count
from public.conversations c
where (select auth.uid()) in (c.user_a, c.user_b);
