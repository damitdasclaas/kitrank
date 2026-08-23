defmodule Kitrank.Release do
  @moduledoc """
  Aufgaben, die in Produktion laufen müssen, wo es kein Mix gibt.

  Aufruf auf dem Server:

      /app/bin/kitrank eval 'Kitrank.Release.migrate()'
      /app/bin/kitrank eval 'Kitrank.Release.admin("du@example.com")'
      /app/bin/kitrank eval 'Kitrank.Release.import_teams()'
  """
  @app :kitrank

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Spielt die Stammdaten einer Saison ein – Vereine, Ligen, Zuordnungen.

  Die Datei liegt im Release unter `priv/data/`. Trikots gehören nicht dazu,
  die pflegst du über `/admin`.
  """
  def import_teams(path \\ nil) do
    start_app()

    case Kitrank.Kits.Import.run(path) do
      {:ok, bericht} ->
        IO.puts("\n" <> Kitrank.Kits.Import.format(bericht))
        :ok

      {:error, grund} ->
        IO.puts("Import fehlgeschlagen: #{grund}")
        :error
    end
  end

  @doc """
  Holt die kleinen Bildvarianten für bestehende Trikots nach.

      /app/bin/kitrank eval "Kitrank.Release.thumbs(write: true)"
  """
  def thumbs(opts \\ []) do
    start_app()
    Kitrank.Kits.Thumbs.run(opts)
  end

  @doc """
  Legt ein Admin-Konto an oder befördert ein bestehendes und gibt einen
  fertigen Anmelde-Link aus.

  Das Gegenstück zu `mix kitrank.admin` für den Server. Es gibt bewusst keinen
  Weg über die Oberfläche, Admin zu werden — und beim ersten Admin gibt es
  niemanden, der eine Einladung verschicken könnte.
  """
  def admin(email) when is_binary(email) do
    start_app()

    case Kitrank.Accounts.promote_to_admin(email) do
      {:ok, user} ->
        {token, user_token} = Kitrank.Accounts.UserToken.build_email_token(user, "login")
        Kitrank.Repo.insert!(user_token)

        IO.puts("\n#{user.email} ist jetzt Admin.\n")
        IO.puts("Anmelden über diesen Link (einmalig, läuft ab):\n")
        IO.puts("  #{KitrankWeb.Endpoint.url()}/users/log-in/#{token}\n")
        :ok

      {:error, changeset} ->
        IO.puts("Ging nicht: #{inspect(changeset.errors)}")
        :error
    end
  end

  @doc "Alle Admin-Konten auflisten."
  def admins do
    start_app()

    case Kitrank.Accounts.list_admins() do
      [] -> IO.puts("Noch kein Admin-Konto.")
      admins -> Enum.each(admins, &IO.puts("  #{&1.email}"))
    end
  end

  # migrate/0 kommt mit einem geladenen Repo aus; admin/1 braucht die laufende
  # Anwendung, weil es den Endpoint fuer die URL und den Mailer-Kontext nutzt.
  defp start_app do
    Application.ensure_all_started(:ssl)
    {:ok, _} = Application.ensure_all_started(@app)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
