# Plan: Sportarten, Ranglisten-Ausschnitte, Konten

**Arbeitspapier, kein Dauerdokument.** Wird gelöscht, wenn die fünf Vorhaben
durch sind. Was davon dauerhaft gilt, wandert vorher nach `architecture.md`
oder `roadmap.md`.

Stand: 27.08.2026.

---

## Warum überhaupt

Die App war für eine Sportart mit zwei Ligen gebaut. Mit der NFL sind es zwei
Sportarten, drei Ligen und 68 Vereine — und an drei Stellen merkt man, dass
das Modell darauf nicht ausgelegt war:

* **Trikot-Kategorien sind global.** „Ausweichtrikot" gibt es in der NFL nicht,
  „Throwback" im Fußball nicht.
* **Die Startseite zeigt alles auf einmal.** Deshalb stehen die Ligen seit
  neuestem zugeklappt da — eine Notlösung für ein Struktur-Problem.
* **Ranglisten-Einstellungen sind flüchtig.** `init_scope` baut sie beim Laden
  aus den vorhandenen Einträgen neu zusammen. Tab zu, Einstellungen weg.

---

## 1. Sportart-Routing — **fertig**

Startseite wird eine Sportart-Auswahl, die Übersicht hängt darunter:

```
/                      Sportart-Auswahl
/football              Übersicht Fußball
/football/teams/:id    Verein-Detail
/football/vergleich    Direktvergleich
/nfl                   Übersicht NFL
```

**Entschieden:**

* **Der Direktvergleich bleibt sportartübergreifend.** Ein Bundesliga-Trikot
  gegen ein NFL-Trikot zu stellen ist eine der wenigen Sachen, die diese App
  kann und trikotranking.de nicht — die gibt man nicht für sauberes Routing auf.
  Die Sportart im Pfad sagt nur, wohin das Schließen zurückführt; der Inhalt
  darf darüber hinausgehen. Technisch heißt das: die verglichenen Trikots
  werden direkt über ihre IDs geladen, nicht aus der (sportartgefilterten)
  Übersicht.
* **Slug-Sperrliste am `Sport`-Changeset.** `/:sport` ganz unten im Router
  fängt sonst alles ab, was davor nicht gepasst hat. Eine Sportart mit dem
  Slug `reveal` würde die Reveal-Seite still verschlucken. Die Route zuletzt zu
  deklarieren reicht nicht — es braucht die Sperrliste dazu.
* **Die Collapsables fallen weg.** Mit einer Sportart pro Seite sind zwei bis
  drei Ligen wieder alle aufgeklappt zeigbar.

**Nebeneffekt:** `/football`, `/nfl` sind genau die SEO-Landingpages, die in
der Roadmap als Lücke der Konkurrenz gegenüber stehen.

---

## 2. Trikot-Kategorien pro Sportart — **fertig**

**So gebaut:** `sports.kit_types` (Array) und `sports.special_label`. Die
globale Liste in `Kit.kit_types/0` bleibt der erlaubte Wertebereich; die
Sportart bestimmt, was angeboten und wie es benannt wird.

**Eine Entscheidung anders als geplant:** die Beschriftung von Sondertrikots
steht als Freitext an der Sportart, nicht als Gettext-Klausel je Sportart. Eine
Klausel hinge am Slug — und der ist Daten, die im Admin geändert werden dürfen.
Eine Umbenennung würde die Beschriftung still auf die Vorgabe zurückfallen
lassen, ohne dass jemand es merkt. Preis dafür: „Alternate" steht auch auf der
englischen Seite so da, was hier passt, weil der Begriff in beiden Sprachen
derselbe ist.

**Dazugekommen:** `mix kitrank.aufraeumen` meldet und löscht Trikots, deren
Kategorie ihre Sportart abgelegt hat. Gelöscht wird nur, was kein Bild, keinen
Shop-Link, keinen Namen und keine Ranglisten-Einträge hat — der Fremdschlüssel
steht auf `delete_all`, ein Trikot mit Einträgen zu löschen würde es still aus
fremden Ranglisten entfernen.

Der Rest dieses Abschnitts ist die ursprüngliche Überlegung.

---

Das Datenmodell kann es im Kern schon: seit `allow_multiple_special_kits` gibt
es von Heim/Auswärts/Ausweich genau eins pro Verein und Saison, von `special`
beliebig viele mit Pflichtnamen. Das ist die Form, die die NFL braucht —
„Alternate Weiß" und „Throwback 1994" sind zwei benannte Sondertrikots.

Der Unterschied zwischen den Sportarten ist also **nicht die Struktur, sondern
welche Kategorien angeboten werden und wie sie heißen**:

```
Fußball  home, away, third  + Sonder ("Sondertrikot")
NFL      home, away         + Sonder ("Alternate")
```

**Vorgehen:** Spalte `kit_types` an `sports`. Die globale Liste in
`Kit.kit_types/0` bleibt der erlaubte Wertebereich; die Sportart bestimmt nur,
was Admin-Formular und Filter anbieten.

**Warum nicht als Constraint:** die Validierung müsste die Sportart des Trikots
kennen, und die hängt transitiv über Verein → Saison-Zuordnung → Liga. Das
macht den Kit-Changeset von einem Join abhängig und einen Verein in zwei
Sportarten zum Sonderfall. Die Import-Dateien sind pro Sportart und werden
gelesen — das Risiko ist klein genug.

**Fummelig:** `KitLabel` hält die Beschriftungen bewusst als Gettext-Literale
im Quelltext. Pro Sportart heißt: mehr Klauseln, keine Nachschlagetabelle.

**Aufräumen dabei:** `nfl_2026_27.json` deklariert `kit_types: [home, away,
third]`. Die 32 Ausweich-Platzhalter müssen weg — sie sind leer, also
unkritisch.

---

## 3. Ranglisten-Ausschnitt speichern — **fertig**

**So gebaut:** `Kitrank.Kits.Scope` als gemeinsamer Begriff mit vier Achsen —
Saisons, Ligen, Vereine, Trikot-Typen; jede leere Liste heißt „keine
Einschränkung". Vier Spalten `scope_*` an `rankings`, geschrieben bei jeder
Änderung statt erst am Ende. Das Reveal baut seinen Ausschnitt jetzt aus
denselben Bausteinen und hat seine eigene Abfrage verloren.

**Die Typ-Achse ist dazugekommen** — vorher ließ sich „alle Auswärtstrikots
dieser vier Vereine" gar nicht ausdrücken.

**Eine Entscheidung:** ein leerer Ausschnitt heißt „alles", auch für alte
Ranglisten, deren Einstellungen es nie gab. Das ist der ehrlichste Ersatz für
„wir wissen es nicht mehr". Eine frische Liste startet dagegen bei der
laufenden Saison — aber als gespeicherte Entscheidung, nicht als
Zufallsergebnis des Ladens.

Der Rest dieses Abschnitts ist die ursprüngliche Überlegung.

---

Heute ist der Ausschnitt flüchtig (`init_scope`). Es gibt nichts zu teilen,
weil es nichts gibt.

**Präzedenzfall im Projekt:** `reveal_rooms` speichert genau so einen
Ausschnitt — `season`, `competition_ids`, `kit_types`. Dasselbe an `rankings`
ist eine Migration.

**Echte Lücke, die dabei auffällt:** „Auswärtstrikot von HSV, Heidenheim,
Dortmund, Bremen" braucht zwei Achsen gleichzeitig — Vereine *und* Trikot-Typ.
`list_kits_for_scope` kennt heute Saisons, Ligen und Vereine, **keinen
Trikot-Typ**. Und die Auswahl-Oberfläche hat für Typen nur eine Schnellauswahl
zum Massen-Anhaken, keinen Filter. Beides muss dazu, sonst lässt sich das
Beispiel gar nicht abbilden.

**Gleich mit aufräumen:** Reveal sagt `season` (Einzahl) und `kit_types`,
`list_kits_for_scope` sagt `seasons` (Mehrzahl) und `team_ids`. Zwei
Ausschnitt-Begriffe nebeneinander laufen garantiert auseinander — einer davon
muss gewinnen.

---

## 4. Suchbare Mehrfachauswahl bei der Vereinsauswahl

Alle Vereine als Pillen ist bei 68 (und wachsend) unbrauchbar. Gebraucht wird
eine **Multi-Select-Combobox**: Textfeld, das filtert, Treffer darunter,
Gewähltes als abwählbare Chips.

Die Teile liegen schon rum: `KitrankWeb.Search.matches?/2` macht die
umlautnachsichtige Suche, die Suchleiste der Startseite ist dieselbe Form. Neu
ist nur Trefferliste plus Chips.

**Der Aufwand steckt in der Tastaturbedienung** — Pfeiltasten, Enter, Escape,
Fokus. Daran scheitern handgebaute Comboboxen üblicherweise. Entscheidung
vertagt: erst die einfache Fassung (klicken, Enter nimmt den ersten Treffer),
ARIA-vollständig nur, wenn es sich als nötig erweist.

Mit Punkt 1 schrumpft die Liste ohnehin auf eine Sportart.

---

## 5. Geteilter Link mit Zwang zur eigenen Rangliste

`share_mode` an `rankings` (`offen` | `erst selber`), plus `abgeleitet_von`,
damit das Gate weiß, welche eigene Rangliste die fremde freischaltet.

**Drei Sachen, die vorher zu klären sind:**

* **Wer ist „der Empfänger"?** Ranglisten haben bewusst kein Login, nur Tokens.
  Der `RememberRanking`-Hook mit localStorage ist da — aber das ist eine
  **Höflichkeitsschranke, keine Sicherheitsgrenze**. Inkognito-Fenster, und die
  Sperre ist weg. Für einen Abend unter Freunden reicht das; es sollte nur
  niemand glauben, es sei dicht. Wer es dicht will, braucht Konten (Punkt 6).
* **Wann gilt die eigene als fertig?** Vorschlag: alle Trikots des Ausschnitts
  platziert — prüfbar über Anzahl Einträge gegen Anzahl Trikots im Ausschnitt.
* **Das ist inhaltlich fast das Reveal.** Das Reveal macht „alle ranken
  denselben Ausschnitt, dann wird verglichen" — synchron, im Raum. Das hier ist
  dieselbe Idee asynchron und eins-zu-viele. **Nicht danebenbauen**: denselben
  Ausschnitt-Begriff nehmen und prüfen, ob die Auswertung wiederverwendbar ist.

---

## 6. Konten — vorbereitet, nicht scharf

**Die Registrierung ist vollständig gebaut und zu.** Der Schalter ist
`Application.get_env(:kitrank, :registration_open, false)`, geprüft in
`Kitrank.Accounts.registration_open?/0`, bewacht von
`UserAuth.require_open_registration`. Ein Test hält beides fest: dass sie zu
ist, und dass Aufmachen wirklich nur der Schalter ist.

**Gedacht als:** Ranglisten funktionieren weiter ohne Konto — der Token-Weg
bleibt der Hauptweg, das ist die Haltung der App. Ein Konto kauft nur dazu:

* Ranglisten geräteübergreifend wiederfinden statt per localStorage
* ein Gate, das ein Inkognito-Fenster aushält (Punkt 5)

**Wo Hinweise hingehören:** dort, wo der Token-Weg an seine Grenze stößt — bei
den gemerkten Ranglisten („In diesem Browser gemerkt") und beim Teilen mit
Gate. Nicht als Sperre, sondern als Angebot: „Um deine Ranglisten auf allen
Geräten wiederzufinden, leg ein Konto an."

**Nicht jetzt.** Erst wenn Punkt 5 zeigt, wofür das Konto wirklich gebraucht
wird — sonst baut man eine Anmeldung ohne Anlass.

---

## Reihenfolge

1. ~~**Sportart-Routing**~~ — fertig.
2. ~~**Trikot-Kategorien pro Sportart**~~ — fertig.
3. ~~**Ausschnitt speichern + Typ-Achse**~~ — fertig.
4. **Multi-Select** — unabhängig, kann auch vorgezogen werden.
5. **Geteilter Link mit Gate** — zuletzt, hier sitzen die Produktfragen.
6. **Konten** — erst wenn 5 den Anlass geliefert hat.
