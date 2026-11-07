# ReFripe — v3 : nouvelle ergonomie (implémentation)

Source : l'audit ergonomique + benchmark Vinted (doc « ReFripe — Ergonomie et nouvelle interface ») et la maquette cliquable « ReFripe — Nouveau design » (11 écrans). La v2 (`docs/DESIGN.md` : SF, `RF.T`, sobriété) reste la base visuelle : **garder les SF Symbols, la barre d'onglets native, les boutons hibiscus, `RF.T` / `RF.C`**.

## v4 — thème (remplace les couleurs/polices ci-dessous)

- **Clair / sombre** : tous les tokens `RF.C` sont dynamiques. Choix dans Réglages › Apparence et à l'inscription (Système · Clair · Sombre), stocké sous `@AppStorage("appearanceMode")`, appliqué par `.preferredColorScheme` à la racine.
- **Couleurs** : fond blanc (`paper` #FFFFFF / bleu nuit #0B1630), surfaces #F4F5F7 / #15244A, cartes #FFFFFF / #13213F. Logo `Wordmark` : « Re » bleu #1F5FD6, « Fripe » orange #F26419. Actions principales orange (`accent` #CC4309), sélection bleue (`brandBlue`, `blueTint`). Plus de noir comme couleur d'action.
- **Polices** : DM Sans (interface, proche de Modern Era utilisée par Hinge) et Newsreader (grands titres, proche de Tiempos). Échelle compacte façon Vinted : corps 15, secondaire 13, méta 12, titres d'écran 30. Wordmark en Unbounded.
- **Textes** : quelques mots, ton humain (« Confirmation » plutôt que « Tout est OK, je confirme »). Pas de phrase d'explication sous les champs sauf nécessité.
- Pas de hex ni de `Color.white/.black` dans les features (sauf photos et pastilles de couleur d'article).

## Décisions prises (par défaut, modifiables)

- Onglets : **Accueil · Favoris · Vendre (+) · Messages · Profil**. (`Découvrir`→`Accueil`, `Envies`→`Favoris`, `Boîte`→`Messages`.)
- Profil = profil public + dressing **et** une courte liste « Mon activité » (Mes achats, Mes ventes, Versements, Statistiques, Aide). Réglages derrière la roue dentée.
- Notifications : derrière une cloche en haut d'Accueil (plus de segment Notifications).
- Swipe = mode secondaire « Coup de cœur » ouvert depuis Accueil ; la **grille** est l'écran par défaut.
- Commission ReFripe : non décidée → l'écran de vente affiche « Tu recevras X FCFA, avant commission ReFripe » ; aucun frais de protection côté acheteuse.
- Texte : `RF.C.accentText` pour le texte orange ; `RF.C.accent` pour les fonds de boutons (alias historiques `hibiscusText` / `hibiscus`).

## Contrat ajouté (Core, déjà écrit — ne pas renommer)

`ItemType`, `Listing.itemType / reservedUntil / reservedFor`, `UserProfile.reviewCount`, `ListingFilters.itemTypes / sizes / districts`, `Order.handoffCode / escrowReleaseAt / paymentReference`, `ChatMessage.photo`, `NotificationKind.offerReceived / offerAccepted / offerRefused / newSale`, `ListingDraft.itemType` (prix vide, négociable par défaut), `PaymentSession`, `Review`, `ReportReason`, et dans `Repository` : `startPayment`, `confirmHandoff`, `submitReview`, `reviews`, `sendPhoto`, `report`, `block`, `unblock`, `blockedUserIds`, `deleteAccount`.

## Règles métier nouvelles

- **Réservation 2 h** : quand la vendeuse accepte une offre (ou que l'acheteuse accepte une contre-offre), l'annonce est réservée 2 h pour cette acheteuse (`reservedUntil`, `reservedFor`) ; pendant ce temps, `createOrder` par quelqu'un d'autre est refusé (« Réservé pour une autre acheteuse jusqu'à HH:mm »). Après 2 h, l'annonce redevient libre.
- **Code de remise** : généré au passage à `SHIPPED`, visible uniquement par l'acheteuse ; `confirmHandoff(orderId, code)` (vendeuse en main propre, relais, coursier) → `DELIVERED` (puis `BUYER_VALIDATION`), `escrowReleaseAt` = +72 h. La vendeuse ne peut plus passer seule une commande à `DELIVERED`.
- **Paiement guidé** : `createOrder` → `PAYMENT_PENDING` ; `startPayment` → `PaymentSession` (Wave : `checkoutURL` à ouvrir avec `UIApplication.open` / SFSafariViewController, jamais WebView ; Orange Money : `ussdCode` ou URL) ; l'app interroge `order(id:)` toutes les 3 s jusqu'à `PAID`, puis affiche un reçu (`paymentReference`). En démo, le paiement passe à `PAID` ~4 s après `startPayment`.
- **Avis** : après `COMPLETED`, l'acheteuse note la vendeuse (1–5 + phrase) ; `UserProfile.rating`/`reviewCount` recalculés.
- **Modération** : signaler une annonce ou un membre, bloquer un membre (ses annonces disparaissent de mes flux, plus de messages) ; suppression de compte dans Réglages.
- **Recherche** : filtres type d'article, taille, commune ; puces rapides « Ma taille » (tailles des préférences), budget (« Moins de 2 000 / 5 000 / 10 000 »), « Près de moi » (quartier du profil) ; mes propres annonces exclues du flux ; plafond « 15 000 + » = sans limite.

## Écrans (maquette → code)

| Écran | Contenu attendu |
|---|---|
| Accueil | logo ReFripe (wordmark) + cloche ; recherche ; onglets Tout/Femme/Homme/Enfants/Bébés ; rangée : bouton Filtres fixe + puces Ma taille · Moins de 5 000 · Près de moi ; carte « Coup de cœur » → swipe ; titre « Dans ta taille, près de toi » + nombre ; grille 2 colonnes (photo 4:5, cœur, prix, « taille · quartier », titre) |
| Filtres | feuille : Type d'article, Taille (grille XS–XL ou pointures), Budget (puces), Commune (puces), État, Ouvert aux offres ; bouton « Afficher N articles » |
| Fiche | photo + retour/partage/cœur + « 1 / N » ; prix, titre, « Taille · État · Marque » ; bloc vert « Paiement protégé » ; ligne remise (quartier · main propre gratuite, relais 1 000, Yango 2 500) ; vendeuse (★ note (n avis) · répond en ~x min) ; description repliée ; barre fixe Faire une offre / Acheter ; menu ⋯ Signaler ; barre d'onglets masquée |
| Conversation | en-tête vendeuse + carte article + Acheter ; messages ; **offres en bulles** (ton offre n/3, contre-offre avec Accepter / Proposer, mention réservation 2 h) ; réponses rapides « Faire une offre », « On se voit où ? » ; bouton photo, champ, envoyer ; menu ⋯ Signaler / Bloquer |
| Paiement | article (prix négocié), Remise (radio, la moins chère présélectionnée), Payer avec (Wave / Orange Money + numéro masqué), récap Article / Remise / Total ; note verte ; bouton « Payer avec Wave » |
| Confirme dans Wave | logo, « Confirme le paiement dans Wave », montant, numéro débité, étapes (commande créée · en attente · reçu), bouton « Ouvrir Wave », « Payer avec Orange Money » ; passe seul au reçu |
| Messages | titre ; section « À faire » (confirmer réception avec délai restant, colis à expédier, offres à traiter) ; Conversations (avatar, dernier message, vignette article) |
| Suivi | bandeau vert argent bloqué + compte à rebours ; article ; 4 étapes Payé · Expédié · Remis · Terminé ; carte remise selon le mode (relais / Yango / main propre) avec **code** côté acheteuse ou **saisie du code** côté vendeuse ; « Tout est OK, je confirme » / « Signaler un problème » ; après : noter la vendeuse |
| Vendre | **4 étapes** : 1 Photos · 2 L'article (type, pour qui, taille, état, marque et couleur facultatives) · 3 Ton prix (champ vide, fourchette, Ouvert aux offres activé, offre minimum privée, « Tu recevras ») · 4 Remise + relecture → Publier ; **brouillon enregistré** (repris au prochain « Vendre ») |
| Profil | roue dentée ; avatar, pseudo + badge vérifié, lieu · ancienneté ; ★ note (n avis) · ventes · réponse ; Modifier / Partager ; Mon dressing (aperçu + Tout voir) ; Mon activité (Mes achats, Mes ventes, Versements, Statistiques, Aide sur WhatsApp) |

## Qui fait quoi (agents, fichiers)

- **Back** : `Data/` (Demo + Supabase + DTO), `supabase/` (nouvelle migration `20261103000001_v3.sql`, edge functions si besoin), `ReFripeTests/` (nouvelles règles), `Core/Catalog.swift` (libellés `ItemType`, puces budget, etc.), `Core/Theme.swift` (`hibiscusText`).
- **Accueil** : `App/` (onglets), `Core/Navigation.swift` (routes ; ajout seulement), `Features/Discover`, `Features/Wishlist` (→ Favoris), `Features/Product`, `Features/Notifications`.
- **Transactions** : `Features/Messages`, `Features/Offers`, `Features/Checkout`, `Features/Orders`, `Features/Inbox` (→ Messages avec « À faire »).
- **Compte & vente** : `Features/Profile`, `Features/Settings`, `Features/Dashboard`, `Features/Sell`, `Features/Onboarding` (guide : nouveaux noms d'onglets), `UI/` (composants partagés : `ReportSheet`, badge vérifié, etc. — signatures existantes inchangées), `ReFripeUITests/`.
