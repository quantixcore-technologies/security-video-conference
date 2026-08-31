defmodule SvcWeb.Locale do
  @moduledoc """
  i18n: локаль интерфейса (uz/ru/en).

  - как **Plug** (HTTP-запросы): берёт локаль из сессии, ставит Gettext-локаль,
    кладёт `@locale` в assigns (для `root.html.heex` → `<html lang=...>`);
  - как **on_mount** (LiveView): та же логика для LiveView-процесса (плаги не выполняются).

  Переключение локали — `SvcWeb.LocaleController` (кладёт `:locale` в сессию).
  """
  import Plug.Conn

  @supported ~w(uz ru en)
  @default "ru"

  @doc "Поддерживаемые локали."
  def supported, do: @supported

  @doc "Локаль по умолчанию."
  def default, do: @default

  @doc "Человекочитаемое имя локали для переключателя."
  def label("uz"), do: "O'zbekcha"
  def label("ru"), do: "Русский"
  def label("en"), do: "English"
  def label(other), do: other

  defp normalize(loc) when loc in @supported, do: loc
  defp normalize(_), do: @default

  ## Plug (HTTP)

  def init(opts), do: opts

  def call(conn, _opts) do
    locale = normalize(get_session(conn, :locale) || @default)
    Gettext.put_locale(SvcWeb.Gettext, locale)
    assign(conn, :locale, locale)
  end

  ## LiveView on_mount

  def on_mount(:default, _params, session, socket) do
    locale = normalize(session["locale"] || @default)
    Gettext.put_locale(SvcWeb.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end
end
