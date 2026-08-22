defmodule Mix.Tasks.Kitrank.Admin do
  @shortdoc "Legt ein Admin-Konto an oder befördert ein bestehendes"

  @moduledoc """
  Admin-Konten verwalten.

      mix kitrank.admin claas@example.com          # anlegen oder befördern
      mix kitrank.admin claas@example.com --revoke # Rechte entziehen
      mix kitrank.admin --list                     # alle Admins zeigen

  Es gibt bewusst keinen Weg, über die Oberfläche Admin zu werden – sonst wäre
  die geschlossene Registrierung sinnlos.

  Die Task gibt am Ende einen fertigen Anmelde-Link aus. Das ist der Grund,
  warum sie existiert: beim ersten Admin gibt es noch niemanden, der eine
  Einladung verschicken könnte, und in Produktion steht oft noch kein Mailer.

  Auf dem Server (Railway und überall sonst, wo das Release läuft):

      /app/bin/kitrank eval 'Kitrank.Release.admin("du@example.com")'
  """
  use Mix.Task

  alias Kitrank.Accounts
  alias Kitrank.Accounts.UserToken
  alias Kitrank.Repo

  @requirements ["app.start"]

  @impl Mix.Task
  def run(["--list"]) do
    case Accounts.list_admins() do
      [] ->
        Mix.shell().info("Noch kein Admin-Konto. Anlegen mit: mix kitrank.admin <email>")

      admins ->
        Mix.shell().info("Admins:")
        Enum.each(admins, &Mix.shell().info("  #{&1.email}"))
    end
  end

  def run([email, "--revoke"]) do
    case Accounts.revoke_admin(email) do
      {:ok, user} -> Mix.shell().info("#{user.email} ist kein Admin mehr.")
      {:error, :not_found} -> Mix.raise("Kein Konto mit der Adresse #{email}.")
      {:error, changeset} -> Mix.raise(errors(changeset))
    end
  end

  def run([email]) do
    case Accounts.promote_to_admin(email) do
      {:ok, user} ->
        Mix.shell().info("#{user.email} ist jetzt Admin.")
        Mix.shell().info("\nAnmelden über diesen Link (einmalig, läuft ab):\n")
        Mix.shell().info("  #{login_url(user)}\n")

      {:error, changeset} ->
        Mix.raise(errors(changeset))
    end
  end

  def run(_args) do
    Mix.raise("""
    Aufruf:
      mix kitrank.admin <email>
      mix kitrank.admin <email> --revoke
      mix kitrank.admin --list
    """)
  end

  # Derselbe Magic-Link, den sonst die Anmelde-Mail enthaelt – nur direkt auf der
  # Kommandozeile ausgegeben, damit der erste Admin ohne funktionierenden Mailer
  # hineinkommt.
  defp login_url(user) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)

    "#{KitrankWeb.Endpoint.url()}/users/log-in/#{encoded_token}"
  end

  defp errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end
end
