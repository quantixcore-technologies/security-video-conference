defmodule SvcWeb.CacheBodyReader do
  @moduledoc """
  Кэширует raw body для путей `/webhooks/*` — нужно для проверки HMAC-подписи
  LiveKit-вебхуков (E1). Для остальных путей — обычное чтение.
  """
  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)

    conn =
      if String.starts_with?(conn.request_path, "/webhooks/") do
        Plug.Conn.put_private(conn, :raw_body, body)
      else
        conn
      end

    {:ok, body, conn}
  end
end
