# KitRank – Roadmap

Stand: 23.08.2026. Ergänzt `architecture.md`, ersetzt sie nicht: dort steht, wie
die App gebaut ist, hier, was als Nächstes kommt und warum.

## 1. Ausgangslage

Es gibt **trikotranking.de** — gleiche Saison, gleicher Umfang (1. und 2. Liga
26/27), Drag-and-drop-Rangliste, Duell-Modus, teilen ohne Anmeldung. Sie sind
als Produkt weiter:

| Sie haben | Wir nicht |
|---|---|
| Community-Voting über alle Nutzer | — |
| Blind-Modus (5/10 Zufallstrikots sofort einordnen) | — |
| Retro-Trikots, „Aus aller Welt" | — |
| SEO: Landingpages, FAQ, Meta-Texte | — |

Sie finanzieren sich über **Affiliate-Links zu Awin und Amazon** (im Footer
deklariert). Das ist transparent, prägt aber die Ausrichtung: die Links gehen zu
Händlern, weil dort die Provision liegt.

**Wir haben, was sie nicht haben** (im ausgelieferten HTML gezielt gesucht — die
Wörter „Reveal" und „live" kommen dort null Mal vor):

- **Das Reveal**: mehrere Geräte, Platz für Platz, alle gleichzeitig, jede:r
  dreht die eigene Karte um, Host übertragbar. Ihr „gemeinsam per Code" ist
  synchronisierte *Eingabe*, kein synchronisiertes *Ereignis*.
- **Notizen pro Trikot** — der Stoff, aus dem ein Reveal-Abend lebt.
- **Ranglisten über Saisons und Vereine** hinweg, nicht nur „Retro" als Kategorie.
- **Deep-Links in den Vereinsshop**, ohne Provision.

### Positionierung

Nicht breiter werden, sondern schärfer. Der Blind-Modus wäre an einem Tag
gebaut und würde uns **ähnlicher** machen, nicht unterscheidbarer. Der Anlass
ist ein anderer: nicht „ich ranke allein und vergleiche mich mit Fremden",
sondern **„wir sitzen zusammen und decken auf"**.

Durchschnitte über Fremde sind langweilig. **Reibung zwischen Leuten, die sich
kennen, ist interessant** — und das ist strukturell unsere Seite.

## 2. Reihenfolge

### Schritt 1 — Abschluss-Ansicht des Reveals ✅ erledigt

Das Reveal hört auf, wenn es interessant wird: nach Platz 1 steht „Fertig" und
sonst nichts. Genau da ist die Gruppe am aufmerksamsten.

Was in den Daten schon steckt, ohne neue Tabellen:

- Wo waren sich alle einig, wo überhaupt nicht
- Der größte Streitfall („Tom Platz 1, Anna Platz 18") — die Zeile, die man weiterschickt
- Das Trikot, das alle unten hatten
- Alle Notizen gesammelt statt einmalig aufblitzend
- Teilbarer Link auf das Ergebnis

Warum zuerst: sitzt auf vorhandenen Daten, erzeugt das Ding, das die App
verlässt, und ist der Unterschied, den niemand nachbauen kann, ohne LiveView-
Räume zu haben.

### Schritt 2 — Beitreten ohne Vorbereitung ✅ erledigt

Heute muss jede:r **vorher** eine Rangliste gebaut und den Teilen-Link parat
haben. Für eine spontane Runde ist das zu viel; trikotranking.de braucht nur
einen Code.

Ziel: einem Raum beitreten und die Rangliste **darin** bauen — mit dem
Ausschnitt des Raums, per Duell. Entscheidet, ob ein Abend überhaupt zustande
kommt.

### Schritt 3 — Vereinsshop sichtbar machen ✅ erledigt

„Im Shop ansehen" → „Zum Vereinsshop", plus ein Satz, dass KitRank an keinem
Kauf mitverdient. Zwanzig Minuten, und die glaubwürdigste Aussage, die eine
Ranking-Seite treffen kann: wer an Käufen verdient, hat ein Interesse daran, wie
das Ranking ausgeht.

### Schritt 4 — Datenpflege automatisieren (siehe 3.1) ⟵ als nächstes

### Schritt 5 — Zweisprachigkeit (siehe 3.3) ✅ erledigt

### Schritt 6 — Weitere Sportarten (siehe 3.2)

## 3. Die drei offenen Fragen

### 3.1 Datenbank per make.com füllen?

**Teilweise — und zwar der langweilige Teil, nicht der interessante.**

Heute gibt es zwei Schreibwege: die Admin-UI (Session-gebunden, für Automation
ungeeignet) und `Kitrank.Kits.Import`, das eine **Datei** liest. Ein
API-Scope existiert nicht (in `router.ex` auskommentiert).

Nötig:

1. `Import.run/1` so umbauen, dass es auch eine Datenstruktur annimmt, nicht nur
   einen Pfad. Kleine Änderung, die Logik bleibt.
2. **`POST /api/import`** mit Token-Prüfung (eigener Plug, kein Session-Login).
   make.com kann JSON posten — damit sind Vereine, Ligen und Saison-Zuordnungen
   automatisierbar.
3. Optional **`POST /api/kits/candidates`**: eine Liste Produktlinks rein, der
   Server holt per `ProductImages` die Kandidaten und legt sie ab. Im Admin
   klickst du nur noch, welche drei es sein sollen.

**Was make.com nicht kann:** entscheiden, welches Bild der Freisteller ist.
Beim HSV war es je nach Produkt eine andere Position — das habe ich nur richtig
zugeordnet, weil ich die Bilder angesehen habe. Zwei Shops antworten ohnehin
nicht (Bayern, merchandising-onlineshop.com, beides Timeout).

Realistischer Gewinn: Stammdaten vollständig automatisch, Bild-URLs
vorgesammelt, Auswahl bleibt manuell. Das ist der Unterschied zwischen einer
Woche und einem Abend.

### 3.2 NFL, NBA, andere Sportarten?

**Das Datenmodell hält, vier konkrete Stellen brechen.**

Vorgesehen ist es (Architektur Abschnitt 11): `sports` und `competitions` sind
Tabellen, `team_seasons` verknüpft, ein Team braucht kein `sport_id`.

Was tatsächlich blockiert:

| Stelle | Problem |
|---|---|
| `Kit.@kit_types` | fest auf `home away third special`. NBA hat City/Statement/Classic Edition, NFL Alternate/Throwback |
| `Kit.@labels` | deutsche Fußballbegriffe, fest verdrahtet |
| `Season.@format` | verlangt `2026/27`. Die NFL-Saison heißt `2026` — würde abgelehnt |
| `kit_silhouette` | zeichnet ein Fußballtrikot. NBA ist ein Trägerhemd, NFL hat Schulterpolster |

Lösung, wenn es soweit ist: `kit_types` und Saisonformat pro `Sport` in der
Datenbank statt im Modul, Labels über Gettext, und eine Silhouette pro
Sportart. Kein Umbau, aber auch kein Schalter — schätzungsweise ein bis zwei
Tage.

**Nicht vorher bauen.** Ohne einen konkreten zweiten Sport rät man, welche
Kit-Typen es braucht. Architektur Abschnitt 11 sagt das ausdrücklich.

### 3.3 Deutsch/Englisch umschaltbar? ✅ gebaut

**Ja — und es war Fleißarbeit, kein Schalter.** Wie geschätzt: 274 Meldungen,
verteilt über 16 Dateien.

Wie es funktioniert:

- **Deutsch ist die Quellsprache.** Die `msgid` im Code *ist* der deutsche Text.
  Ein nicht übersetzter Text erscheint dadurch automatisch auf Deutsch statt
  als leerer Kasten — und es gibt keinen deutschen Katalog zu pflegen. Siehe
  `priv/gettext/README.md`.
- **Sprache steht in der Sitzung**, nicht im Pfad (`/sprache/de`, `/sprache/en`).
  Ein URL-Präfix hätte jede Route umgebaut; für zwei Sprachen zahlt sich das
  nicht aus. Ohne eigene Wahl entscheidet `Accept-Language`.
- **Plug *und* `on_mount`-Hook** (`KitrankWeb.Locale`). Das ist die Stelle, an
  der Zweisprachigkeit in LiveView-Anwendungen fast immer bricht:
  `Gettext.put_locale/1` gilt pro Prozess, und der LiveView-Prozess ist nicht
  der Request-Prozess. Nur mit Plug wäre die erste Seite richtig und alles
  danach deutsch.
- **Trikot-Bezeichnungen** liegen jetzt in `KitrankWeb.KitLabel`, nicht mehr im
  Schema. Welche Trikot-Typen es gibt, ist Sache der Domäne; wie sie heißen,
  Sache der Darstellung. Sonst müsste `Kitrank.Kits.Kit` die Sprache des
  Betrachters kennen.

Zwei Dinge, die dabei aufgefallen sind und mit erledigt wurden:

- **Die Anmeldeseiten waren englisch**, der Rest deutsch — `phx.gen.auth`
  generiert englische Texte. Jetzt deutsch in der Quelle, englisch im Katalog.
- **Ecto-Fehlermeldungen** („can't be blank") kommen englisch aus der
  Bibliothek. Für die ist Deutsch *nicht* die Quellsprache, deshalb hat die
  Domäne `errors` als einzige auch einen deutschen Katalog.

**Was bewusst deutsch bleibt:** der Admin-Bereich. Ihn benutzt die Datenpflege,
nicht die Besucher. Die Texte dort sind nicht gewickelt und erscheinen in jeder
Sprache auf Deutsch.

**Zwei Wächter**, weil ein fehlender `gettext`-Aufruf nichts kaputtmacht und
deshalb kein Test ihn von selbst findet:

- `test/kitrank_web/untranslated_text_test.exs` rendert jede Besucher-Seite auf
  Englisch und schlägt an, wenn ein Umlaut übrig ist — inklusive Gegenprobe,
  dass der Wächter greift.
- `test/kitrank_web/locale_test.exs` prüft die Erkennung, das Umschalten, das
  Halten über das Verbinden *und über ein Ereignis hinaus* und dass kein
  `msgstr` leer oder `fuzzy` ist.

**Offene Altlast: Satzfragmente.** Wo im Text ein `<span>` mitten im Satz sitzt,
sind daraus zwei Meldungen geworden („Du brauchst den" + „deiner Rangliste — den
mit"). Für Englisch geht das auf, weil die Wortstellung ähnlich ist; für eine
Sprache mit anderer Satzstellung nicht. Zu beheben, indem die betroffenen
Absätze auf *eine* Meldung mit Bindings umgestellt werden — so wie es die
Hauptzeile und die Einleitung jetzt schon sind. Rund ein Dutzend Stellen, kein
Vorrang, solange es bei de/en bleibt.

**Die Produktfrage bleibt offen** und ist keine technische: Die deutschen Texte
sind bewusst gesprochen. Die englische Fassung ist mit derselben Tonlage
geschrieben, aber von mir — nicht von jemandem, dessen Muttersprache das ist.
Wenn Englisch ernst gemeint ist, sollte da mal jemand drüberlesen.

## 4. Bewusst nicht jetzt

- **Blind-Modus** — macht uns ähnlicher, nicht unterscheidbarer
- **Community-Voting über Fremde** — genau das Gegenteil der Positionierung
- **Bilder-Proxy mit Skalierung** (Architektur Abschnitt 5) — erst wenn Hotlinks
  brechen oder die Bytes wirklich weh tun
- **Rate-Limiting** auf den Token-Routen — vor öffentlicher Bewerbung nachziehen
- **Mail-Adapter für Produktion** — nötig, sobald jemand außer dir ein Konto braucht
