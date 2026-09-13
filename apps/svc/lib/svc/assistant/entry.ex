defmodule Svc.Assistant.Entry do
  @moduledoc """
  Одна запись базы знаний встроенного помощника (S37).

  Осознанно НЕ Ecto-схема: контент — часть кода, а не данные организации.
  Он одинаков для всех клиентов, версионируется вместе с функциями, которые
  описывает, и ревьюится в PR — иначе справка разъезжается с продуктом.
  """

  @enforce_keys [:id, :topic, :keywords, :question, :answer]
  defstruct [:id, :topic, :keywords, :question, :answer, roles: :all]

  @type lang_map :: %{required(String.t()) => String.t()}

  @type t :: %__MODULE__{
          id: atom(),
          topic: atom(),
          # Ключевые слова для поиска — плоский список по всем языкам сразу:
          # пользователь может писать вопрос вперемешку (uz + ru), и это норма.
          keywords: [String.t()],
          question: lang_map(),
          answer: lang_map(),
          # :all либо список ролей. Сотруднику не показываем инструкцию по
          # управлению пользователями — её всё равно нельзя выполнить (D-016),
          # а ложная подсказка выглядит как сломанный продукт.
          roles: :all | [atom()]
        }

  @doc "Видна ли запись пользователю с ролью `role` (nil — аноним/неизвестно)."
  def visible?(%__MODULE__{roles: :all}, _role), do: true
  def visible?(%__MODULE__{roles: roles}, role), do: role in roles

  @doc """
  Текст на нужном языке. Фолбэк — узбекский: он основной для заказчика,
  и лучше ответить на понятном языке, чем не ответить вовсе.
  """
  def text(map, locale) when is_map(map) do
    map[locale] || map["uz"] || map |> Map.values() |> List.first()
  end
end
