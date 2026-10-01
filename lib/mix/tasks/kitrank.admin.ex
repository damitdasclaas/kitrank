defmodule Mix.Tasks.Kitrank.Admin do
  @shortdoc "Legt ein Admin-Konto an oder befördert ein bestehendes"

  @moduledoc """
  Admin-Konten verwalten.

      mix kitrank.admin claas@example.com    # anlegen oder befördern
      mix kitrank.admin claas@example.com --password
      mix kitrank.admin claas@example.com --revoke  # Rechte entziehen
      mix kitrank.admin --list                      # alle Admins zeigen

  Es gibt bewusst keinen Weg, über die Oberfläche Admin zu werden – sonst wäre
  die geschlossene Registrierung sinnlos.

  Ohne `--password` gibt die Task einen fertigen, aber einmaligen Anmelde-Link
  aus – das war lange der einzige Weg hinein, weil es beim ersten Admin noch
  niemanden gibt, der eine Einladung verschicken könnte, und in Produktion oft
  noch kein Mailer steht.

  Mit `--password` erzeugt die Task stattdessen ein zufälliges, dauerhaftes
  Passwort und gibt es einmalig aus. **Bewusst kein eigenes Passwort als
  Argument** – das würde in der Shell-History landen und dort liegen bleiben.
  Anmelden geht danach über `/users/log-in` (E-Mail + Passwort) – eine Seite,
  die es schon gibt, aber nirgends verlinkt ist (siehe
  `KitrankWeb.Layouts.app/1`). Ein Passwort nach eigenem Geschmack setzt du
  danach eingeloggt unter `/users/settings`.

  Auf dem Server (Railway und überall sonst, wo das Release läuft):

      /app/bin/kitrank eval 'Kitrank.Release.admin("du@example.com")'
      /app/bin/kitrank eval 'Kitrank.Release.admin("du@example.com", :password)'
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

  def run([email, "--password"]) do
    password = random_password()

    with {:ok, user} <- Accounts.promote_to_admin(email),
         {:ok, {user, _expired_tokens}} <-
           Accounts.update_user_password(user, %{password: password}) do
      Mix.shell().info("#{user.email} ist jetzt Admin, mit Passwort.")
      Mix.shell().info("\nPasswort (nur jetzt sichtbar, nirgends gespeichert):\n")
      Mix.shell().info("  #{password}\n")
      Mix.shell().info("Anmelden unter #{KitrankWeb.Endpoint.url()}/users/log-in")
      Mix.shell().info("Eigenes Passwort danach unter /users/settings setzen.\n")
    else
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
      mix kitrank.admin <email> --password
      mix kitrank.admin <email> --revoke
      mix kitrank.admin --list
    """)
  end

  # 18 zufaellige Bytes, URL-sicher kodiert: 24 Zeichen, genug Entropie, dass
  # Raten keine Rolle spielt. Kein Argument, damit es nie in der Shell-History
  # landet – nur in dieser einmaligen Ausgabe.
  defp random_password do
    :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)
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
