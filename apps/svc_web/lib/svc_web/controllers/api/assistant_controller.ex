defmodule SvcWeb.API.AssistantController do
  @moduledoc """
  API встроенного помощника (S37) — общий для веб-панели, Android и Tauri.

  Контент и логика поиска живут на сервере в одном месте: три клиента с
  собственными копиями справки разъехались бы после первого же изменения
  продукта, а обновить Android у всех сразу нельзя.
  """
  use SvcWeb, :controller

  alias Svc.Assistant
  alias Svc.Assistant.Entry
  alias SvcWeb.Locale

  @doc "Стартовые подсказки — показываются до первого вопроса."
  def suggestions(conn, params) do
    user = conn.assigns.current_user
    locale = locale_from(params)

    json(conn, %{
      locale: locale,
      suggestions: render_many(Assistant.suggestions(role: user.role), locale)
    })
  end

  @doc "Вопрос пользователя."
  def ask(conn, params) do
    user = conn.assigns.current_user
    locale = locale_from(params)
    question = params["question"] || params["q"] || ""

    case Assistant.ask(question, role: user.role) do
      {:ok, entry, related} ->
        json(conn, %{
          status: "ok",
          locale: locale,
          answer: render_one(entry, locale),
          related: render_many(related, locale)
        })

      {:unsure, candidates} ->
        json(conn, %{
          status: "unsure",
          locale: locale,
          candidates: render_many(candidates, locale)
        })

      {:restricted, entry} ->
        # Роль не позволяет выполнить действие. Отдаём сам вопрос (чтобы человек
        # видел, что его поняли) и список ролей — клиент скажет, к кому идти.
        json(conn, %{
          status: "restricted",
          locale: locale,
          question: Entry.text(entry.question, locale),
          allowed_roles: Enum.map(entry.roles, &to_string/1)
        })

      {:no_match, suggestions} ->
        json(conn, %{
          status: "no_match",
          locale: locale,
          suggestions: render_many(suggestions, locale)
        })
    end
  end

  @doc "Ответ по идентификатору — переход по «похожим вопросам»."
  def show(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user
    locale = locale_from(params)

    case Assistant.fetch(id, role: user.role) do
      {:ok, entry} ->
        json(conn, %{status: "ok", locale: locale, answer: render_one(entry, locale)})

      :error ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  ## Внутреннее

  defp render_one(%Entry{} = entry, locale) do
    %{
      id: to_string(entry.id),
      topic: to_string(entry.topic),
      question: Entry.text(entry.question, locale),
      answer: Entry.text(entry.answer, locale)
    }
  end

  defp render_many(entries, locale), do: Enum.map(entries, &render_one(&1, locale))

  # Явный параметр важнее сессии: у мобильного клиента своя настройка языка,
  # сессии в bearer-запросе нет.
  defp locale_from(params) do
    requested = params["locale"] || Gettext.get_locale(SvcWeb.Gettext)

    if requested in Locale.supported(), do: requested, else: Locale.default()
  end
end
