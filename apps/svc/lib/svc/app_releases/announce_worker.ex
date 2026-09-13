defmodule Svc.AppReleases.AnnounceWorker do
  @moduledoc """
  Oban Cron: раз в 10 минут сверяет опубликованный манифест приложения и объявляет
  новую версию (D-020).

  Ретраи не нужны — следующий тик cron и есть повтор, а дубликатов не будет благодаря
  уникальному индексу в `app_release_announcements`.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 1, unique: [period: 300]

  require Logger
  alias Svc.AppReleases

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case AppReleases.check_and_announce() do
      {:error, reason} ->
        Logger.warning("app release check failed: #{inspect(reason)}")
        {:error, reason}

      _announced_already_or_disabled ->
        :ok
    end
  end
end
