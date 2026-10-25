# ReFripe iOS — architecture & conventions

> **Design v2 (octobre 2026)** : la typographie, le style et la navigation sont désormais décrits dans [DESIGN.md](DESIGN.md) (SF + `RF.T`, onglet Boîte, Profil recentré, Réglages). Ce document reste valable pour l'architecture ; les mentions de `RF.F`, de Manrope / Unbounded / IBM Plex Mono et l'aspect des composants ci-dessous datent de la v1.

Application SwiftUI native (iOS 17+, Swift 5 language mode), backend Supabase. Marché : Abidjan & Dakar, prix en **FCFA** (entiers), paiement **Wave / Orange Money** avec **séquestre** (libération auto 72h après livraison), livraison **point relais / main propre / Yango**. Tout le texte de l'UI est en **français**, tutoiement (« ta série », « tes envies »), comme la maquette.

## Arborescence

```
project.yml                  XcodeGen → `xcodegen generate` crée ReFripe.xcodeproj
Config/Secrets.xcconfig      clés Supabase (vides = mode démo)
ReFripe/
  Core/                      CONTRAT PARTAGÉ — ne pas modifier sans validation
    Models.swift             types métier (Listing, Order, OfferThread…)
    Catalog.swift            libellés, options, règles (OfferRules), formatage (Fmt.fcfa)
    Repository.swift         protocole d'accès aux données
    AppStore.swift           état global @Observable (session, envies, badges, toast)
    Navigation.swift         Router, AppTab, Route, .withAppRoutes()
    Theme.swift              RF.C (couleurs), RF.F (polices), RF.R (rayons), RF.S (espacements)
  App/                       point d'entrée, RootView, tab bar            (agent Socle)
  UI/                        kit de composants réutilisables               (agent Socle)
  Data/Demo/                 DemoRepository + données de la maquette        (agent Socle)
  Data/Supabase/             SupabaseRepository, AppConfig                  (agent Backend)
  Data/RepositoryFactory.swift                                              (agent Backend)
  Features/<Feature>/        écrans                                         (agents A–D)
  Resources/                 polices, Assets.xcassets                       (agent Socle)
supabase/migrations, supabase/functions                                     (agent Backend)
```

## Règles pour tous les agents

1. **Ne modifie que les fichiers/dossiers qui te sont attribués.** Tu peux créer de nouveaux fichiers dans tes dossiers. Si le contrat (`Core/`) doit changer, ne le modifie pas : explique le besoin dans ton rapport final.
2. Garde exactement le **nom de type et la signature d'init** des stubs (ex. `ProductView(listingId:)`), ils sont référencés par `Navigation.swift`.
3. État global : `@Environment(AppStore.self) private var store` ; navigation : `@Environment(Router.self) private var router` puis `router.push(.product(id))`. Données d'écran : `@State` + `.task { … try await store.repo.xxx }`. Erreurs → `store.show(error)`.
4. Style : uniquement les tokens `RF.C.*`, `RF.F.*`, `RF.R.*`, `RF.S.*` et les composants de `UI/`. Icônes = **SF Symbols**. Fond d'écran `RF.C.paper`. Pas de couleurs système iOS par défaut (pas de `.blue`).
5. Montants : `FCFA` (Int) et `Fmt.fcfa(x)` pour l'affichage. Dates : `Fmt.relative`.
6. Qualité iOS : `NavigationStack` natif (bouton retour système conservé, `.navigationTitle` + `.toolbar`), `.sheet` avec `.presentationDetents`, `ShareLink`, `PhotosPicker`, `.sensoryFeedback` pour l'haptique, Dynamic Type via `RF.F` (déjà `relativeTo:`), libellés d'accessibilité sur les boutons icône.
7. Chaque écran doit avoir une `#Preview` qui marche en mode démo : utilise `.previewEnvironment()` (fourni par le Socle dans `UI/Preview.swift`).
8. Pas de dépendance tierce en dehors de `Supabase` (déjà dans `project.yml`).
9. Pas de compilateur Swift ici : vérifie la syntaxe avec `node /home/claude/swiftcheck/check.js <tes fichiers>` (0 erreur exigé). Relis ton code avec soin pour les erreurs de type, que le parseur ne voit pas : c'est Eugène qui compilera dans Xcode.

## Maquette de référence

`/home/claude/mockup-ref/` : `app.js` (logique + rendu HTML de chaque écran), `mockup.css` (styles exacts), `body.html`, `INDEX.txt` (numéros de ligne des fonctions `screenXxx`, `sellStepXxx`…). Lis la fonction de ton écran et ses classes CSS pour reproduire fidèlement mise en page, textes, tailles et couleurs. Les photos sont des data-URI base64 (lignes 247–258) : ne les lis pas, le Socle les convertit en assets `listing-1` … `listing-9`.

Le panneau `PANEL` (ligne ~305) explique l'intention produit de chaque écran ; respecte ces règles métier.

## Kit UI (fourni par le Socle, dans `UI/`)

| Composant | Usage |
|---|---|
| `RFButton(_ title:, symbol:, style: .primary/.secondary/.ink/.ghost, action:)` | boutons pleine largeur (primary = hibiscus) |
| `ListingPhotoView(photo:, listingId:)` | image d'annonce (asset ou URL) avec fond `RF.C.thumb` et repli |
| `ListingCard(listing:)` | carte de la grille (photo 118pt, cœur, badge « Prix en baisse », prix mono, nom, quartier) |
| `HeartButton(listingId:)` | cœur relié à `store.toggleLike` avec animation |
| `Chip(_ title:, selected:, badge:, action:)` | puces de filtre |
| `StatusPill(status: OrderStatus)` | pastille de statut de commande colorée selon `tone` |
| `Avatar(profile:, size:)` + `VerifiedBadge()` | initiale sur fond coloré, badge vérifié |
| `PriceStepper(value: Binding<FCFA>, step:, range:)` | curseur +/− des offres et du prix |
| `SectionLabel(_:)` | petit titre de section (mono, majuscules) |
| `StatTile(title:, value:, delta:)` | tuile du tableau de bord |
| `EmptyStateView(symbol:, title:, message:, action:)` | état vide |
| `LoadingView()`, `ErrorStateView(error:, retry:)` | chargement / erreur |
| `.rfScreenBackground()` | fond paper plein écran |
| `.rfCard()` | fond blanc, rayon 14, filet `RF.C.line` |
| `.previewEnvironment()` | injecte AppStore(démo) + Router pour les #Preview |

## Mode démo

`DemoRepository` est en mémoire, initialisé avec les données de la maquette (9 annonces, 5 vendeuses, commandes, notifications, chat). L'utilisatrice connectée est **Awa_Style225** (vendeuse des annonces 1, 5 et 7, acheteuse des commandes 3–5). Le dépôt simule la vendeuse (réponse aux offres après ~1,5 s via `OfferRules.simulatedSellerResponse`) et le paiement (PAYMENT_PENDING → PAID → AWAITING_SHIPMENT). Les UUID de démo sont déterministes (`DemoIDs`).
