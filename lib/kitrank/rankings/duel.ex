defmodule Kitrank.Rankings.Duel do
  @moduledoc """
  Eine Rangliste durch Zweikämpfe sortieren: zwei Trikots, du wählst eines,
  weiter bis die Reihenfolge steht.

  Verfahren ist **binäres Einfügen**. Der bereits sortierte Teil bleibt
  sortiert; jedes neue Trikot wird per Halbierungssuche eingeordnet. Das kostet
  rund `n · log₂ n` Fragen — bei 18 Trikots etwa 55, bei 40 etwa 210.

  Warum nicht Elo oder Zufallspaarungen: die brauchen ein Vielfaches an
  Vergleichen und liefern trotzdem keine garantiert vollständige Ordnung. Hier
  war die Vorgabe "bis eine Rangliste steht" — das ist eine Sortierung, kein
  Bewertungssystem.

  Der Zustand ist bewusst reine Datenstruktur ohne Datenbankbezug: so lässt
  sich das Verfahren prüfen, ohne eine Oberfläche zu bedienen.

  Zwischendurch ist `order/1` immer eine gültige Reihenfolge — der sortierte
  Teil vorn, der noch nicht befragte dahinter. Abbrechen ist deshalb jederzeit
  möglich, ohne dass etwas verloren geht.
  """

  @enforce_keys [:sorted, :pending, :current, :lo, :hi, :comparisons]
  defstruct [:sorted, :pending, :current, :lo, :hi, :comparisons]

  @type t :: %__MODULE__{}

  @doc """
  Startet mit einer Ausgangsreihenfolge. Das erste Trikot gilt als gesetzt —
  ein einzelnes Element ist immer sortiert.
  """
  def start(kit_ids) when is_list(kit_ids) do
    case Enum.uniq(kit_ids) do
      [] ->
        %__MODULE__{sorted: [], pending: [], current: nil, lo: 0, hi: 0, comparisons: 0}

      [einziges] ->
        %__MODULE__{sorted: [einziges], pending: [], current: nil, lo: 0, hi: 0, comparisons: 0}

      [erstes | rest] ->
        %__MODULE__{
          sorted: [erstes],
          pending: rest,
          current: nil,
          lo: 0,
          hi: 0,
          comparisons: 0
        }
        |> naechstes_trikot()
    end
  end

  @doc """
  Die nächste Frage als `{neues, vergleich}` – oder `:done`.

  `neues` ist das Trikot, das einsortiert wird, `vergleich` das aus dem
  sortierten Teil, gegen das es antritt.
  """
  def question(%__MODULE__{current: nil}), do: :done

  def question(%__MODULE__{current: current} = state) do
    {current, Enum.at(state.sorted, mid(state))}
  end

  @doc """
  Antwort verbuchen: `:new` heißt, das neue Trikot ist besser, `:existing` das
  bisherige.
  """
  def answer(%__MODULE__{current: nil} = state, _wahl), do: state

  def answer(%__MODULE__{} = state, wahl) when wahl in [:new, :existing] do
    m = mid(state)

    state =
      case wahl do
        # Besser heißt weiter vorn – die Suche geht in die vordere Hälfte.
        :new -> %{state | hi: m}
        :existing -> %{state | lo: m + 1}
      end

    state = %{state | comparisons: state.comparisons + 1}

    if state.lo >= state.hi, do: einfuegen(state), else: state
  end

  @doc """
  Die beste bekannte Reihenfolge: sortierter Teil, dann das gerade befragte
  Trikot, dann der Rest.

  Auch mitten im Verfahren eine gültige Rangliste – abbrechen kostet nichts.
  """
  def order(%__MODULE__{} = state) do
    state.sorted ++ Enum.reject([state.current | state.pending], &is_nil/1)
  end

  @doc "Wie weit es ist: `%{placed:, total:, comparisons:, remaining_estimate:}`."
  def progress(%__MODULE__{} = state) do
    total = length(order(state))
    platziert = length(state.sorted)

    %{
      placed: platziert,
      total: total,
      comparisons: state.comparisons,
      remaining_estimate: schaetzung(platziert, total)
    }
  end

  def done?(%__MODULE__{current: nil}), do: true
  def done?(_), do: false

  defp mid(%__MODULE__{lo: lo, hi: hi}), do: div(lo + hi, 2)

  defp einfuegen(%__MODULE__{} = state) do
    %{state | sorted: List.insert_at(state.sorted, state.lo, state.current)}
    |> naechstes_trikot()
  end

  defp naechstes_trikot(%__MODULE__{pending: []} = state) do
    %{state | current: nil, lo: 0, hi: 0}
  end

  defp naechstes_trikot(%__MODULE__{pending: [naechstes | rest]} = state) do
    %{state | current: naechstes, pending: rest, lo: 0, hi: length(state.sorted)}
  end

  # Grobe Schaetzung der restlichen Fragen: jedes offene Trikot braucht etwa
  # log2 der bisherigen Laenge. Gedacht als Orientierung, nicht als Versprechen.
  defp schaetzung(platziert, total) when total > platziert do
    platziert..(total - 1)
    |> Enum.map(fn n -> max(1, ceil(:math.log2(max(n, 2)))) end)
    |> Enum.sum()
  end

  defp schaetzung(_platziert, _total), do: 0
end
