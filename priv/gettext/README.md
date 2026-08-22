# Sprachen

Deutsch ist die **Quellsprache**: die `msgid` im Quelltext *ist* der deutsche
Text. Deshalb gibt es für Deutsch keinen zu pflegenden Katalog — was nicht
übersetzt ist, erscheint automatisch auf Deutsch.

```
default.pot                   Vorlage, wird erzeugt (mix gettext.extract)
en/LC_MESSAGES/default.po     Englisch — hier wird übersetzt
de/LC_MESSAGES/default.po     absichtlich leer, siehe unten
de/LC_MESSAGES/errors.po      Ecto-Meldungen auf Deutsch
en/LC_MESSAGES/errors.po      Ecto-Meldungen auf Englisch
```

## Warum `de/default.po` leer bleibt

`mix gettext.extract --merge` legt die Datei an, sobald das Verzeichnis `de/`
existiert. Sie darf leer bleiben und soll es auch: ein gefülltes
`de/default.po` wäre eine **zweite Quelle** für denselben deutschen Text und
würde den Text im Quelltext still überschreiben. Wer die deutsche Fassung
ändern will, ändert die `msgid` — also den Quelltext — und läuft danach
`mix gettext.extract --merge`.

Ein Test hält das fest (`test/kitrank_web/locale_test.exs`).

## Warum `errors.po` die Ausnahme ist

Die Meldungen der Formularprüfung kommen aus Ecto und sind englisch
(`can't be blank`). Für die ist Deutsch *nicht* die Quellsprache — deshalb
braucht die Domäne `errors` als einzige auch einen deutschen Katalog.

## Ablauf

```sh
mix gettext.extract --merge     # neue Texte einsammeln und in die .po legen
# en/LC_MESSAGES/default.po füllen — msgstr "" heisst: fällt auf Deutsch zurück
mix test test/kitrank_web/locale_test.exs
```

## Was nicht übersetzt wird

Der Admin-Bereich (`lib/kitrank_web/live/admin/`) bleibt deutsch. Ihn benutzt
die Datenpflege, nicht die Besucher; die Texte dort sind nicht in `gettext`
gewickelt und erscheinen in jeder Sprache auf Deutsch.
