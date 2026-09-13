defmodule Svc.Assistant do
  @moduledoc """
  Встроенный помощник «как пользоваться системой» (S37, D-019).

  Работает БЕЗ LLM: вопрос сопоставляется с базой знаний по ключевым словам.
  Решение принято осознанно — продукт продаётся как полностью self-hosted,
  без зависимости от зарубежного облака, и отправлять вопросы госслужащих
  во внешний API означало бы противоречить собственному обещанию (см. D-019).

  Плата за это — помощник отвечает только на то, что есть в базе. Поэтому
  при неуверенном совпадении он честно говорит «не понял» и предлагает темы,
  а не выдумывает ответ.
  """

  alias Svc.Assistant.{Entry, KnowledgeBase}

  # Слова, которые есть почти в любом вопросе. Без их отсева «как мне сделать»
  # матчится со всем подряд и первый же ответ оказывается случайным.
  @stopwords ~w(
    qanday qilaman qilish nima uchun kerak menga meni mumkin bo'ladi bu shu
    qayerda qayerdan qachon kim nimaga iltimos ayting yordam
    как мне что где когда кто зачем почему нужно надо можно ли это
    сделать делать пожалуйста скажи помоги хочу
    how do i what where when who why can could should the a an to my me
    is are please help want need
  )

  # Минимальная длина общего префикса, при которой считаем слова однокоренными.
  # Узбекский и русский агглютинативны/флективны: «majlis» / «majlisni» /
  # «majlisga», «совещание» / «совещания» — точное равенство ловило бы единицы.
  @stem_len 4

  # Насколько длиннее может быть слово после общего корня. Ограничение
  # обязательно: без него «yangi» (новый) склеивается с «yangilanish»
  # (обновление) — общий префикс есть, а смысл разный.
  @max_tail 5

  @typedoc "Результат запроса к помощнику."
  @type result ::
          {:ok, Entry.t(), [Entry.t()]}
          | {:unsure, [Entry.t()]}
          | {:restricted, Entry.t()}
          | {:no_match, [Entry.t()]}

  @doc """
  Отвечает на вопрос.

  Опции: `:role` — роль пользователя (фильтрует недоступные инструкции),
  `:locale` — не влияет на поиск (ключевые слова общие), нужен вызывающему
  для выбора языка текста.

  Возвращает `{:ok, entry, related}` при уверенном совпадении,
  `{:unsure, candidates}` когда кандидаты равнозначны,
  `{:restricted, entry}` когда ответ найден, но роли он недоступен,
  `{:no_match, suggestions}` когда ничего не найдено.

  Поиск идёт по ВСЕЙ базе, а фильтр роли применяется к результату. Если просто
  прятать недоступные записи, сотрудник, спросивший «как добавить работника»,
  получил бы случайный соседний ответ вместо внятного «это может только
  администратор» — то есть продукт выглядел бы сломанным.
  """
  @spec ask(String.t(), keyword()) :: result()
  def ask(query, opts \\ []) do
    role = Keyword.get(opts, :role)
    tokens = tokenize(query)

    if tokens == [] do
      {:no_match, suggestions(opts)}
    else
      KnowledgeBase.entries()
      |> Enum.map(&{score(tokens, &1), &1})
      |> Enum.reject(fn {score, _} -> score == 0 end)
      |> Enum.sort_by(fn {score, _} -> -score end)
      |> decide(role, opts)
    end
  end

  @doc "Стартовые вопросы для подсказок в интерфейсе."
  @spec suggestions(keyword()) :: [Entry.t()]
  def suggestions(opts \\ []) do
    opts |> Keyword.get(:role) |> KnowledgeBase.entries_for() |> starters()
  end

  @doc "Запись по идентификатору — для перехода по «похожим вопросам»."
  @spec fetch(atom() | String.t(), keyword()) :: {:ok, Entry.t()} | :error
  def fetch(id, opts \\ []) do
    wanted = to_string(id)

    opts
    |> Keyword.get(:role)
    |> KnowledgeBase.entries_for()
    |> Enum.find(&(to_string(&1.id) == wanted))
    |> case do
      nil -> :error
      entry -> {:ok, entry}
    end
  end

  ## Внутреннее

  defp decide([], _role, opts), do: {:no_match, suggestions(opts)}

  defp decide([{top_score, best} | rest], role, _opts) do
    ties = Enum.filter(rest, fn {score, _} -> score == top_score end)

    cond do
      # Ответ есть, но роль его выполнить не может — говорим об этом прямо.
      not Entry.visible?(best, role) ->
        {:restricted, best}

      # Несколько записей набрали одинаковый балл — уверенности нет, пусть
      # человек выберет сам, это честнее случайного попадания.
      ties != [] ->
        candidates =
          [best | Enum.map(ties, &elem(&1, 1))]
          |> Enum.filter(&Entry.visible?(&1, role))
          |> Enum.take(4)

        {:unsure, candidates}

      true ->
        related =
          rest
          |> Enum.map(&elem(&1, 1))
          |> Enum.filter(&Entry.visible?(&1, role))
          |> Enum.take(3)

        {:ok, best, related}
    end
  end

  defp score(tokens, %Entry{keywords: keywords}) do
    Enum.count(tokens, fn token -> Enum.any?(keywords, &same_stem?(token, &1)) end)
  end

  # Однокоренные, если совпал достаточный префикс И «хвост» длинного слова
  # похож на окончание, а не на другое слово. Две проверки нужны обе:
  # «совещания»/«совещание» — общий префикс 8, хвост 1 → одно слово;
  # «yangi»/«yangilanish»  — общий префикс 5, хвост 6 → разные слова.
  defp same_stem?(token, keyword) do
    shared = common_prefix_length(token, keyword)
    longest = max(String.length(token), String.length(keyword))

    shared >= @stem_len and longest - shared <= @max_tail
  end

  defp common_prefix_length(a, b) do
    a
    |> String.graphemes()
    |> Enum.zip(String.graphemes(b))
    |> Enum.take_while(fn {x, y} -> x == y end)
    |> length()
  end

  defp tokenize(query) when is_binary(query) do
    query
    |> String.downcase()
    # Апостроф — часть узбекских букв (o', g'), его убирать нельзя.
    |> String.replace(~r/[^\p{L}\p{N}'’]+/u, " ")
    |> String.replace("’", "'")
    |> String.split(" ", trim: true)
    |> Enum.reject(&(&1 in @stopwords or String.length(&1) < 2))
    |> Enum.uniq()
  end

  defp tokenize(_), do: []

  # Первые записи базы — она упорядочена от самых частых вопросов к редким.
  defp starters(entries), do: Enum.take(entries, 4)
end
