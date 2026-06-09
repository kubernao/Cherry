defmodule Cherry.Repo do
  use Ecto.Repo,
    otp_app: :cherry,
    adapter: Ecto.Adapters.SQLite3
end
