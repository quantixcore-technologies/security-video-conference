defmodule SvcWeb.LocaleController do
  @moduledoc "Переключение локали интерфейса — кладёт выбор в сессию и возвращает назад."
  use SvcWeb, :controller

  @doc "GET /locale/:locale — сохраняет локаль в сессии, редиректит на исходную страницу."
  def set(conn, %{"locale" => locale} = params) do
    locale = if locale in SvcWeb.Locale.supported(), do: locale, else: SvcWeb.Locale.default()

    conn
    |> put_session(:locale, locale)
    |> redirect(to: safe_return(params["return_to"] || referer_path(conn)))
  end

  defp referer_path(conn) do
    case get_req_header(conn, "referer") do
      [ref | _] -> URI.parse(ref).path
      _ -> nil
    end
  end

  # только локальный путь (защита от open-redirect)
  defp safe_return("/" <> _ = path) do
    if String.starts_with?(path, "//"), do: "/admin", else: path
  end

  defp safe_return(_), do: "/admin"
end
