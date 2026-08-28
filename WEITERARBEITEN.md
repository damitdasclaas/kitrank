# Weiterarbeiten auf einem anderen Rechner

Was du brauchst, um hier weiterzumachen — und was dich sonst Zeit kostet.

`README.md` erklärt, **was** die App ist und wie sie deployt wird. Dieses Papier
erklärt, **wie man an ihr arbeitet**. `plan.md` sagt, wo die laufenden Vorhaben
stehen.

Stand: 28.08.2026.

---

## In fünf Minuten lauffähig

Vorausgesetzt: Docker und die in `.tool-versions` gepinnten Versionen — Erlang
29.0.5, Elixir 1.20.2, etwa über `asdf install`.

```bash
git clone https://github.com/damitdasclaas/kitrank.git && cd kitrank
docker compose up -d postgres
mix setup                    # deps, DB anlegen, migrieren, Seeds, Assets
mix kitrank.import                             # Fußball: 36 Vereine
mix kitrank.import priv/data/nfl_2026_27.json  # NFL: 32 Vereine
mix phx.server               # http://localhost:4000
```

`mix setup` allein reicht nicht: die Seeds legen nur ein paar Beispieldaten an.
Die beiden Import-Läufe bringen den echten Stammdatenbestand.

**Was du danach hast:** zwei Sportarten, drei Ligen, 68 Vereine. Bilder haben
nur **vier** Trikots (HSV Heim/Auswärts/Ausweich, TSG Heim) — alle anderen
zeichnet die App als Silhouette. Das ist Absicht und kein Fehler, aber es heißt:
**wer eine Bild-Änderung prüfen will, muss auf `/football` beim HSV oder bei der
TSG schauen.** Auf einer Kachel ohne Foto sieht man nichts.

Ein Admin-Konto brauchst du nur für `/admin`:

```bash
mix kitrank.admin du@example.com   # gibt einen fertigen Anmelde-Link aus
```

---

## Täglicher Ablauf

```bash
mix phx.server                    # http://localhost:4000
HANDY=1 mix phx.server            # zusätzlich im WLAN, für echte Geräte
mix test                          # ~730 Tests, läuft in ~4 s
mix format                        # vor jedem Commit
mix format --check-formatted      # das prüft auch CI-artig
mix gettext.extract --merge       # nach jedem neuen sichtbaren Text
```

`HANDY=1` bindet an alle Schnittstellen; die App ist dann unter
`http://<LAN-IP>:4000` erreichbar. Ohne die Variable bleibt es bei `localhost`.

---

## Fallen, die schon Zeit gekostet haben

Die Liste ist teuer erkauft. Wer sie liest, spart sich das nochmal.

### Feste Vereins-Kürzel in Tests verklemmen die Datenbank

`teams.short_code` ist eindeutig. Zwei `async: true`-Tests, die beide einen
Verein mit demselben festen Kürzel anlegen, warten in ihren Transaktionen
wechselseitig auf die Eindeutigkeitsprüfung des anderen — Postgres löst das mit
`ERROR 40P01 deadlock detected` auf. Sporadisch, etwa jeder dritte Lauf.

**Regel:** Namen dürfen fest sein, Kürzel nicht. `team_fixture(name: "1. FC
Köln")` und das Kürzel aus dem Fixture nehmen. Wo die Reihenfolge nach Kürzel
geprüft wird, ein gemeinsames Suffix hinter einen steuernden Anfangsbuchstaben
setzen (`"A" <> lauf`, `"M" <> lauf`, `"Z" <> lauf`).

Dasselbe gilt für **Sportart-Slugs**: jedes Testmodul bekommt einen eigenen
(`@sport_slug "uebersicht-test"`), nie denselben in zwei Modulen.

### Neuer sichtbarer Text ohne Übersetzung bricht den Test

`untranslated_text_test.exs` rendert die Besucher-Seiten auf Englisch und sucht
nach Umlauten. Ein neuer deutscher Text ohne englische Fassung fällt dadurch
auf — aber erst im Testlauf, nicht beim Schreiben.

**Ablauf:** Text in `gettext(...)` wickeln → `mix gettext.extract --merge` →
`msgstr` in `priv/gettext/en/LC_MESSAGES/default.po` füllen. Auf `fuzzy` achten:
Gettext rät bei ähnlichen Texten und schreibt dann eine **falsche** Übersetzung
hin, die man leicht übersieht.

### `kit_figure` mit `fill` ignoriert Polster

`fill` legt das Bild mit `absolute inset-0` in den Kasten. `inset-0` misst gegen
die **Padding-Box** — ein `p-4` am Kasten oder am Bild hat damit **keine
Wirkung**. Trikots stehen randlos.

Das ist bekannt und bewusst so geblieben, aber es heißt: ein `p-*` an so einem
Kasten ist tote Klasse. Wer Polster will, braucht einen inneren `relative`-Kasten.

### Die Sportart-Route fängt alles ab

`/:sport` steht als **letzter Scope** in `router.ex` und nimmt alles, was davor
nicht gepasst hat. Neue Top-Level-Routen müssen **davor** stehen, sonst sind sie
tot. Zusätzlich sperrt `Kitrank.Kits.Sport` die Slugs bestehender Pfade
(`reservierte_slugs/0`) — wer eine Route hinzufügt, trägt ihren Pfad dort ein.

### `Search.matches?/2` trifft bei leerer Suche alles

Absichtlich: so muss kein Aufrufer den Sonderfall behandeln. Wer daraus „nimm
den ersten Treffer" baut, nimmt bei leerem Feld den erstbesten Datensatz. Vorher
auf leer prüfen.

### `mix format` schreibt HEEx um

Skript-Ersetzungen über Zeichenketten scheitern nach einem `mix format`, weil
Attribute umgebrochen wurden. Entweder vor dem Formatieren ersetzen oder über
Zeilennummern gehen.

### Ein Trikot zu löschen entfernt es aus fremden Ranglisten

`ranking_entries.kit_id` steht auf `on_delete: :delete_all`. `mix
kitrank.aufraeumen` prüft das deshalb und lässt belegte Trikots stehen. Wer
anderswo Trikots löscht, muss dasselbe prüfen.

---

## Datenpflege-Kommandos

```bash
mix kitrank.import [datei]        # Stammdaten, idempotent, pro Sportart
mix kitrank.aufraeumen            # Trikots ohne Kategorie in ihrer Sportart: melden
mix kitrank.aufraeumen --loeschen # … und löschen (nur leere, unbenutzte)
mix kitrank.thumbs                # kleine Bildvarianten nachholen
mix kitrank.admin <mail>          # Admin anlegen/befördern
```

Auf dem Server dasselbe über `Kitrank.Release`:

```bash
/app/bin/kitrank eval 'Kitrank.Release.migrate()'
/app/bin/kitrank eval 'Kitrank.Release.import_teams()'
/app/bin/kitrank eval 'Kitrank.Release.import_teams("data/nfl_2026_27.json")'
/app/bin/kitrank eval 'Kitrank.Release.aufraeumen()'
/app/bin/kitrank eval 'Kitrank.Release.admin("du@example.com")'
```

**Pfade sind relativ zu `priv/`**, nicht zum Arbeitsverzeichnis: im Release
liegt `priv/` unter `lib/kitrank-<version>/`. `Import.resolve/1` probiert beide
Schreibweisen, `"data/nfl_2026_27.json"` ist die gemeinte.

---

## Nach dem nächsten Deploy einmalig nötig

Drei Migrationen dieser Woche sind noch nicht auf dem Server, und die NFL steht
dort noch mit Ausweichtrikots da, die es in der Sportart nicht mehr gibt:

```bash
/app/bin/kitrank eval 'Kitrank.Release.migrate()'
/app/bin/kitrank eval 'Kitrank.Release.import_teams()'
/app/bin/kitrank eval 'Kitrank.Release.import_teams("data/nfl_2026_27.json")'
/app/bin/kitrank eval 'Kitrank.Release.aufraeumen()'              # erst melden
/app/bin/kitrank eval 'Kitrank.Release.aufraeumen(loeschen: true)'
```

**Vorher in `/admin` nachsehen**, ob die NFL dort als Sportart
`american-football` mit Liga `NFL` / Land `US` steht. Heißt sie anders, legt der
Import eine zweite daneben, statt die vorhandene zu füllen.

---

## Wo der Stand steht

`plan.md` ist das Arbeitspapier für die laufenden Vorhaben. Fünf von sechs sind
durch:

1. ✅ Sportart-Routing (`/`, `/football`, `/american-football`)
2. ✅ Trikot-Kategorien pro Sportart
3. ✅ Ranglisten-Ausschnitt gespeichert, mit Trikot-Typ-Achse
4. ✅ Suchbare Mehrfachauswahl bei den Vereinen
5. ✅ Geteilter Link mit Gate („erst selbst ranken")
6. ⬜ **Konten** — die Registrierung ist vollständig gebaut und über
   `REGISTRATION_OPEN=true` zuschaltbar. Der Anlass ist da: das Gate hängt am
   localStorage, ein privates Fenster hebt es auf.

Ist Punkt 6 durch, kann `plan.md` weg — was dauerhaft gilt, gehört vorher nach
`architecture.md` oder `roadmap.md`.

### Was ich nie am Bildschirm geprüft habe

Alles Folgende ist nur über Tests und rohes HTML belegt, nicht bedient:

- der Gate-Ablauf (Bildschirm → eigene Liste bauen → zurück)
- die Multi-Select-Combobox bei der Vereinsauswahl
- die Hero-Aufteilung auf mittleren Breiten
- das Duell auf einem echten Handy (die 58 dvh sind gesetzt, nicht gemessen)

Wer an einem echten Gerät sitzt, sollte da zuerst hinschauen.

---

## Konventionen, die man dem Code ansieht, aber vielleicht nicht ernst nimmt

- **Kommentare erklären das Warum, nicht das Was.** Wo eine Entscheidung
  überrascht, steht der verworfene Weg dabei. Neue Kommentare halten das durch.
- **Commit-Nachrichten beschreiben das Problem, nicht die Änderung.**
  „Kopfzeile war breiter als das Handy-Display", nicht „fix header css".
- **Deutsch** in Kommentaren, Commit-Nachrichten, Tests und
  `data-role`-Attributen. Modulnamen und Ecto-Felder bleiben englisch.
- **Tests halten Entscheidungen fest**, nicht nur Verhalten — die Testnamen sind
  ganze Sätze, und wo ein Test eine Zusage schützt, steht sie als Kommentar
  darüber.
- **`data-role`-Attribute** statt Klassen-Selektoren in Tests. Klassen ändern
  sich beim Gestalten, Rollen nicht.

---

## Der README ist an vier Stellen veraltet

Durch die Arbeit dieser Woche stimmen dort ein paar Sätze nicht mehr. Sie sind
korrigiert, aber falls etwas übersehen wurde, hier die betroffenen Themen:

| Was der README sagte | Was jetzt gilt |
|---|---|
| Übersicht liegt auf `/` | `/` ist die Sportart-Auswahl, die Übersicht liegt unter `/:sport` |
| Ausschnitt hat drei Achsen | vier — Saison, Liga, Verein, **Trikot-Typ** |
| Ausschnitt steht nicht in der Datenbank | er steht dort, in vier `scope_*`-Spalten an `rankings` |
| Verein: einer oder mehrere (als Pillen) | suchbare Mehrfachauswahl, Gewähltes als Chips |
