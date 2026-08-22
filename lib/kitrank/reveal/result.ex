defmodule Kitrank.Reveal.Result do
  @moduledoc """
  Die Auswertung nach dem Aufdecken: worin sich die Gruppe einig war und worin
  überhaupt nicht.

  Der Punkt ist die Reibung, nicht der Durchschnitt. Ein Mittelwert über eine
  Freundesgruppe ist so aussagekräftig wie einer über Fremde — interessant ist
  die Zeile "Tom Platz 1, Anna Platz 18".

  Verglichen wird nur, was **alle** bewertet haben. Sonst hätte ein Trikot, das
  bloß eine Person kennt, automatisch die größte Einigkeit.
  """

  @doc """
  Baut die Auswertung aus den Ranglisten des Raums.

  `entries_by_participant` ist `%{participant_id => [entry]}` in Rangfolge,
  `participants` die Teilnehmer in Anzeigereihenfolge.
  """
  def build(participants, entries_by_participant) do
    plaetze = plaetze_je_teilnehmer(entries_by_participant)
    gemeinsam = gemeinsame_trikots(plaetze, participants)

    trikots =
      gemeinsam
      |> Enum.map(&trikot_auswertung(&1, plaetze, participants, entries_by_participant))
      # Bei gleichem Mittelwert zaehlt die geringere Streuung: darueber war die
      # Gruppe sich einiger. Die kit_id zuletzt, damit die Reihenfolge stabil
      # bleibt und nicht bei jedem Aufruf anders aussieht.
      |> Enum.sort_by(&{&1.average, &1.spread, &1.kit_id})

    %{
      participants: participants,
      shared_count: length(gemeinsam),
      kits: trikots,
      consensus_top: Enum.take(trikots, 3),
      consensus_bottom: trikots |> Enum.reverse() |> Enum.take(3),
      biggest_split: Enum.max_by(trikots, & &1.spread, fn -> nil end),
      pairs: paare(plaetze, participants, gemeinsam),
      notes: notizen(participants, entries_by_participant)
    }
  end

  # Position eines Trikots je Teilnehmer – die Position im Ausschnitt, nicht die
  # in der ganzen Rangliste.
  defp plaetze_je_teilnehmer(entries_by_participant) do
    Map.new(entries_by_participant, fn {participant_id, entries} ->
      positionen =
        entries
        |> Enum.with_index(1)
        |> Map.new(fn {entry, position} -> {entry.kit_id, position} end)

      {participant_id, positionen}
    end)
  end

  defp gemeinsame_trikots(_plaetze, []), do: []

  defp gemeinsame_trikots(plaetze, participants) do
    participants
    |> Enum.map(&(plaetze |> Map.get(&1.id, %{}) |> Map.keys() |> MapSet.new()))
    |> Enum.reduce(&MapSet.intersection/2)
    |> MapSet.to_list()
  end

  defp trikot_auswertung(kit_id, plaetze, participants, entries_by_participant) do
    je_teilnehmer =
      Enum.map(participants, fn p ->
        %{
          participant_id: p.id,
          participant_name: p.display_name,
          position: plaetze[p.id][kit_id]
        }
      end)

    positionen = Enum.map(je_teilnehmer, & &1.position)

    %{
      kit_id: kit_id,
      kit: beispiel_kit(kit_id, entries_by_participant),
      positions: Enum.sort_by(je_teilnehmer, & &1.position),
      average: Enum.sum(positionen) / length(positionen),
      spread: Enum.max(positionen) - Enum.min(positionen),
      best: Enum.min(positionen),
      worst: Enum.max(positionen)
    }
  end

  # Das Trikot selbst steht in jedem Eintrag – einer reicht.
  defp beispiel_kit(kit_id, entries_by_participant) do
    entries_by_participant
    |> Map.values()
    |> Enum.flat_map(& &1)
    |> Enum.find_value(fn entry -> if entry.kit_id == kit_id, do: entry.kit end)
  end

  # Wie nah zwei Leute beieinanderliegen: mittlerer Abstand der Plätze. 0 heisst
  # identische Ranglisten. Bewusst kein Korrelationskoeffizient – "im Schnitt
  # drei Plätze auseinander" versteht man ohne Statistikkurs.
  defp paare(_plaetze, participants, _gemeinsam) when length(participants) < 2, do: []

  defp paare(plaetze, participants, gemeinsam) do
    for {a, i} <- Enum.with_index(participants),
        {b, j} <- Enum.with_index(participants),
        j > i do
      abstaende = Enum.map(gemeinsam, &abs(plaetze[a.id][&1] - plaetze[b.id][&1]))

      %{
        a: a.display_name,
        b: b.display_name,
        distance: if(abstaende == [], do: nil, else: Enum.sum(abstaende) / length(abstaende))
      }
    end
    |> Enum.reject(&is_nil(&1.distance))
    |> Enum.sort_by(& &1.distance)
  end

  defp notizen(participants, entries_by_participant) do
    for p <- participants,
        {entry, position} <- Enum.with_index(Map.get(entries_by_participant, p.id, []), 1),
        is_binary(entry.note),
        String.trim(entry.note) != "" do
      %{
        participant_name: p.display_name,
        position: position,
        kit: entry.kit,
        note: String.trim(entry.note)
      }
    end
  end
end
