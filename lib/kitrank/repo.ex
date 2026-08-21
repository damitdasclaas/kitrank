defmodule Kitrank.Repo do
  use Ecto.Repo,
    otp_app: :kitrank,
    adapter: Ecto.Adapters.Postgres
end
