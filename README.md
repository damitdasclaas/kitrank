# KitRank

Web-App zum Ranken der Trikots von 1. und 2. Bundesliga. Drei Bereiche:

- **Übersicht** – alle Teams mit ihren aktuellen Trikots (Heim/Auswärts/Ausweich/Sonder), je als Cutout und Model-Bilder, mit Link zum Shop.
- **Ranking** – jede:r baut eine eigene, per Link teilbare Rangliste, optional mit Notiz pro Trikot.
- **Reveal** – mehrere Personen decken ihre Ranglisten gemeinsam auf, Rang für Rang, live über mehrere Geräte.

Kein Login: Zugriff läuft über geheime Bearbeitungs-Links, öffentliche Share-Links und Raum-Codes.

Die vollständige Architektur steht in [`architecture.md`](architecture.md).

## Stand

Alle drei Bereiche stehen: **Übersicht** (Team-Raster, Team-Detail, Direktvergleich, große Ansicht), **Ranking** (auswählen, sortieren, teilen) und **Reveal** (Raum, Beitritt, Platz-für-Platz aufdecken), dazu **Login** mit Admin-UI zur Datenpflege.

Noch offen: Aufräum-Job für abgelaufene Räume, Rate-Limiting, Mail-Adapter für Produktion — und einmal wirklich auf Fly deployen.

## Anmelden

Es gibt einen vollwertigen Login, aber **die Registrierung ist zu** — die App hat
heute nur Admins. Den ersten legst du auf der Kommandozeile an:

```bash
mix kitrank.admin du@example.com     # anlegen oder befördern
mix kitrank.admin --list             # alle Admins zeigen
mix kitrank.admin du@example.com --revoke
```

Die Task gibt einen fertigen Anmelde-Link aus. Das ist Absicht: beim ersten Admin
gibt es niemanden, der eine Einladung verschicken könnte, und in Produktion steht
oft noch kein Mailer. Danach läuft die Anmeldung über `/users/log-in` per
Magic Link — lokal landen die Mails unter `/dev/mailbox`.

`is_admin` wird von keinem Changeset gecastet. Es gibt also keinen Weg, sich über
ein Formular selbst zu befördern.

Wenn die App später normale Nutzerkonten bekommen soll, ist das ein Schalter,
kein Umbau — der ganze Registrierungs-Ablauf ist gebaut und getestet:

```bash
fly secrets set REGISTRATION_OPEN=true
```

## Datenpflege

`/admin` (nur für Admins) hat CRUD für Sportarten, Ligen, Vereine,
Saison-Zuordnungen und Trikots. Die Reihenfolge, in der man vorgeht:

1. **Sportart** → **Liga** anlegen
2. **Vereine** mit Kürzel und Vereinsfarbe
3. **Saison**: welcher Verein spielt dieses Jahr in welcher Liga (hier pflegst du Auf- und Abstieg)
4. **Trikots** pro Verein und Saison, mit Bild- und Shop-Links

Ohne Schritt 3 bleibt die Übersicht leer — die Gruppierung kommt aus
`team_seasons`, nicht aus einem Feld am Verein. Das Dashboard unter `/admin`
zeigt, was fehlt.

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
lib/kitrank/
  accounts.ex       # Login, Konten, Admin-Rechte (mix phx.gen.auth)
lib/kitrank_web/
  live/overview_live.ex        # Raster, Team-Modal und Direktvergleich
  live/admin/                  # Datenpflege, nur für Admins
  user_auth.ex                 # Session, Admin-Schranke, Registrierungs-Schalter
  components/kit_components.ex # Trikot-Darstellung und Modal-Hülle
  color.ex                     # Kontrast- und Mischrechnung für Vereinsfarben
  presence.ex                  # wer ist gerade in einem Reveal-Raum online
```

## Ranglisten

Ohne Konto, der Zugriff hängt am Link:

| Link | Wer ihn hat |
|---|---|
| `/rankings/:edit_token/auswahl` | wählt Trikots aus |
| `/rankings/:edit_token/edit` | sortiert sie und schreibt Notizen |
| `/r/:share_slug` | liest mit |

Beide zeigen denselben Datensatz — der Teilen-Link ist deshalb immer aktuell,
es gibt keinen Veröffentlichen-Schritt. Unbekannte Tokens liefern 404 statt
eines Serverfehlers, damit ein Fehlschlag nicht verrät, dass an der Stelle
überhaupt etwas sein könnte.

**Warum zwei Schritte statt einer Liste:** bei vollständigen 1. und 2. Bundesliga
stehen über hundert Trikots zur Wahl. Die per Drag in eine Reihenfolge zu
bringen wäre unbenutzbar, und ein Reveal darüber liefe hundert Runden.
Ausgewählt wird deshalb in einem Raster, sortiert nur noch, was übrig bleibt.

Die Auswahl beginnt mit den **Ligen**: erst legt man fest, worüber überhaupt
entschieden wird, danach zeigt das Raster nur diese Ligen. Die Schnellauswahl
(„Alle Heim", „Alle Auswärts", „Alle Trikots") bezieht sich immer genau auf
diesen Ausschnitt — ein Knopf, der stillschweigend auch die zweite Liga
mitnimmt, wäre eine böse Überraschung. Angeboten werden nur Kit-Typen, die in
den gewählten Ligen wirklich vorkommen.

Die Liga-Vorauswahl steht bewusst **nicht** in der Datenbank: sie sagt nur, worüber
gerade entschieden wird, und gehört nicht zur Rangliste selbst. Beim Wiederkommen
ergibt sie sich aus dem, was schon drin ist.

Jede Zeile beim Sortieren hat eine **Detailansicht** — großes Bild mit Galerie,
großes Notizfeld, Shop-Link und die Schiebe-Knöpfe.

Der Browser **merkt sich deine Ranglisten** (localStorage, kein Cookie — der
Token soll nicht bei jedem Request mitgehen). `/rankings/new` zeigt sie oben an;
gelöschte fliegen dabei automatisch raus. Der Bearbeiten-Link bleibt trotzdem
der eigentliche Zugriffsweg, etwa beim Gerätewechsel.

Sortieren geht per Drag (Sortable.js, `assets/js/hooks/sortable.js`) **und** über
Pfeil-Knöpfe — Drag ist auf dem Handy fummelig und mit der Tastatur gar nicht zu
bedienen. Der Hook schickt nach dem Loslassen die komplette neue Reihenfolge,
nicht "Element X von 3 nach 1": so kann der Server sie gegen seinen Stand prüfen
und ablehnen, statt eine Verschiebung auf einen Stand anzuwenden, den der
Browser vielleicht nicht mehr hat.

## Reveal

`/reveal/new` öffnet einen Raum, `/reveal/:room_code` ist der Raum. Beigetreten
wird mit dem **Teilen-Link** der eigenen Rangliste, nicht mit dem Bearbeiten-Link
— das Reveal braucht Leserechte, nicht mehr.

Der Ablauf hängt an zwei getrennten Dingen: der **Raumcode** ist kurz, zum
Vorlesen gedacht und wird geteilt; die **Steuerung** hängt an einem eigenen
langen Token. Das liegt nur im localStorage des Erstellers und steht bewusst
nicht in der Adresse — wer eine URL mit Host-Token weitergäbe, würde ungewollt
die Steuerung mitgeben. Für den Gerätewechsel gibt es stattdessen die Übergabe
im Raum (`Reveal.transfer_host/2`); das Ersteller-Token bleibt daneben gültig,
damit kein Raum unsteuerbar wird, wenn der neue Host offline geht.

Jeder Schritt wird erst in Postgres geschrieben und dann als fertig geladener
Schritt gesendet — auch an den Host selbst. Eine Extra-Runde, die dafür
garantiert, dass alle exakt denselben Stand rendern statt zwei Codepfade zu
haben. Kein Client lädt nach, kein Polling, und ein Reconnect ist unspektakulär:
beim Neuaufbau steht der Stand einfach in der Datenbank.

Auf schmalen Bildschirmen bleiben die Karten **nebeneinander und werden
gewischt** statt gestapelt (Scroll-Snap pro Karte). Bei jedem Schritt geht es um
den Vergleich; gestapelt sieht man nie zwei gleichzeitig.

## Zur Oberfläche

Die Übersicht liegt auf `/`, ein Team auf `/teams/:id`, der Vergleich auf `/vergleich`
— alle drei bedient derselbe LiveView über `live_action`.

Die Vergleichsauswahl steht im Query-Parameter `trikots`, nicht im Socket-State.
Das macht sie teilbar (`/vergleich?trikots=12,40,7`), lässt den Zurück-Button
richtig funktionieren und überlebt einen Reload. IDs, die es in der angezeigten
Saison nicht gibt, fallen still weg statt leere Karten zu erzeugen.

**Zur Gestaltung**, weil es dem Code sonst wie Willkür aussieht:

- **Fehlt ein Trikotbild, wird das Trikot gezeichnet** statt einen grauen Kasten zu zeigen — als SVG in der Vereinsfarbe, gemustert nach Kit-Typ. Das ist der Normalfall und nicht der Ausnahmefall, weil Bilder verlinkt und nicht gehostet werden.
- **Die App hat keine eigene Akzentfarbe.** 36 Vereinsfarben tragen die Sättigung der Seite; ausgewählte Zustände nehmen die Farbe des jeweiligen Vereins an, statt mit ihr zu konkurrieren.
- **Ein Klick auf jede Trikot-Fläche zeigt es groß** — mit Pfeiltasten durch die Bilder, Escape zurück. Escape schließt dabei erst die große Ansicht und nicht gleich das Modal darunter. Funktioniert auch bei Trikots ohne Foto, dort eben mit der Zeichnung.
- **Die Trikot-Fläche bleibt in beiden Themes hell.** Trikots sind Produktfotos, und die liegen auf Weiß — im Dunkelmodus wirkt das wie ein Leuchtkasten statt wie ein invertiertes Foto.
- Kontraste (Schrift auf Vereinsfarbe, Ärmelabstufungen) rechnet `KitrankWeb.Color` über die WCAG-Leuchtdichte aus, nicht über einen Helligkeits-Daumenwert. Sonst kippt es genau bei Dortmund-Gelb und Schalke-Blau in die falsche Richtung.

Ein paar Entscheidungen, die man dem Code sonst nicht ansieht:

- **Liga-Zugehörigkeit hängt an `team_seasons`**, nicht am Team. Auf-/Abstieg ist damit ein Datensatz pro Jahr, keine Änderung an Stammdaten.
- **`sports` und `competitions` sind Tabellen**, keine hart codierten Strings. Eine weitere Liga oder Sportart ist später eine neue Zeile, kein Deploy.
- **Reveal-State liegt in Postgres**, nicht in einem GenServer pro Raum. Für Freundesgruppen reicht "Write + Broadcast", und Reconnects brauchen dadurch keine Sonderbehandlung.
- **Der Raumcode steuert nicht den Raum.** Er ist kurz und damit ratbar; die Host-Rechte hängen an einem eigenen langen `host_token`.
- **Trikotbilder werden verlinkt, nicht gehostet** (Urheberrecht, Architektur Abschnitt 5). URL-Felder sind auf `http(s)` begrenzt, weil die Werte direkt in `src`/`href` landen.
