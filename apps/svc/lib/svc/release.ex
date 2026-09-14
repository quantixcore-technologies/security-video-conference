defmodule Svc.Release do
  @moduledoc """
  Релизные задачи (миграции БД) для собранного релиза, где `mix` недоступен.

      bin/svc eval "Svc.Release.migrate()"
      bin/svc eval "Svc.Release.rollback(Svc.Repo, VERSION)"
  """
  @app :svc
  @repos [Svc.Repo]

  def migrate do
    load_app()

    for repo <- @repos do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp load_app do
    Application.load(@app)
  end
end
