defmodule Kitrank.Reveal.Cleanup do
  @moduledoc """
  Löscht abgelaufene Reveal-Räume in regelmäßigen Abständen.

  Ein eigener Prozess statt Oban: es gibt genau eine wiederkehrende Aufgabe,
  sie muss nicht zuverlässig genau einmal laufen, und ein verpasster Durchgang
  holt beim nächsten Mal alles nach. Eine Job-Queue mit eigenen Tabellen wäre
  dafür mehr Apparat als Nutzen.

  Räume laufen nach `expires_at` ab und liefern dann 404 — gelöscht werden sie
  hier. Die Ranglisten der Teilnehmer bleiben unberührt; verknüpft war nur die
  Teilnahme.

  Der erste Durchgang läuft verzögert, damit der Start der Anwendung nicht auf
  eine Datenbankabfrage wartet.
  """
  use GenServer

  require Logger

  alias Kitrank.Reveal

  @default_interval :timer.hours(1)
  @initial_delay :timer.seconds(30)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  @doc "Läuft sofort, unabhängig vom Takt – für Tests und die Konsole."
  def run_now(server \\ __MODULE__), do: GenServer.call(server, :run_now)

  @impl true
  def init(opts) do
    interval =
      opts[:interval] ||
        Application.get_env(:kitrank, :reveal_cleanup_interval, @default_interval)

    Process.send_after(self(), :cleanup, opts[:initial_delay] || @initial_delay)

    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    sweep()
    Process.send_after(self(), :cleanup, state.interval)

    {:noreply, state}
  end

  @impl true
  def handle_call(:run_now, _from, state), do: {:reply, sweep(), state}

  defp sweep do
    count = Reveal.delete_expired_rooms()

    # Nur melden, wenn es etwas zu melden gibt – ein stündliches "0 gelöscht"
    # macht das Log unlesbar.
    if count > 0 do
      Logger.info("Reveal-Aufräumen: #{count} abgelaufene(r) Raum/Räume gelöscht")
    end

    count
  rescue
    # Ein Datenbankausfall soll den Prozess nicht in eine Neustart-Schleife
    # schicken; beim nächsten Takt wird es erneut versucht.
    error ->
      Logger.warning("Reveal-Aufräumen fehlgeschlagen: #{Exception.message(error)}")
      0
  end
end
