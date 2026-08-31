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
    # LiveKit шлёт raw JWT (без "Bearer"), iss = api_key. livekitex Webhook.validate_webhook
    # хардкодит issuer "webhook" → обходим: верифицируем JWT через TokenVerifier с реальным api_key.
    token = String.replace_prefix(auth_header, "Bearer ", "")
    api_key = config(:api_key)
    secret = config(:webhook_key) || config(:api_secret)

    if is_nil(api_key) or is_nil(secret) do
      {:error, :not_configured}
    else
      verifier = Livekitex.TokenVerifier.new(api_key, secret)

      case Livekitex.TokenVerifier.verify(verifier, token) do
        {:ok, _claims} -> Livekitex.Webhook.parse_webhook_event(raw_body)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  E5-C: удаляет участника из комнаты LiveKit (реакция :eject). Best-effort.
  Возвращает {:ok, :removed} | {:error, reason}. Требует admin-грант (roomAdmin).
  """
  def remove_participant(room_name, identity)
      when is_binary(room_name) and is_binary(identity) do
    with key when is_binary(key) <- config(:api_key),
         secret when is_binary(secret) <- config(:api_secret),
         ws_url when is_binary(ws_url) <- config(:url),
         {:ok, jwt, _} <- admin_jwt(key, secret, room_name) do
      http_post_remove(ws_url, jwt, room_name, identity)
    else
      _ -> {:error, :not_configured}
    end
  rescue
    e -> {:error, e}
  end

  defp admin_jwt(key, secret, room_name) do
    grant = VideoGrant.new(room_admin: true, room: room_name)

    key
    |> AccessToken.create(secret, identity: "svc-admin", ttl: 60)
    |> AccessToken.set_video_grant(grant)
    |> AccessToken.to_jwt()
  end

  defp http_post_remove(ws_url, jwt, room, identity) do
    http =
      ws_url
      |> String.replace_prefix("wss://", "https://")
      |> String.replace_prefix("ws://", "http://")

    url = String.to_charlist(http <> "/twirp/livekit.RoomService/RemoveParticipant")
    body = Jason.encode!(%{room: room, identity: identity})
    headers = [{~c"authorization", String.to_charlist("Bearer " <> jwt)}]

    case :httpc.request(:post, {url, headers, ~c"application/json", body}, [], []) do
      {:ok, {{_, status, _}, _, _}} when status in 200..299 -> {:ok, :removed}
      {:ok, {{_, status, _}, _, resp}} -> {:error, {:http, status, to_string(resp)}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "LiveKit WS URL для клиента."
  def url, do: config(:url)

  @doc "Стабильный identity пользователя в LiveKit."
  def identity(%User{id: id}), do: "user-#{id}"

  defp config(key), do: Application.get_env(:svc, __MODULE__, [])[key]
end
