defmodule Kitrank.Mailer do
  @moduledoc """
  Versand der Anmelde-Mails (Magic Link, Bestätigung, Adresswechsel).

  In Entwicklung und Test landen die Mails im lokalen Postfach unter
  `/dev/mailbox` – es geht nichts nach draußen. Für Produktion muss in
  `config/runtime.exs` ein echter Adapter gesetzt werden.
  """
  use Swoosh.Mailer, otp_app: :kitrank
end
