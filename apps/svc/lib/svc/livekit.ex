defmodule Svc.LiveKit do
  @moduledoc """
  Обёртка над `livekitex` (E1, D-003): JWT access-токены для входа в комнату.
  Канал hop-by-hop DTLS-SRTP, E2EE off (D-010) — сервер доверенный.

  Конфиг (config/runtime.exs из env):
      config :svc, Svc.LiveKit,
        url: System.get_env("LIVEKIT_URL"),
        api_key: System.get_env("LIVEKIT_API_KEY"),
        api_secret: System.get_env("LIVEKIT_API_SECRET"),
        webhook_key: System.get_env("LIVEKIT_WEBHOOK_KEY")
  """
  alias Livekitex.AccessToken
  alias Livekitex.Grants.VideoGrant
  alias Svc.Accounts.User
  alias Svc.Meetings.Meeting

  @doc """
  JWT для входа пользователя в комнату встречи.
  opts: `:can_publish` (true), `:can_subscribe` (true), `:ttl` сек (3600).
  Возвращает {:ok, jwt} | {:error, :not_configured | term}.
  """
  def join_token(%User{} = user, %Meeting{} = meeting, opts \\ []) do
    with key when is_binary(key) <- config(:api_key),
         secret when is_binary(secret) <- config(:api_secret) do
      grant =
        VideoGrant.new(
          room_join: true,
          room: meeting.livekit_room_name,
          can_publish: Keyword.get(opts, :can_publish, true),
          can_subscribe: Keyword.get(opts, :can_subscribe, true),
          can_publish_data: true
        )

      token =
        key
        |> AccessToken.create(secret,
          identity: identity(user),
          name: user.full_name,
          ttl: Keyword.get(opts, :ttl, 3600)
        )
        |> AccessToken.set_video_grant(grant)

      case AccessToken.to_jwt(token) do
        {:ok, jwt, _claims} -> {:ok, jwt}
        {:error, reason} -> {:error, reason}
      end
    else
      _ -> {:error, :not_configured}
    end
  end

  @doc """
  Проверяет HMAC-подпись LiveKit-вебхука и парсит событие.
  Возвращает {:ok, event} | {:error, reason}. `event.event` — тип
  (room_started, participant_joined/left, room_finished).
  """
  def verify_webhook(raw_body, auth_header)
      when is_binary(raw_body) and is_binary(auth_header) do
    case config(:webhook_key) || config(:api_secret) do
      nil -> {:error, :not_configured}
      secret -> Livekitex.Webhook.validate_webhook(raw_body, auth_header, secret)
    end
  end

  @doc "LiveKit WS URL для клиента."
  def url, do: config(:url)

  @doc "Стабильный identity пользователя в LiveKit."
  def identity(%User{id: id}), do: "user-#{id}"

  defp config(key), do: Application.get_env(:svc, __MODULE__, [])[key]
end
