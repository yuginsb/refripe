# ReFripe — design system v2 (refonte « moins vibe-codée »)

Retours d'Eugène sur le rendu v1 :
1. changer la police ; 2. changer la police des chiffres ; 3. réduire les textes ;
4. Profil ne doit contenir que ce qui concerne le profil, tout le reste réorganisé comme dans les apps du genre (Vinted, Depop, Leboncoin) ;
5. qu'on sente moins le côté « vibe codé ».

L'objectif : une app qui ressemble à une vraie app iOS de marketplace, sobre et native, avec l'identité ReFripe (palette, logo) en touches, pas partout.

## 1. Typographie

- **San Francisco partout**, via les styles natifs `RF.T` (Core/Theme.swift) → Dynamic Type gratuit.
  | Usage | Token |
  |---|---|
  | Titre d'écran racine | titre de navigation natif (`.navigationTitle`, `.large` sur les racines d'onglet, `.inline` ailleurs) |
  | Titre dans le contenu (rare) | `RF.T.title` / `RF.T.title3` |
  | Titre de ligne, de carte, nom d'article | `RF.T.headline` ou `RF.T.subheadline.weight(.semibold)` |
  | Texte courant | `RF.T.body` / `RF.T.callout` |
  | Texte secondaire d'une ligne | `RF.T.subheadline` + `RF.C.textDim` |
  | Métadonnées (quartier, date, taille) | `RF.T.footnote` + `RF.C.textDim` |
  | Pastilles, compteurs | `RF.T.caption` (avec parcimonie) |
  | Boutons | `RF.T.button` |
- **Chiffres** : SF à chasse fixe, `RF.T.price(...)` pour les montants, `RF.T.number(...)` pour les stats. Plus jamais de police mono (IBM Plex Mono supprimée).
- **Unbounded** uniquement pour le logo « ReFripe » (`RF.T.brand`) : splash et écran d'accueil de l'inscription. Jamais pour un titre, un bouton ou un prix.
- `RF.F.*` est un reliquat : chaque fichier touché doit être migré vers `RF.T`. À la fin, plus aucun `RF.F.` dans l'app.
- Pas de texte en MAJUSCULES espacées (les « SectionLabel » mono) : en-têtes de section en casse normale, `RF.T.footnote.weight(.semibold)` + `textDim`, ou en-têtes natifs de `List`/`Form`.
- Taille minimale de fait : `caption` (12 pt). Rien en dessous.

## 2. Textes (réduire)

- Une idée par écran, une phrase max sous un titre. Supprimer les paragraphes explicatifs, les « astuces » et les phrases de réassurance répétées. Si une explication est vraiment utile, une ligne en `footnote` ou une feuille d'info derrière un bouton ⓘ.
- Libellés courts : « Faire une offre », « Acheter », « Payer », « Publier ». Pas de phrases dans les boutons, pas de montant dans le libellé si le total est déjà affiché à côté.
- Pas de point d'exclamation, pas d'emoji, pas de ton « coach ». Tutoiement conservé.
- Les compteurs « vues aujourd'hui », « dernière pièce » : un seul signal par carte au maximum.

## 3. Sobriété visuelle (anti « vibe codé »)

- **Une seule couleur d'action par écran** : hibiscus pour l'action principale et les états sélectionnés. Vert `money` uniquement pour l'argent sécurisé / succès de paiement. Marigold seulement pour le logo et la note (étoiles). Pas de dégradés, pas de motifs décoratifs, pas d'ombres portées colorées, pas de lueurs.
- Fond `RF.C.paper` ; cartes `RF.C.card` (blanc) avec rayon 12, sans bordure ou avec hairline `RF.C.line`, pas d'ombre (sauf la carte du swipe).
- **Composants natifs d'abord** : `List`/`Form` `.insetGrouped` pour réglages, listes de commandes, menus ; `Picker(.segmented)` pour les bascules ; `Toggle`, `Stepper`, `Menu`, `confirmationDialog`, `ShareLink`, `.searchable`, `.sheet` + `presentationDetents`, `ContentUnavailableView` pour les états vides. Teinter (`.tint(RF.C.hibiscus)`) plutôt que redessiner.
- Icônes SF Symbols en poids régulier, couleur `text`/`textDim` ; pas de pastille de couleur derrière chaque icône.
- Badges : au maximum un par carte (ex. « Prix en baisse »), petits, `caption`.
- Espacements sur une grille de 8 : marges 16, entre sections 24, dans une carte 12.
- Pas de bannières « Mode démo » dans le contenu : l'info démo va dans Réglages (pied de section).

## 4. Architecture de l'information (nouvelle)

Onglets (inchangés en nombre) :

| Onglet | Contenu |
|---|---|
| **Découvrir** | recherche, bascule Swipe/Grille, filtres. En-tête épuré : pas de « Salut Awa », pas de série en gros ; le compte à rebours des arrivages devient une ligne discrète. La cloche disparaît (les alertes sont dans Boîte). |
| **Envies** | grille des articles aimés, baisse de prix signalée par un badge. |
| **Vendre** (+) | ouvre le parcours de vente plein écran. |
| **Boîte** (ex-Messages) | `Picker` segmenté **Messages · Commandes · Notifications**. *Commandes* = `Picker` Achats / Ventes + section « Offres à traiter » en tête quand il y en a ; chaque ligne ouvre le suivi de commande ou l'écran d'offre. Badge d'onglet = messages non lus + offres à traiter + notifications non lues. |
| **Profil** | uniquement le profil public, vu par moi : avatar, pseudo, vérifié, ville, note ★ + nombre d'avis, ventes, temps de réponse ; boutons « Modifier le profil » et « Partager » ; puis **Mon dressing** (grille de mes annonces, statut « Réservé/Vendu » en badge) et un accès « Statistiques » (le tableau de bord vendeuse, restylé, en écran poussé). Barre d'outils : ⚙︎ → **Réglages**. |
| **Réglages** (poussé depuis Profil) | `Form` natif : Compte (pseudo, prénom, ville/quartier, téléphone) · Préférences (catégories, tailles, marques) · Paiement par défaut (Wave / Orange Money) · Notifications · Aide (revoir le guide de bienvenue, CGU) · Déconnexion (destructive, confirmation) · pied : version + « Mode démo » le cas échéant. |

Le tableau de bord n'est plus un onglet caché du profil : ses blocs « achats » vont dans Boîte › Commandes, ses blocs « ventes » (objectif, palier, vues, recommandations) dans Profil › Statistiques.

## 5. Ce qui ne change pas

Palette `RF.C`, logo, règles métier (négociation 3 offres, séquestre 72 h, livraisons), modèles, Repository, textes en français. Les identifiants d'accessibilité utilisés par `ReFripeUITests` doivent être conservés ou les tests mis à jour.
