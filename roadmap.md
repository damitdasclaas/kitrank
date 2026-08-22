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

### Schritt 1 — Abschluss-Ansicht des Reveals

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

### Schritt 2 — Beitreten ohne Vorbereitung

Heute muss jede:r **vorher** eine Rangliste gebaut und den Teilen-Link parat
haben. Für eine spontane Runde ist das zu viel; trikotranking.de braucht nur
einen Code.

Ziel: einem Raum beitreten und die Rangliste **darin** bauen — mit dem
Ausschnitt des Raums, per Duell. Entscheidet, ob ein Abend überhaupt zustande
kommt.

### Schritt 3 — Vereinsshop sichtbar machen

„Im Shop ansehen" → „Zum Vereinsshop", plus ein Satz, dass KitRank an keinem
Kauf mitverdient. Zwanzig Minuten, und die glaubwürdigste Aussage, die eine
Ranking-Seite treffen kann: wer an Käufen verdient, hat ein Interesse daran, wie
das Ranking ausgeht.

### Schritt 4 — Datenpflege automatisieren (siehe 3.1)

### Schritt 5 — Zweisprachigkeit (siehe 3.3)

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

### 3.3 Deutsch/Englisch umschaltbar?

**Möglich, aber es ist Fleißarbeit, kein Schalter.**

Gettext ist im Projekt (`KitrankWeb.Gettext`, `priv/gettext/en/`), wird aber nur
in den generierten Dateien benutzt. **Meine Oberfläche hat praktisch keine
gettext-Aufrufe** — alle Texte stehen fest auf Deutsch im Template. Grobe
Zählung: rund 70 Textzeilen in Templates, mit Attributen, Platzhaltern und
aria-Labels realistisch 150 bis 250 übersetzbare Zeichenketten.

Nötig:

1. Jede Zeichenkette in `gettext(...)` wickeln — der Aufwand, verteilt über ~15
   Dateien
2. `mix gettext.extract --merge`, dann übersetzen
3. Locale bestimmen (URL-Präfix, Session oder `Accept-Language`) plus
   `on_mount`-Hook und Umschalter in der Kopfzeile
4. Kit-Typ-Labels aus dem Modul in Gettext holen (überschneidet sich mit 3.2)

**Zwei Dinge, die keine Übersetzung sind:** Vereinsnamen sind Eigennamen und
bleiben. Namen von Sondertrikots („125 Jahre") sind Nutzerdaten — die kann
niemand automatisch übersetzen.

**Und eine Produktfrage, keine technische:** Die deutschen Texte sind bewusst
gesprochen („Ranken, teilen, streiten", „sieht scheiße aus wegen…"). Das gut ins
Englische zu bringen ist Schreiben, nicht Übersetzen. Wenn die Stärke der
gemeinsame Abend in einer Freundesgruppe ist, ist die Zielgruppe vermutlich
deutschsprachig — Englisch öffnet dagegen internationale Ligen. Das ist eine
Richtungsentscheidung, die vor der Fleißarbeit stehen sollte.

## 4. Bewusst nicht jetzt

- **Blind-Modus** — macht uns ähnlicher, nicht unterscheidbarer
- **Community-Voting über Fremde** — genau das Gegenteil der Positionierung
- **Bilder-Proxy mit Skalierung** (Architektur Abschnitt 5) — erst wenn Hotlinks
  brechen oder die Bytes wirklich weh tun
- **Rate-Limiting** auf den Token-Routen — vor öffentlicher Bewerbung nachziehen
- **Mail-Adapter für Produktion** — nötig, sobald jemand außer dir ein Konto braucht
