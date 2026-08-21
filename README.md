# KitRank

Web-App zum Ranken der Trikots von 1. und 2. Bundesliga. Drei Bereiche:

- **Übersicht** – alle Teams mit ihren aktuellen Trikots (Heim/Auswärts/Ausweich/Sonder), je als Cutout und Model-Bilder, mit Link zum Shop.
- **Ranking** – jede:r baut eine eigene, per Link teilbare Rangliste, optional mit Notiz pro Trikot.
- **Reveal** – mehrere Personen decken ihre Ranglisten gemeinsam auf, Rang für Rang, live über mehrere Geräte.

Kein Login: Zugriff läuft über geheime Bearbeitungs-Links, öffentliche Share-Links und Raum-Codes.

Die vollständige Architektur steht in [`architecture.md`](architecture.md).

## Stand

Fertig: Datenmodell und Contexts (Schritt 1 aus Abschnitt 8 der Architektur) — Migrations, Schemas, Queries, Seeds, Tests.
Noch offen: Übersicht-, Ranking-, Reveal- und Admin-LiveViews.

## Setup

Vorausgesetzt sind Docker und die in `.tool-versions` gepinnten Versionen (Erlang 29.0.5, Elixir 1.20.2 — z. B. über `asdf install`).

```bash
docker compose up -d postgres   # Datenbank
mix setup                       # deps, DB anlegen, migrieren, Seeds, Assets
mix phx.server                  # http://localhost:4000
```

`mix setup` lädt auch die Dev-Seeds: ein paar Beispiel-Teams mit Trikots, aber **ohne** Bild- und Shop-URLs. Die echten Daten werden später über die Admin-UI gepflegt, nicht im Seed-Skript (Architektur Abschnitt 4.4).

### Tests

```bash
mix test
```

Die Test-Datenbank legt Ecto selbst an, es braucht dafür nur den laufenden Postgres-Container.

### App im Container statt nativ

Startet exakt das Release-Image, das auch nach Fly geht — langsamerer Dev-Loop, aber nah an Produktion:

```bash
cp .env.example .env && mix phx.gen.secret   # Wert in .env eintragen
docker compose --profile app up
```

## Deploy (Fly.io)

```bash
fly launch --no-deploy --copy-config
fly postgres create --name kitrank-db --region fra
fly postgres attach kitrank-db               # setzt DATABASE_URL
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)
fly deploy
```

Migrationen laufen bei jedem Deploy automatisch über das `release_command` in `fly.toml`.

## Aufbau

```
lib/kitrank/
  kits.ex           # Teams, Ligen, Trikots – liefert die Übersicht, schreibt für den Admin
  kits/             # Sport, Competition, Team, TeamSeason, Kit + Season-/URL-Validierung
  rankings.ex       # Ranglisten anlegen, umsortieren, teilen
  rankings/         # Ranking (edit_token + share_slug), RankingEntry
  reveal.ex         # Räume, Beitritt, Schritt-für-Schritt-Aufdecken, PubSub
  reveal/           # Room, Participant
lib/kitrank_web/
  presence.ex       # wer ist gerade in einem Reveal-Raum online
```

Ein paar Entscheidungen, die man dem Code sonst nicht ansieht:

- **Liga-Zugehörigkeit hängt an `team_seasons`**, nicht am Team. Auf-/Abstieg ist damit ein Datensatz pro Jahr, keine Änderung an Stammdaten.
- **`sports` und `competitions` sind Tabellen**, keine hart codierten Strings. Eine weitere Liga oder Sportart ist später eine neue Zeile, kein Deploy.
- **Reveal-State liegt in Postgres**, nicht in einem GenServer pro Raum. Für Freundesgruppen reicht "Write + Broadcast", und Reconnects brauchen dadurch keine Sonderbehandlung.
- **Der Raumcode steuert nicht den Raum.** Er ist kurz und damit ratbar; die Host-Rechte hängen an einem eigenen langen `host_token`.
- **Trikotbilder werden verlinkt, nicht gehostet** (Urheberrecht, Architektur Abschnitt 5). URL-Felder sind auf `http(s)` begrenzt, weil die Werte direkt in `src`/`href` landen.
