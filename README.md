# ReFripe

Application iOS native (SwiftUI, iOS 17+) pour digitaliser la fripe à Abidjan et Dakar : découverte en swipe ou en grille, négociation encadrée, paiement Wave / Orange Money avec séquestre, livraison point relais / main propre / Yango.

Backend : Supabase (Postgres + RLS, RPC, Storage, Edge Functions de paiement). Sans clés Supabase, l'app tourne entièrement sur les données de démonstration de la maquette.

## Lancer l'app

Prérequis : macOS avec **Xcode 16.3 ou plus récent** (le SDK supabase-swift 2.55.3 exige Swift 6.1) et [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate          # crée ReFripe.xcodeproj (non versionné)
open ReFripe.xcodeproj     # schéma ReFripe → simulateur iPhone → ⌘R
```

Le projet démarre en **mode démo**. Pour brancher Supabase, crée `Config/Secrets.local.xcconfig` (ignoré par git) :

```
SUPABASE_URL = https:/$()/<ton-projet>.supabase.co
SUPABASE_ANON_KEY = <clé anon>
```

Déploiement du backend, authentification (SMS, Sign in with Apple) et paiement : voir [docs/BACKEND.md](docs/BACKEND.md).

## Sur un iPhone / TestFlight

1. Dans `project.yml`, renseigne `DEVELOPMENT_TEAM` (ton Team ID Apple), puis `xcodegen generate`.
2. Sur developer.apple.com, active pour l'App ID `dev.eugenebessan.refripe` les capacités **Sign in with Apple** et **Sensitive Content Analysis**.
3. Xcode → Product → Archive → Distribute App → TestFlight.

## Structure

| Dossier | Contenu |
|---|---|
| `ReFripe/Core` | modèles, protocole `Repository`, état global, navigation, thème |
| `ReFripe/Features` | les écrans (Découvrir, fiche, offres, paiement, commandes, messages, vente, envies, notifications, inscription, profil, tableau de bord) |
| `ReFripe/UI` | composants réutilisables |
| `ReFripe/Data` | `DemoRepository` (données de la maquette) et `SupabaseRepository` |
| `supabase/` | migrations SQL, seed, Edge Functions `payment-init` / `payment-webhook` |
| `docs/` | [architecture](docs/ARCHITECTURE.md) et [backend](docs/BACKEND.md) |

## Tests

- `ReFripeTests` (XCTest) : règles de négociation (`OfferRules`, plafond de 3 offres, contre-offre acceptée, refus), machine à états des commandes et totaux (prix + frais de remise), filtres et tri de Découvrir, envies, formatage `Fmt`, sur le `DemoRepository`.
- `ReFripeUITests` : parcourt l'app en mode démo (inscription → Découvrir swipe/grille → filtres → fiche → offre → paiement → envies → vente → messages → profil → tableau de bord → notifications) et joint une capture d'écran par écran.
- Argument de lancement `-uiTestingSignedOut` (mode démo uniquement) : démarre déconnecté pour afficher l'inscription ; le numéro 07 07 07 07 07 et le code 1234 reconnectent Awa.

Dans Xcode : schéma ReFripe → ⌘U.

## Intégration continue

`.github/workflows/ios.yml` compile l'app pour le simulateur, sans signature, puis lance les tests unitaires et le test d'interface sur un iPhone simulé (choisi par `.github/scripts/pick_simulator.py`), à chaque push sur `main` et sur chaque pull request.

- Branche `ci-screens` : captures d'écran du test d'interface + `summary.txt` (résultat de chaque test), publiée même si des tests échouent.
- Branche `ci-logs` (en cas d'échec) : erreurs de compilation (`errors.txt`), tests en échec avec leurs messages (`test-failures.txt`), fin des journaux.

## Reste à faire avant la production

- **Paiement** : contrats marchands Wave et Orange Money, puis compléter les `TODO(Wave)` / `TODO(Orange Money)` des Edge Functions.
- **Livraison** : aujourd'hui, la vendeuse comme l'acheteuse peut marquer un colis « livré », ce qui lance le délai de 72 h avant libération du séquestre. Il faudra une confirmation par le point relais ou par Yango.
- **Tests** : les tests couvrent le `DemoRepository` ; il manque des tests d'intégration des RPC Supabase (droits par rôle sur les transitions de commande, notamment).
