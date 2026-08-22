defmodule Kitrank.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      KitrankWeb.Telemetry,
      Kitrank.Repo,
      {DNSCluster, query: Application.get_env(:kitrank, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Kitrank.PubSub},
      KitrankWeb.Presence,
      Kitrank.Reveal.Cleanup,
      # Start to serve requests, typically the last entry
      KitrankWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Kitrank.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    KitrankWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
