defmodule Svc.Repo do
  use Ecto.Repo,
    otp_app: :svc,
    adapter: Ecto.Adapters.Postgres
end
