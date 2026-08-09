# Commit Convention

Dieses Projekt verwendet [Conventional Commits](https://www.conventionalcommits.org/de/v1.0.0/).

## Format

```
<type>(<scope>): <beschreibung>
```

## Types

| Type       | Beschreibung        | Beispiel                                    |
| ---------- | ------------------- | ------------------------------------------- |
| `feat`     | Neues Feature       | `feat(ar): add barrier overlay rendering`   |
| `fix`      | Bugfix              | `fix(map): correct marker position offset`  |
| `docs`     | Dokumentation       | `docs(readme): add setup instructions`      |
| `style`    | Formatierung        | `style(views): apply SwiftLint formatting`  |
| `refactor` | Code-Umbau          | `refactor(services): split SupabaseService` |
| `test`     | Tests               | `test(barrier-logic): add shouldWarn tests` |
| `chore`    | Build, Deps, Config | `chore(deps): update supabase-swift`        |
| `perf`     | Performance         | `perf(map): lazy-load barrier markers`      |

## Scopes

| Scope           | Bereich                         |
| --------------- | ------------------------------- |
| `onboarding`    | Screens 1.1–1.6                 |
| `auth`          | Sign-up, Sign-in, Supabase Auth |
| `map`           | Kartenansicht, MapKit, Marker   |
| `ar`            | ARKit, RealityKit, AR-Overlays  |
| `barrier-logic` | shouldWarn(), Schwellenwerte    |
| `profile`       | UserProfile, Einstellungen      |
| `data`          | Supabase, OSM-Import, ginto API |
| `ui`            | Shared UI-Komponenten           |
| `a11y`          | Barrierefreiheit der App        |
| `poi`           | POI-Suche, Filter, Detail       |

## Branch-Strategie

```
main              ← Stabile Releases / Abgabeversion
├── develop       ← Aktuelle Entwicklung
│   ├── feat/onboarding-flow
│   ├── feat/map-view
│   ├── feat/ar-session
│   └── fix/barrier-logic-scewo
```

Feature-Branches gehen per Pull Request nach `develop`, `develop` per Pull
Request nach `main`. Direkte Commits auf `main` bleiben den Abgabeständen
vorbehalten.

## Sprache

Commit-Betreffzeilen auf Englisch, Imperativ, ohne Punkt am Ende – wie die
Beispiele oben. Der Code selbst ist auf Deutsch kommentiert, weil die
Arbeit auf Deutsch verfasst ist.
