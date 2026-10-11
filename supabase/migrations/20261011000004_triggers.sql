-- ReFripe — 4/6 : triggers (compteurs, baisse de prix, notifications, journal des commandes)
-- Toutes les fonctions trigger sont security definer (elles écrivent dans des
-- tables fermées aux clientes, ex. notifications) avec search_path vide.

-- ---------------------------------------------------------------------------
-- updated_at générique
-- ---------------------------------------------------------------------------
create function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_touch before update on public.profiles
  for each row execute function private.touch_updated_at();
create trigger preferences_touch before update on public.preferences
  for each row execute function private.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Annonces : valeurs dérivées à l'insertion (ville/quartier de la vendeuse)
-- ---------------------------------------------------------------------------
create function private.listings_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.profiles;
begin
  select * into p from public.profiles where id = new.seller_id;
  if not found then
    raise exception 'Complète ton profil avant de publier.' using hint = 'profile_required';
  end if;
  new.city := p.city;
  new.district := p.district;
  new.old_price := null;
  new.views_count := 0;
  new.favorites_count := 0;
  if coalesce(new.size_label, '') = '' then
    new.size_label := new.size_value;
  end if;
  if not new.negotiable then
    new.min_offer := null;
  end if;
  new.delivery_methods := array(select distinct unnest(new.delivery_methods));
  return new;
end;
$$;

create trigger listings_before_insert before insert on public.listings
  for each row execute function private.listings_before_insert();

-- ---------------------------------------------------------------------------
-- Annonces : baisse de prix -> old_price (cumulé), plancher cohérent
-- ---------------------------------------------------------------------------
create function private.listings_before_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  if new.price is distinct from old.price then
    if new.price < old.price then
      new.old_price := greatest(old.price, coalesce(old.old_price, 0));
    elsif new.old_price is not null and new.price >= new.old_price then
      new.old_price := null;
    end if;
  end if;
  if not new.negotiable then
    new.min_offer := null;
  elsif new.min_offer is not null and new.min_offer >= new.price then
    new.min_offer := null;
  end if;
  return new;
end;
$$;

create trigger listings_before_update before update on public.listings
  for each row execute function private.listings_before_update();

-- Notification price_drop à chaque personne qui a l'article en envie.
create function private.listings_after_price_drop()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.notifications (user_id, kind, title, body, listing_id)
  select w.user_id, 'price_drop', 'Baisse de prix sur une envie',
         '« ' || new.title || ' » passe à ' || private.fcfa(new.price)
           || ' (−' || private.fcfa(old.price - new.price) || ')',
         new.id
    from public.wishlist w
   where w.listing_id = new.id and w.user_id <> new.seller_id;
  return null;
end;
$$;

create trigger listings_after_price_drop after update of price on public.listings
  for each row
  when (new.price < old.price and new.status = 'active')
  execute function private.listings_after_price_drop();

-- Notification new_in_size : préférences catégorie + taille correspondantes.
create function private.listings_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status <> 'active' or coalesce(new.size_value, '') = '' then
    return null;
  end if;
  insert into public.notifications (user_id, kind, title, body, listing_id)
  select p.user_id, 'new_in_size', 'Nouvel article dans ta taille',
         '« ' || new.title || ' » (' || new.size_label || ') vient d’être publié'
           || case when new.district <> '' then ' à ' || new.district else '' end,
         new.id
    from public.preferences p
   where p.user_id <> new.seller_id
     and new.gender = any (p.categories)
     and p.sizes ->> new.size_type::text = new.size_value;
  return null;
end;
$$;

create trigger listings_after_insert after insert on public.listings
  for each row execute function private.listings_after_insert();

-- ---------------------------------------------------------------------------
-- Compteur de favoris
-- ---------------------------------------------------------------------------
create function private.wishlist_counter()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.listings set favorites_count = favorites_count + 1 where id = new.listing_id;
  elsif tg_op = 'DELETE' then
    update public.listings set favorites_count = greatest(favorites_count - 1, 0) where id = old.listing_id;
  end if;
  return null;
end;
$$;

create trigger wishlist_counter after insert or delete on public.wishlist
  for each row execute function private.wishlist_counter();

-- ---------------------------------------------------------------------------
-- Négociation : notification à l'autre partie à chaque tour
-- ---------------------------------------------------------------------------
create function private.offer_rounds_after_insert()
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
    perform private.notify(
      t.buyer_id, 'counter_offer',
      case new.action
        when 'counter' then 'Contre-offre reçue'
        when 'accept' then 'Offre acceptée'
        else 'Offre refusée'
      end,
      case new.action
        when 'counter' then v_seller || ' te propose ' || private.fcfa(new.amount) || ' pour « ' || v_title || ' »'
        when 'accept' then v_seller || ' accepte ' || private.fcfa(new.amount) || ' pour « ' || v_title || ' ». Tu peux acheter maintenant.'
        else v_seller || ' a refusé ton offre pour « ' || v_title || ' »'
      end,
      t.listing_id);
  else
    perform private.notify(
      t.seller_id, 'counter_offer',
      case new.action when 'accept' then 'Contre-offre acceptée' else 'Nouvelle offre' end,
      v_buyer || case new.action when 'accept' then ' accepte ' else ' propose ' end
        || private.fcfa(new.amount) || ' pour « ' || v_title || ' »',
      t.listing_id);
  end if;
  return null;
end;
$$;

create trigger offer_rounds_after_insert after insert on public.offer_rounds
  for each row execute function private.offer_rounds_after_insert();

-- ---------------------------------------------------------------------------
-- Messages : dernier message, non-lus, notification, temps de réponse
-- ---------------------------------------------------------------------------
create function private.messages_after_insert()
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
  v_preview text := left(btrim(new.text), 140);
begin
  select * into c from public.conversations where id = new.conversation_id for update;
  v_recipient := case when c.user_a = new.sender_id then c.user_b else c.user_a end;

  -- Temps de réponse : délai depuis le dernier message de l'autre partie
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

  -- Une seule notification non lue par conversation : on la rafraîchit.
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

create trigger messages_after_insert after insert on public.messages
  for each row execute function private.messages_after_insert();

-- ---------------------------------------------------------------------------
-- Commandes : journal order_events + notifications à chaque changement de statut
-- (l'acteur est transmis par private.transition_order via refripe.actor).
-- ---------------------------------------------------------------------------
create function private.orders_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.order_events (order_id, status, actor) values (new.id, new.status, 'buyer');
  return null;
end;
$$;

create trigger orders_after_insert after insert on public.orders
  for each row execute function private.orders_after_insert();

create function private.orders_after_status_change()
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
begin
  if v_actor not in ('buyer', 'seller', 'system') then
    v_actor := 'system';
  end if;
  insert into public.order_events (order_id, status, actor) values (new.id, new.status, v_actor);

  case new.status
    when 'AWAITING_SHIPMENT' then
      v_buyer_title := 'Paiement confirmé';
      v_buyer_body := 'Tes ' || v_total || ' pour ' || v_item || ' sont sécurisés en séquestre.';
      v_seller_title := 'Nouvelle vente !';
      v_seller_body := v_item || ' a été payé. Prépare le colis.';
    when 'SHIPPED' then
      v_buyer_title := 'Colis expédié';
      v_buyer_body := v_item || ' est en route.';
    when 'BUYER_VALIDATION' then
      v_buyer_title := 'Confirme la réception';
      v_buyer_body := v_item || ' est arrivé. Sans réponse sous 72 h, les fonds seront libérés à la vendeuse.';
      v_seller_title := 'Colis livré';
      v_seller_body := v_item || ' est arrivé. Les fonds seront libérés après confirmation (72 h max).';
    when 'COMPLETED' then
      v_buyer_title := 'Commande terminée';
      v_buyer_body := 'Merci ! ' || v_item || ' est à toi.';
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
    perform private.notify(new.seller_id, 'order_update', v_seller_title, v_seller_body, new.listing_id, new.id);
  end if;
  return null;
end;
$$;

create trigger orders_after_status_change after update of status on public.orders
  for each row
  when (new.status is distinct from old.status)
  execute function private.orders_after_status_change();

-- Les fonctions trigger ne doivent pas être appelables directement.
revoke all on all functions in schema private from public, anon, authenticated;
