defmodule Svc.AppReleases do
  @moduledoc """
  Автоматическое объявление новой версии мобильного приложения (D-020).

  Раз в 10 минут `AnnounceWorker` (Oban Cron) читает опубликованный манифест — тот же
  `version.json`, по которому приложение решает, обновляться ли, — и если Android
  `versionCode` в нём ещё не объявлялся, рассылает всем активным пользователям
  уведомление `:update`. Телефон забирает его фоновым `NotifyWorker` даже при закрытом
  приложении, поэтому новость доходит и до тех, кто приложение не открывает, и до
  старых сборок, которые не умеют блокироваться сами (D-017).

  «Ровно один раз» держит уникальный индекс `platform + version_code`: вставка с
  `on_conflict: :nothing` возвращает запись без id, если версия уже объявлена, и
  рассылка не начинается. Отметка и уведомления пишутся одной транзакцией: если
  рассылка упадёт, откатится и отметка, а следующий тик cron попробует снова.
  """

  import Ecto.Query
  require Logger

  alias Svc.{Notifications, Repo}
  alias Svc.Accounts.User
  alias Svc.AppReleases.Announcement

  @platform "android"
  @title "Ilovani yangilang"

  @type release :: %{
          platform: String.t(),
          version_code: pos_integer(),
          version_name: String.t(),
          mandatory?: boolean()
        }

  @doc """
  Сверяет манифест и объявляет новую версию.

  `:fetch` — функция без аргументов, возвращающая `{:ok, тело}` или `{:error, причина}`.
  По умолчанию читается `APP_RELEASE_MANIFEST_URL`; если он не задан — `:disabled`,
  чтобы локальная разработка, CI и чужие развёртывания ничего не рассылали.
  """
  @spec check_and_announce(keyword()) ::
          {:announced, non_neg_integer()} | :already_announced | :disabled | {:error, term()}
  def check_and_announce(opts \\ []) do
    case Keyword.get(opts, :fetch) || default_fetch() do
      nil ->
        :disabled

      fetch ->
        with {:ok, body} <- fetch.(),
             {:ok, release} <- decode_manifest(body) do
          announce(release)
        end
    end
  end

  @doc "Разбирает манифест — строку JSON или уже декодированную карту."
  @spec decode_manifest(binary() | map()) :: {:ok, release()} | {:error, term()}
  def decode_manifest(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, map} -> decode_manifest(map)
      {:error, _} -> {:error, :invalid_json}
    end
  end

  def decode_manifest(%{"versionCode" => code} = manifest) when is_integer(code) and code > 0 do
    min = manifest["minVersionCode"]

    {:ok,
     %{
       platform: @platform,
       version_code: code,
       version_name: manifest["versionName"] || Integer.to_string(code),
       # Новая версия сама стала минимальной → все, кто ниже, заблокированы (D-017).
       mandatory?: is_integer(min) and min >= code
     }}
  end

  def decode_manifest(_), do: {:error, :invalid_manifest}

  @doc "Объявляет версию: одна отметка в реестре и уведомление каждому активному пользователю."
  @spec announce(release()) ::
          {:announced, non_neg_integer()} | :already_announced | {:error, term()}
  def announce(%{platform: platform, version_code: code, version_name: name} = release) do
    Repo.transaction(fn ->
      changeset =
        Announcement.changeset(%Announcement{}, %{
          platform: platform,
          version_code: code,
          version_name: name
        })

      case Repo.insert(changeset,
             on_conflict: :nothing,
             conflict_target: [:platform, :version_code]
           ) do
        {:ok, %Announcement{id: nil}} ->
          Repo.rollback(:already_announced)

        {:ok, announcement} ->
          count = notify_active_users(body(release))
          announcement |> Ecto.Changeset.change(notified_count: count) |> Repo.update!()
          Logger.info("app release #{platform} #{name} (#{code}) announced to #{count} users")
          count

        {:error, changeset} ->
          Repo.rollback({:invalid, changeset.errors})
      end
    end)
    |> case do
      {:ok, count} -> {:announced, count}
      {:error, :already_announced} -> :already_announced
      {:error, reason} -> {:error, reason}
    end
  end

  defp notify_active_users(body) do
    users =
      Repo.all(
        from u in User,
          where: u.status == :active,
          # Только id/org_id: без зашифрованных полей (Cloak) и без лишнего чтения.
          select: struct(u, [:id, :org_id])
      )

    Enum.each(users, fn user ->
      case Notifications.notify(user, :update, @title, body: body) do
        {:ok, _} ->
          :ok

        # Молча потерянное уведомление хуже повтора: откатываем всё, cron повторит.
        {:error, changeset} ->
          Repo.rollback({:notify_failed, user.id, changeset.errors})
      end
    end)

    length(users)
  end

  defp body(%{version_name: name, mandatory?: true}),
    do:
      "SVC Android ilovasining yangi versiyasi (#{name}) chiqdi. Davom etish uchun ilovani oching va yangilang."

  defp body(%{version_name: name}),
    do:
      "SVC Android ilovasining yangi versiyasi (#{name}) chiqdi. Yangilash uchun ilovani oching."

  defp default_fetch do
    case Application.get_env(:svc, __MODULE__, [])[:manifest_url] do
      url when is_binary(url) and url != "" -> fn -> fetch_manifest(url) end
      _ -> nil
    end
  end

  defp fetch_manifest(url) do
    # ts — мимо кэша Cloudflare. Тело берём сырым: nginx может отдать version.json
    # не как application/json, а разбор у нас один — decode_manifest/1.
    case Req.get(url,
           params: [ts: System.system_time(:second)],
           decode_body: false,
           retry: false,
           receive_timeout: 15_000
         ) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, exception} -> {:error, {:transport, Exception.message(exception)}}
    end
  end
end
