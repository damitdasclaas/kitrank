# KitRank

Web-App zum Ranken der Trikots von 1. und 2. Bundesliga. Drei Bereiche:

- **Übersicht** – alle Teams mit ihren aktuellen Trikots (Heim/Auswärts/Ausweich/Sonder), je als Cutout und Model-Bilder, mit Link zum Shop.
- **Ranking** – jede:r baut eine eigene, per Link teilbare Rangliste, optional mit Notiz pro Trikot.
- **Reveal** – mehrere Personen decken ihre Ranglisten gemeinsam auf, Rang für Rang, live über mehrere Geräte.

Kein Login: Zugriff läuft über geheime Bearbeitungs-Links, öffentliche Share-Links und Raum-Codes.

Die vollständige Architektur steht in [`architecture.md`](architecture.md).

## Stand

Alle drei Bereiche stehen: **Übersicht** (Team-Raster, Team-Detail, Direktvergleich, große Ansicht), **Ranking** (auswählen, sortieren, teilen) und **Reveal** (Raum, Beitritt, Platz-für-Platz aufdecken), dazu **Login** mit Admin-UI zur Datenpflege.

Noch offen: Aufräum-Job für abgelaufene Räume, Rate-Limiting, Mail-Adapter für Produktion — und der erste echte Deploy.

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
kein Umbau — der ganze Registrierungs-Ablauf ist gebaut und getestet: die
Umgebungsvariable `REGISTRATION_OPEN=true` setzen, fertig.

## Datenpflege

Zwei Wege, bewusst getrennt nach dem, was sich wie oft ändert.

### Stammdaten: Import aus einer Datei

Vereine, Ligen und Saison-Zuordnungen stehen in
[`priv/data/teams_2026_27.json`](priv/data/teams_2026_27.json) — 36 Vereine mit
Kürzel und Vereinsfarbe. Einspielen:

```bash
mix kitrank.import                                        # lokal
/app/bin/kitrank eval 'Kitrank.Release.import_teams()'    # auf dem Server
```

Der Import ist **idempotent** und berichtet, was er getan hat. Für die nächste
Saison die Datei kopieren, `season` hochsetzen, Auf- und Abstiege eintragen,
neu einspielen — Vereine wechseln dann einfach die Liga.

Drei Dinge, die er absichtlich **nicht** tut:

- **Vereine löschen.** Wer aus der Datei fällt, verliert nur die Zuordnung für
  diese Saison. Sonst wären mit einem Abstieg auch alle Trikots früherer
  Saisons weg.
- **Andere Saisons anfassen.** Ein Lauf betrifft nur die Saison in der Datei.
- **Shop-Links überschreiben.** Ein leeres Feld in der Datei löscht nicht, was
  im Admin gepflegt wurde.

### Trikots: über `/admin`

Bilder stehen bewusst nicht in der Import-Datei. Sie ändern sich laufend, sehen
bei jedem Verein anders aus und brauchen ein Auge: welches Bild der Freisteller
ist und welches eine Model-Aufnahme, entscheidet kein Skript zuverlässig.

Was das Tippen abnimmt: im Trikot-Formular **Produktlink einfügen → „Bilder
holen"**. Der Server lädt die Seite und sammelt alle Bildkandidaten
(`og:image`, JSON-LD, `<img>` und `srcset`), entdoppelt Größenvarianten und
zeigt sie als Raster. Dann klickst du: **erster Klick = Freisteller, jeder
weitere = Model-Bild.** Der Produktlink wird gleich als Shop-Deep-Link
übernommen.

Nicht jeder Shop lässt sich lesen, und die Oberfläche sagt jeweils warum:

| Was passiert | Warum |
|---|---|
| „Der Shop hat nicht geantwortet" | Bot-Schutz lässt die Verbindung still offen (Bayern, merchandising-onlineshop.com) |
| „Lädt Bilder erst im Browser nach" | JS-gerenderte Seite, der Server sieht nichts (shop.bvb.de) |
| „Lässt automatisierte Abrufe nicht zu" | Antwortet mit 403 oder 429 |

In allen Fällen ist der Ausweg derselbe und steht in der Meldung: Bild-Adressen
im Browser per Rechtsklick kopieren und unten einfügen. Bot-Schutz wird nicht
umgangen.

Der Abruf läuft in einem eigenen Prozess (`start_async`) — ein Shop, der zwölf
Sekunden nicht antwortet, würde die Oberfläche sonst so lange einfrieren, und
ein eingefrorenes Fenster sieht aus wie ein Fehler.

**Sondertrikots** gibt es pro Team und Saison beliebig viele — Heim, Auswärts
und Ausweich weiterhin genau eines. Dafür brauchen Sondertrikots einen **Namen**
(„125 Jahre", „Weihnachten"): ohne ihn stünde in jeder Liste mehrfach dasselbe
„Sonder". Zwei Sondertrikots desselben Teams dürfen nicht denselben Namen tragen.

Umgesetzt über zwei partielle Unique-Indizes statt einer gelockerten Regel — so
bleibt die Begrenzung dort, wo sie sinnvoll ist, statt überall zu fallen.

`/admin` hat CRUD für alles. Die Trikot-Liste lässt sich nach **Saison und Liga**
filtern und nach **Verein durchsuchen** (Name oder Kürzel) — bei über hundert
Trikots pro Saison ist Scrollen sonst keine Option.

Sie zeigt ausdrücklich auch Trikots **ohne Liga-Zuordnung**, rot markiert. Die
tauchen in der Übersicht nämlich nicht auf, und das soll im Admin auffallen
statt unsichtbar zu bleiben.

Das Dashboard zeigt, was noch fehlt — Trikots ohne Bild, ohne Shop-Link, und ob
für die Saison überhaupt Zuordnungen existieren.

**Ohne Saison-Zuordnung bleibt die Übersicht leer** — die Gruppierung kommt aus
`team_seasons`, nicht aus einem Feld am Verein.

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

## Deploy (Railway)

Das Dockerfile ist providerunabhängig — im Code steht nichts über den Hoster,
alles läuft über Umgebungsvariablen. `railway.json` sagt Railway nur, dass es das
Dockerfile bauen und vor jedem Deploy die Migrationen fahren soll.

1. Im Railway-Projekt **zwei Services**: einen aus diesem Repo, dazu **Postgres**
   aus dem Katalog.
2. Am App-Service diese Variablen setzen:

```
DATABASE_URL   = ${{Postgres.DATABASE_URL}}   # private Adresse, nicht die public
ECTO_IPV6      = true
SECRET_KEY_BASE = <mix phx.gen.secret>
PHX_HOST       = <deine-domain>.up.railway.app
```

`PORT` setzt Railway selbst.

**`ECTO_IPV6=true` ist nicht optional.** Railways internes Netz spricht nur IPv6;
ohne die Variable verbindet sich Ecto nicht mit der Datenbank.

**`PHX_HOST` muss exakt die ausgelieferte Domain sein.** Der Wert steuert zwei
Dinge auf einmal: die erzeugten Teilen-Links der Ranglisten und `check_origin`
für die LiveView-Verbindung. Stimmt er nicht, verbinden sich die WebSockets
nicht — und das Reveal bleibt stumm.

Migrationen laufen bei jedem Deploy über den Pre-Deploy-Befehl aus
`railway.json`. Von Hand geht es auch:

```bash
/app/bin/kitrank eval 'Kitrank.Release.migrate()'
```

### Ersten Admin anlegen

Ohne eingerichteten Mailversand kommt kein Magic Link an. Deshalb gibt es den
Weg über die Konsole — er gibt den Anmelde-Link direkt aus:

```bash
/app/bin/kitrank eval 'Kitrank.Release.admin("du@example.com")'
```

### Mailversand

Noch offen. Lokal läuft alles über `/dev/mailbox`; in Produktion ist bisher kein
Adapter gesetzt, das Anmelden per Magic Link funktioniert dort also noch nicht.
Nötig sind ein Swoosh-Adapter in `config/runtime.exs` und die passenden
Zugangsdaten.

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

Die Auswahl beginnt mit dem **Ausschnitt** — drei Achsen, frei kombinierbar:

| Achse | wofür |
|---|---|
| **Saison** | eine, mehrere, oder „Alle" fürs Archiv |
| **Liga** | Bundesliga, 2. Bundesliga, … |
| **Verein** | einer oder mehrere |

Damit geht beides: „alle Heimtrikots der Bundesliga 2026/27" genauso wie
**„alle HSV-Trikots der letzten zehn Jahre"** — Saison auf „Alle", Verein auf
HSV, fertig.

Eine leere Menge heißt überall **keine Einschränkung**, wie beim Reveal-Raum.
Damit das nicht wie ein Versehen aussieht, ist „Alle" ein eigener Knopf, der
dann aktiv leuchtet.

Die Gruppierung passt sich an: bei **einer** Saison nach Liga, bei **mehreren**
nach Saison. Wer Trikots über Jahre sortiert, denkt in Jahren; wer eine Saison
rankt, in Ligen.

Die Schnellauswahl („Alle Heim", „Alle Trikots") bezieht sich immer genau auf
den gewählten Ausschnitt — ein Knopf, der stillschweigend mehr mitnimmt, wäre
eine böse Überraschung. Angeboten werden nur Kit-Typen, die es im Ausschnitt
wirklich gibt.

Der Ausschnitt steht bewusst **nicht** in der Datenbank: er sagt nur, worüber
gerade entschieden wird, und gehört nicht zur Rangliste selbst. Beim
Wiederkommen ergibt er sich aus dem, was schon drin ist — wer bisher nur
HSV-Trikots gewählt hat, landet wieder dort.

### Sortieren durch Vergleichen

Statt von Hand zu ziehen geht es auch als **Duell**: zwei Trikots, du wählst
eines, weiter bis die Reihenfolge steht. Das Ergebnis ist ein Entwurf, den man
danach im Sortier-Schritt noch anfassen kann.

Verfahren ist **binäres Einfügen** (`Kitrank.Rankings.Duel`) — der sortierte Teil
bleibt sortiert, jedes neue Trikot wird per Halbierungssuche eingeordnet. Kostet
rund `n · log₂ n` Fragen: **18 Trikots in 52 Vergleichen** statt 153 bei jedem
gegen jeden.

Kein Elo und keine Zufallspaarungen: die brauchen ein Vielfaches an Vergleichen
und liefern trotzdem keine garantiert vollständige Ordnung.

Die Logik ist reine Datenstruktur ohne Datenbankbezug — geprüft wird gegen einen
Vergleicher, der die Wunschordnung kennt: kommt genau die heraus, stimmt das
Verfahren. Der Zwischenstand ist jederzeit eine gültige Reihenfolge und wird
nach **jeder** Antwort gespeichert, Abbrechen kostet also nichts.

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

`/reveal/new` ist der Einstieg: links Code eingeben und beitreten, rechts einen
Raum erstellen. `/reveal/:room_code` ist der Raum selbst. Beigetreten wird mit
dem **Teilen-Link** der eigenen Rangliste, nicht mit dem Bearbeiten-Link — das
Reveal braucht Leserechte, nicht mehr.

**Der Raum gibt den Ausschnitt vor.** Beim Erstellen legt der Host Saison, Ligen
und Kit-Typen fest; alle Ranglisten werden darauf gefiltert und im Ausschnitt neu
durchnummeriert. Ohne das vergleicht der Reveal Rang gegen Rang über völlig
verschiedene Mengen — „Platz 2" hieße bei einer Zweierliste „mein schlechtestes"
und bei einer Neunerliste „fast mein bestes". Die Lobby zeigt vor dem Start, wer
wie viel vom Ausschnitt abdeckt.

Im Datenmodell heißt eine leere Liga- oder Typ-Liste **keine Einschränkung** — ein
Raum über alles ist ein legitimer Raum. Dass beim Anlegen über die Oberfläche
trotzdem etwas gewählt sein muss, prüft die Oberfläche.

**Aufgedeckt wird einzeln.** Der Host schaltet die Plätze weiter, aber jede:r
dreht die eigene Karte selbst um. Fremde Karten bleiben zu, bis ihr Besitzer
klickt. Karten von Listen, die so weit nicht reichen, gelten als aufgedeckt —
sonst würde die Runde auf jemanden warten, der nichts zeigen kann. Der Host darf
trotzdem weiterschalten, damit eine abwesende Person nicht alles blockiert.

Eine **Gesamtübersicht** zeigt jederzeit den bisherigen Verlauf als Tabelle:
eine Zeile je Platz, eine Spalte je Person. Die Regel dafür ist bewusst einfach —
vergangene Runden sind offen, die laufende zeigt nur, was umgedreht wurde. Eine
Karte dauerhaft zu verstecken, nur weil jemand nicht geklickt hat, würde die
Tabelle für alle anderen unbrauchbar machen.

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

- **Bilder werden in der Größe geladen, die der Ort braucht.** Gespeichert wird die größte Variante, die der Shop hergibt (beim HSV 1000×1000 bei 108 KB) — im Raster ist die Kachel aber nur ~250 px breit. `Kitrank.Kits.ImageVariant` leitet für bekannte Shop-CDNs die kleinere Adresse ab: 27 KB statt 108 KB, bei 36 Kacheln 0,9 MB statt 3,7 MB. Die große Ansicht lädt weiter das Original. Fremde Muster bleiben unangetastet — lieber ein zu großes Bild als ein gebrochenes, und bewusst kein `srcset`, weil es dort keinen Rückfall gibt.
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
