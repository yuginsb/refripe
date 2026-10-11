-- ReFripe — données de démo pour le développement local (`supabase db reset`).
-- NE PAS exécuter en production.
--
-- Connexion locale sans SMS : les numéros ci-dessous ont un code OTP fixe
-- (voir [auth.sms.test_otp] dans config.toml), ex. +225 07 00 00 00 01 / 123456.
-- Les écritures « métier » passent par les vraies RPC en simulant auth.uid()
-- via request.jwt.claim.sub, pour exercer triggers et machine à états.

-- ---------------------------------------------------------------------------
-- Utilisatrices (auth.users + profiles)
-- ---------------------------------------------------------------------------
insert into auth.users (
  instance_id, id, aud, role, phone, phone_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.phone, now(),
       '{"provider":"phone","providers":["phone"]}', '{}', now() - u.age, now(),
       '', '', '', ''
from (values
  ('a0000000-0000-4000-8000-000000000001'::uuid, '2250700000001', interval '8 months'),
  ('a0000000-0000-4000-8000-000000000002'::uuid, '2250700000002', interval '2 months'),
  ('a0000000-0000-4000-8000-000000000003'::uuid, '2250700000003', interval '12 months'),
  ('a0000000-0000-4000-8000-000000000004'::uuid, '221770000004',  interval '5 months'),
  ('a0000000-0000-4000-8000-000000000005'::uuid, '221770000005',  interval '11 months'),
  ('a0000000-0000-4000-8000-000000000006'::uuid, '2250700000006', interval '1 month')
) as u(id, phone, age)
on conflict (id) do nothing;

-- Identités « phone » (requises par GoTrue pour la connexion OTP des comptes du seed)
insert into auth.identities (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), u.id::text, u.id,
       jsonb_build_object('sub', u.id::text, 'phone', u.phone, 'phone_verified', true),
       'phone', now(), now(), now()
from auth.users u
where u.id::text like 'a0000000-0000-4000-8000-%'
  and not exists (select 1 from auth.identities i where i.user_id = u.id and i.provider = 'phone');

insert into public.profiles (id, username, first_name, city, district, verified, rating, sales_count,
                             response_time_minutes, phone, created_at)
values
  ('a0000000-0000-4000-8000-000000000001', 'Awa_Style225',   'Awa',    'Abidjan', 'Cocody',   true,  4.8, 127, 10, '2250700000001', now() - interval '8 months'),
  ('a0000000-0000-4000-8000-000000000002', 'Karim_Fripe',    'Karim',  'Abidjan', 'Plateau',  false, 4.4, 31,  45, '2250700000002', now() - interval '2 months'),
  ('a0000000-0000-4000-8000-000000000003', 'SneakDak',       'Moussa', 'Abidjan', 'Yopougon', true,  4.9, 340, 8,  '2250700000003', now() - interval '12 months'),
  ('a0000000-0000-4000-8000-000000000004', 'Fatou_Elegance', 'Fatou',  'Dakar',   'Plateau',  true,  5.0, 58,  20, '221770000004',  now() - interval '5 months'),
  ('a0000000-0000-4000-8000-000000000005', 'SecondLook.sn',  'Ndeye',  'Dakar',   'Almadies', true,  4.7, 212, 30, '221770000005',  now() - interval '11 months'),
  ('a0000000-0000-4000-8000-000000000006', 'Aicha_225',      'Aïcha',  'Abidjan', 'Marcory',  false, 0,   0,   null,'2250700000006', now() - interval '1 month')
on conflict (id) do nothing;

insert into public.preferences (user_id, categories, sizes, brands, is_adult_confirmed, onboarding_completed,
                                intro_guide_seen, swipe_coach_seen, streak_days, last_active_day)
values
  ('a0000000-0000-4000-8000-000000000001', '{femme,enfant}', '{"haut":"M","pantalon":"38","chaussures":"40"}', '{"Wax local",Zara}', true, true, true, true, 4, now() - interval '1 day'),
  ('a0000000-0000-4000-8000-000000000006', '{femme}',        '{"haut":"M","pantalon":"38","chaussures":"39"}', '{Vintage}',          true, true, true, false, 1, now() - interval '1 day')
on conflict (user_id) do nothing;

-- ---------------------------------------------------------------------------
-- Annonces (les 9 articles de la maquette). Photos : placeholders neutres.
-- ---------------------------------------------------------------------------
insert into public.listings (id, seller_id, title, description, price, size_type, size_value, size_label, gender,
                             condition, brand, color, tags, photos, is_last_piece, negotiable, min_offer,
                             delivery_methods, created_at)
values
  ('b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001',
   'Robe wax imprimé, motif Ankara',
   'Robe en pagne wax authentique, coupe cintrée, portée 3 fois seulement. Fermeture éclair dos en bon état. Idéale pour une cérémonie ou une sortie.',
   4500, 'haut', 'M', 'Taille M', 'femme', 'very_good', 'Wax local', 'Multicolore', '{Wax,Cérémonie,Coton}',
   '{https://placehold.co/600x800/F3EDE4/8A7F72/png?text=Robe+wax}', false, true, 3500, '{relais,main_propre}', now() - interval '3 days'),
  ('b0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000002',
   'Chemise vintage à carreaux',
   'Chemise en flanelle, léger bouloché sur une manche mais aucune tache. Parfaite pour un look décontracté.',
   2000, 'haut', 'L', 'Taille L', 'homme', 'good', 'Vintage', 'Bleu', '{Vintage,Homme}',
   '{https://placehold.co/600x800/F3EDE4/8A7F72/png?text=Chemise}', false, false, null, '{main_propre}', now() - interval '20 days'),
  ('b0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000003',
   'Baskets Nike Air',
   'Semelle encore marquée, quelques traces d’usure sur le talon, cuir nettoyé récemment.',
   8000, 'chaussures', '42', 'Pointure 42', 'homme', 'good', 'Nike', 'Blanc', '{Sport,Nike}',
   '{https://placehold.co/600x800/F3EDE4/8A7F72/png?text=Baskets}', true, true, 6000, '{relais,main_propre,yango}', now() - interval '6 days'),
  ('b0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000004',
   'Boubou traditionnel brodé',
   'Boubou brodé main, porté une seule fois pour un mariage. Tissu bazin riche.',
   12000, 'unique', 'Taille unique', 'Taille unique', 'femme', 'excellent', 'Bazin', 'Blanc', '{Bazin,Mariage}',
   '{https://placehold.co/600x800/F3EDE4/8A7F72/png?text=Boubou}', false, true, 8000, '{relais,yango}', now() - interval '16 days'),
  ('b0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000001',
   'Jean mom fit taille haute',
   'Denim épais, coupe mom fit tendance, taille haute confortable.',
   3000, 'pantalon', '38', 'Taille 38', 'femme', 'very_good', 'Sans marque précise', 'Bleu', '{Denim,Femme}',
   '{https://placehold.co/600x800/F3EDE4/8A7F72/png?text=Jean}', false, false, null, '{relais,main_propre}', now() - interval '5 days'),
  ('b0000000-0000-4000-8000-000000000006', 'a0000000-0000-4000-8000-000000000005',
   'Sac à main cuir vintage',
   'Cuir véritable, patine du temps qui donne du caractère, fermoir en bon état.',
   6500, 'unique', 'Taille unique', 'Taille unique', 'femme', 'good', 'Vintage', 'Marron', '{Cuir,Accessoire}',
   '{https://placehold.co/600x800/F3EDE4/8A7F72/png?text=Sac}', false, true, 5000, '{relais,main_propre,yango}', now() - interval '9 days'),
  ('b0000000-0000-4000-8000-000000000007', 'a0000000-0000-4000-8000-000000000001',
   'Robe en wax pour fille, 4 ans',
   'Petite robe en pagne wax, portée pour deux baptêmes. Coupe évasée, confortable pour jouer. Aucune tache, couleurs encore vives.',
   2500, 'enfant', '4 ans', '4 ans', 'enfant', 'very_good', 'Wax local', 'Multicolore', '{Wax,Fille}',
   '{}', false, true, 1800, '{relais,main_propre}', now() - interval '2 days'),
  ('b0000000-0000-4000-8000-000000000008', 'a0000000-0000-4000-8000-000000000002',
   'Ensemble t-shirt et short, 6 ans',
   'Ensemble coton pour garçon. Le t-shirt a légèrement passé au lavage, le short est comme neuf. Idéal pour l’école.',
   1500, 'enfant', '6 ans', '6 ans', 'enfant', 'good', 'Sans marque précise', 'Rouge', '{Coton,Garçon}',
   '{}', false, false, null, '{main_propre}', now() - interval '1 day'),
  ('b0000000-0000-4000-8000-000000000009', 'a0000000-0000-4000-8000-000000000004',
   'Pyjama bébé et chaussons, 0-3 mois',
   'Pyjama en coton doux porté trois semaines, mon bébé a grandi trop vite. Lavé et repassé, vendu avec les chaussons assortis.',
   2000, 'enfant', '0-3 mois', '0-3 mois', 'bebe', 'excellent', 'Sans marque précise', 'Jaune', '{Coton,Bébé}',
   '{}', false, true, 1500, '{relais,yango}', now() - interval '4 hours')
on conflict (id) do nothing;

-- Compteurs de vues de la maquette
update public.listings l set views_count = v.n
from (values
  ('b0000000-0000-4000-8000-000000000001'::uuid, 132), ('b0000000-0000-4000-8000-000000000002'::uuid, 54),
  ('b0000000-0000-4000-8000-000000000003'::uuid, 301), ('b0000000-0000-4000-8000-000000000004'::uuid, 214),
  ('b0000000-0000-4000-8000-000000000005'::uuid, 76),  ('b0000000-0000-4000-8000-000000000006'::uuid, 98),
  ('b0000000-0000-4000-8000-000000000007'::uuid, 88),  ('b0000000-0000-4000-8000-000000000008'::uuid, 41),
  ('b0000000-0000-4000-8000-000000000009'::uuid, 63)
) as v(id, n)
where l.id = v.id;

-- Quelques vues journalisées cette semaine sur les annonces d'Awa (graphique du dashboard)
insert into public.listing_views (listing_id, viewer_id, viewed_at)
select (array['b0000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000005',
              'b0000000-0000-4000-8000-000000000007'])[1 + (g % 3)]::uuid,
       'a0000000-0000-4000-8000-000000000006',
       now() - (g * interval '37 minutes')
from generate_series(1, 120) as g;

-- ---------------------------------------------------------------------------
-- Envies d'Awa (2, 4) puis baisse du Boubou 12 000 -> 10 000 : déclenche
-- old_price et la notification price_drop.
-- ---------------------------------------------------------------------------
insert into public.wishlist (user_id, listing_id) values
  ('a0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000002'),
  ('a0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000004'),
  ('a0000000-0000-4000-8000-000000000006', 'b0000000-0000-4000-8000-000000000001')
on conflict do nothing;

update public.listings set price = 10000 where id = 'b0000000-0000-4000-8000-000000000004';

-- ---------------------------------------------------------------------------
-- Scénarios via les RPC (auth.uid() simulé)
-- ---------------------------------------------------------------------------
do $$
declare
  awa    constant uuid := 'a0000000-0000-4000-8000-000000000001';
  karim  constant uuid := 'a0000000-0000-4000-8000-000000000002';
  sneak  constant uuid := 'a0000000-0000-4000-8000-000000000003';
  fatou  constant uuid := 'a0000000-0000-4000-8000-000000000004';
  secondlook constant uuid := 'a0000000-0000-4000-8000-000000000005';
  aicha  constant uuid := 'a0000000-0000-4000-8000-000000000006';
  v_thread uuid;
  v_order uuid;
  v_conv uuid;
begin
  -- Négociation Awa -> Boubou (Fatou) : 8 500, contre-offre 9 000 acceptée, commande livrée
  perform set_config('request.jwt.claim.sub', awa::text, true);
  v_thread := public.make_offer('b0000000-0000-4000-8000-000000000004', 8500);
  perform set_config('request.jwt.claim.sub', fatou::text, true);
  perform public.respond_offer(v_thread, 'counter', 9000);
  perform set_config('request.jwt.claim.sub', awa::text, true);
  perform public.make_offer('b0000000-0000-4000-8000-000000000004', 9000); -- = acceptation
  v_order := public.create_order('b0000000-0000-4000-8000-000000000004', 'yango', 'wave');
  perform set_config('request.jwt.claim.sub', '', true);
  perform public.confirm_payment(v_order, 9000 + 2500, 'sandbox', 'seed');
  perform set_config('request.jwt.claim.sub', fatou::text, true);
  perform public.advance_order(v_order, 'SHIPPED');
  perform public.advance_order(v_order, 'DELIVERED');  -- -> BUYER_VALIDATION

  -- Ventes d'Awa : Robe wax achetée par Aïcha (à expédier)
  perform set_config('request.jwt.claim.sub', aicha::text, true);
  v_order := public.create_order('b0000000-0000-4000-8000-000000000001', 'relais', 'orange_money');
  perform set_config('request.jwt.claim.sub', '', true);
  perform public.confirm_payment(v_order, 4500 + 1000, 'sandbox', 'seed');

  -- Jean mom fit acheté par Karim (expédié)
  perform set_config('request.jwt.claim.sub', karim::text, true);
  v_order := public.create_order('b0000000-0000-4000-8000-000000000005', 'relais', 'wave');
  perform set_config('request.jwt.claim.sub', '', true);
  perform public.confirm_payment(v_order, 3000 + 1000, 'sandbox', 'seed');
  perform set_config('request.jwt.claim.sub', awa::text, true);
  perform public.advance_order(v_order, 'SHIPPED');

  -- Historique d'Awa acheteuse : Baskets (SneakDak) terminée
  perform set_config('request.jwt.claim.sub', awa::text, true);
  v_order := public.create_order('b0000000-0000-4000-8000-000000000003', 'relais', 'wave');
  perform set_config('request.jwt.claim.sub', '', true);
  perform public.confirm_payment(v_order, 8000 + 1000, 'sandbox', 'seed');
  perform set_config('request.jwt.claim.sub', sneak::text, true);
  perform public.advance_order(v_order, 'SHIPPED');
  perform public.advance_order(v_order, 'DELIVERED');
  perform set_config('request.jwt.claim.sub', awa::text, true);
  perform public.advance_order(v_order, 'COMPLETED');

  -- Conversation Aïcha <-> Awa sur la robe wax
  perform set_config('request.jwt.claim.sub', aicha::text, true);
  v_conv := public.get_or_create_conversation(awa, 'b0000000-0000-4000-8000-000000000001');
  insert into public.messages (conversation_id, sender_id, text) values
    (v_conv, aicha, 'Bonjour, la robe wax est toujours dispo ?');
  perform set_config('request.jwt.claim.sub', awa::text, true);
  insert into public.messages (conversation_id, sender_id, text) values
    (v_conv, awa, 'Oui toujours dispo');
  perform set_config('request.jwt.claim.sub', aicha::text, true);
  insert into public.messages (conversation_id, sender_id, text) values
    (v_conv, aicha, 'Dernier prix ?');
  perform set_config('request.jwt.claim.sub', awa::text, true);
  insert into public.messages (conversation_id, sender_id, text) values
    (v_conv, awa, '4000 possible si vous récupérez à Cocody, sinon 4500 livrée');

  -- Offre en attente sur le sac (SecondLook.sn) par Aïcha
  perform set_config('request.jwt.claim.sub', aicha::text, true);
  perform public.make_offer('b0000000-0000-4000-8000-000000000006', 5000);

  perform set_config('request.jwt.claim.sub', '', true);
end;
$$;
