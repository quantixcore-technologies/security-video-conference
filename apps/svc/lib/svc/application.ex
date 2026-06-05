defmodule Svc.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Svc.Repo,
      {DNSCluster, query: Application.get_env(:svc, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Svc.PubSub},
      {Oban, Application.fetch_env!(:svc, Oban)}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Svc.Supervisor)
  end
end
