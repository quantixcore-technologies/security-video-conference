defmodule Svc.Documents do
  @moduledoc """
  Контекст обмена документами (S40).

  Модель доступа повторяет встречи (D-016/D-021), потому что задача та же —
  конфиденциальный объект внутри организации:

    * всё scoped по `org_id` (D-005);
    * видят только автор и ЯВНО указанные получатели — даже super_admin не
      получает чужой документ «по должности»;
    * невидимый документ отдаётся как `{:error, :not_found}`, а не `:unauthorized`:
      иначе по коду ответа можно перебором узнать, какие документы существуют;
    * отзыв и срок действия закрывают доступ получателям, но автор и журнал
      сохраняют полную историю (D-014).

  Файл на диске зашифрован (`Svc.Documents.Storage`); в БД только метаданные.
  """
  import Ecto.Query

  alias Svc.Accounts.User
  alias Svc.Documents.{Document, Recipient, Storage}
  alias Svc.Repo

  @max_bytes 25 * 1024 * 1024

  @doc "Предельный размер файла (байт). Совпадает с лимитом формы LiveView."
  def max_bytes, do: @max_bytes

  @doc "Кто вправе отправлять документы. Рядовой сотрудник — только получатель."
  def can_send?(%User{role: role}), do: role in [:super_admin, :admin_hr, :manager]

  @doc """
  Загружает документ и рассылает получателям.

  `attrs`: `title`, `filename`, `content_type`, `expires_at` (опционально),
  `recipient_ids` — список id пользователей своей организации.
  `content` — бинарь файла (LiveView уже сложил его во временный файл).

  Всё в одной транзакции: если получатели не записались, документ не остаётся
  «висящим» без адресатов, а блоб удаляется.
  """
  def upload(%User{} = actor, attrs, content) when is_binary(content) do
    cond do
      not can_send?(actor) ->
        {:error, :unauthorized}

      byte_size(content) == 0 ->
        {:error, :empty_file}

      byte_size(content) > @max_bytes ->
        {:error, :too_large}

      true ->
        do_upload(actor, attrs, content)
    end
  end

  defp do_upload(actor, attrs, content) do
    attrs = normalize(attrs)
    recipient_ids = actor |> allowed_recipient_ids(attrs["recipient_ids"] || [])

    with {:ok, storage_key} <- Storage.put(content) do
      document_attrs =
        Map.merge(attrs, %{
          "org_id" => actor.org_id,
          "owner_id" => actor.id,
          "content_type" => safe_content_type(attrs["content_type"]),
          "byte_size" => byte_size(content),
          "sha256" => sha256(content),
          "storage_key" => storage_key
        })

      result =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:document, Document.create_changeset(%Document{}, document_attrs))
        |> Ecto.Multi.run(:recipients, fn _repo, %{document: document} ->
          insert_recipients(document, recipient_ids)
        end)
        |> Repo.transaction()

      case result do
        {:ok, %{document: document}} ->
          Svc.Audit.log_action(actor, :document_upload,
            resource_type: :document,
            resource_id: document.id,
            metadata: %{"recipients" => length(recipient_ids), "bytes" => document.byte_size}
          )

          notify_recipients(document, actor, recipient_ids)
          {:ok, Repo.preload(document, [:recipients, :owner])}

        {:error, _step, reason, _changes} ->
          # Блоб без записи в БД никому не нужен и не должен занимать диск.
          Storage.delete(storage_key)
          {:error, reason}
      end
    end
  end

  defp insert_recipients(%Document{} = document, user_ids) do
    Enum.reduce_while(user_ids, {:ok, []}, fn user_id, {:ok, acc} ->
      attrs = %{org_id: document.org_id, document_id: document.id, user_id: user_id}

      case Repo.insert(Recipient.changeset(%Recipient{}, attrs)) do
        {:ok, recipient} -> {:cont, {:ok, [recipient | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  # Получатель должен узнать о документе, не открывая веб-панель: мобильный
  # клиент забирает уведомления фоном (NotifyWorker), поэтому «от кого» и
  # «что делать» кладём прямо в текст.
  defp notify_recipients(%Document{} = document, %User{} = actor, recipient_ids) do
    users = Repo.all(from u in User, where: u.id in ^recipient_ids)

    Svc.Notifications.notify_many(
      users,
      :document,
      "#{action_label(document.action)}: #{document.title}",
      body: notification_body(document, actor)
    )
  end

  defp notification_body(%Document{} = document, %User{} = actor) do
    [
      "От: #{actor.full_name}",
      document.due_at && "срок: #{Calendar.strftime(document.due_at, "%d.%m.%Y")}",
      document.note && String.slice(document.note, 0, 200)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  @doc "Подпись резолюции для уведомлений и клиентов."
  def action_label(:information), do: "К сведению"
  def action_label(:review), do: "На рассмотрение"
  def action_label(:signature), do: "На подпись"
  def action_label(:execution), do: "На исполнение"
  def action_label(_), do: "Документ"

  @doc """
  Отметка получателя «ознакомился / исполнил».

  Отличается от `opened_at` (скачал): отправителю важно видеть не факт загрузки
  файла, а подтверждение, что резолюция принята к работе.
  """
  def acknowledge(%User{} = actor, id) do
    with {:ok, document} <- fetch(actor, id) do
      {count, _} =
        from(r in Recipient,
          where:
            r.document_id == ^document.id and r.user_id == ^actor.id and
              is_nil(r.acknowledged_at)
        )
        |> Repo.update_all(set: [acknowledged_at: DateTime.utc_now()])

      if count > 0 do
        Svc.Audit.log_action(actor, :document_acknowledge,
          resource_type: :document,
          resource_id: document.id
        )
      end

      {:ok, count > 0}
    end
  end

  @doc """
  Документы, видимые пользователю: свои (любые) + присланные ему (только активные).

  Отозванные и просроченные чужие документы не показываем — иначе отзыв не
  закрывал бы доступ, а лишь «прятал кнопку».
  """
  def list_visible(%User{} = actor) do
    visible_query(actor)
    |> order_by([d], desc: d.inserted_at)
    |> preload([:owner, recipients: :user])
    |> Repo.all()
  end

  @doc "Тот же фильтр как выражение — для будущей пагинации/поиска."
  def visible_query(%User{id: user_id, org_id: org_id}) do
    now = DateTime.utc_now()

    received =
      from r in Recipient,
        where: r.user_id == ^user_id,
        select: r.document_id

    from d in Document,
      where:
        d.org_id == ^org_id and
          (d.owner_id == ^user_id or
             (d.id in subquery(received) and is_nil(d.revoked_at) and
                (is_nil(d.expires_at) or d.expires_at > ^now)))
  end

  @doc """
  Документ по id с проверкой доступа. `{:error, :not_found}` — и когда его нет,
  и когда он есть, но не для этого пользователя (не раскрываем существование).
  """
  def fetch(%User{} = actor, id) do
    case actor |> visible_query() |> where([d], d.id == ^id) |> Repo.one() do
      nil -> {:error, :not_found}
      document -> {:ok, Repo.preload(document, [:owner, recipients: :user])}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  @doc """
  Отдаёт содержимое файла и фиксирует факт скачивания.

  Для получателя проставляется `opened_at` (первое открытие) — это и есть
  «кто прочитал» в отчётах.
  """
  def download(%User{} = actor, id) do
    with {:ok, document} <- fetch(actor, id),
         {:ok, content} <- Storage.get(document.storage_key),
         :ok <- verify_integrity(document, content) do
      mark_opened(document, actor)

      Svc.Audit.log_action(actor, :document_download,
        resource_type: :document,
        resource_id: document.id
      )

      {:ok, document, content}
    end
  end

  # Блоб мог испортиться на диске или быть подменён — отдавать такой файл
  # под видом исходного нельзя.
  defp verify_integrity(%Document{sha256: expected}, content) do
    if sha256(content) == expected, do: :ok, else: {:error, :corrupted}
  end

  defp mark_opened(%Document{} = document, %User{} = actor) do
    from(r in Recipient,
      where: r.document_id == ^document.id and r.user_id == ^actor.id and is_nil(r.opened_at)
    )
    |> Repo.update_all(set: [opened_at: DateTime.utc_now()])
  end

  @doc """
  Отзывает документ. Может только автор (или super_admin своей организации —
  ему нужна возможность закрыть утечку, когда автор недоступен).
  """
  def revoke(%User{} = actor, id) do
    with {:ok, document} <- fetch_for_revoke(actor, id) do
      if can_revoke?(actor, document) do
        document
        |> Document.revoke_changeset(%{revoked_by_id: actor.id})
        |> Repo.update()
        |> tap(fn
          {:ok, revoked} ->
            Svc.Audit.log_action(actor, :document_revoke,
              resource_type: :document,
              resource_id: revoked.id
            )

          _ ->
            :noop
        end)
      else
        {:error, :unauthorized}
      end
    end
  end

  # Отзыв — единственная операция, доступная super_admin по должности (D-022):
  # когда автор уволился или утечка уже случилась, кто-то обязан уметь закрыть
  # доступ. Поэтому здесь поиск идёт по org, а не по видимости. Содержимое при
  # этом остаётся закрытым: `download/2` по-прежнему ходит через `fetch/2`.
  defp fetch_for_revoke(%User{role: :super_admin, org_id: org_id} = actor, id) do
    case Repo.get_by(Document, id: id, org_id: org_id) do
      nil -> {:error, :not_found}
      document -> {:ok, Repo.preload(document, [:owner, recipients: :user])}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
    ArgumentError -> fetch(actor, id)
  end

  defp fetch_for_revoke(%User{} = actor, id), do: fetch(actor, id)

  @doc "Автор документа или super_admin той же организации."
  def can_revoke?(%User{id: id}, %Document{owner_id: id}), do: true

  def can_revoke?(%User{role: :super_admin, org_id: org_id}, %Document{org_id: org_id}), do: true

  def can_revoke?(%User{}, %Document{}), do: false

  @doc """
  Новая версия существующего документа: старая остаётся в истории.

  Список получателей наследуется — иначе при обновлении файла адресаты молча
  теряли бы доступ.
  """
  def new_version(%User{} = actor, id, attrs, content) do
    with {:ok, parent} <- fetch(actor, id) do
      if parent.owner_id == actor.id do
        root = parent.parent_id || parent.id
        inherited = Enum.map(parent.recipients, & &1.user_id)

        attrs =
          attrs
          |> normalize()
          |> Map.merge(%{
            "title" => attrs["title"] || attrs[:title] || parent.title,
            "parent_id" => root,
            "version" => next_version(actor, root),
            "recipient_ids" => attrs["recipient_ids"] || attrs[:recipient_ids] || inherited
          })

        upload(actor, attrs, content)
      else
        {:error, :unauthorized}
      end
    end
  end

  @doc "Все версии документа (корень + потомки), сверху свежая."
  def versions(%User{} = actor, id) do
    with {:ok, document} <- fetch(actor, id) do
      root = document.parent_id || document.id

      list =
        actor
        |> visible_query()
        |> where([d], d.id == ^root or d.parent_id == ^root)
        |> order_by([d], desc: d.version)
        |> Repo.all()

      {:ok, list}
    end
  end

  defp next_version(%User{org_id: org_id}, root_id) do
    max =
      from(d in Document,
        where: d.org_id == ^org_id and (d.id == ^root_id or d.parent_id == ^root_id),
        select: max(d.version)
      )
      |> Repo.one()

    (max || 1) + 1
  end

  # Получателем может быть только активный пользователь СВОЕЙ организации:
  # id из формы приходит от клиента и доверять ему нельзя.
  defp allowed_recipient_ids(%User{org_id: org_id, id: actor_id}, ids) do
    ids =
      ids
      |> List.wrap()
      |> Enum.map(&to_int/1)
      |> Enum.reject(&(&1 in [nil, actor_id]))
      |> Enum.uniq()

    if ids == [] do
      []
    else
      from(u in User, where: u.org_id == ^org_id and u.id in ^ids and u.status == :active)
      |> select([u], u.id)
      |> Repo.all()
    end
  end

  defp to_int(value) when is_integer(value), do: value

  defp to_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp to_int(_), do: nil

  # Белый список MIME-типов. Тип приходит от клиента, и если отдать его обратно
  # как есть, загрузка `text/html` (или SVG со скриптом) превратится в хранимую
  # XSS на нашем домене. Всё неизвестное отдаётся как поток байт — браузер такое
  # не исполняет, а сохраняет.
  @safe_content_types ~w(
    application/pdf
    application/msword
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/vnd.ms-excel
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    application/vnd.ms-powerpoint
    application/vnd.openxmlformats-officedocument.presentationml.presentation
    application/zip
    text/plain
    image/png
    image/jpeg
    image/gif
    image/webp
  )

  @doc "Безопасный MIME для отдачи файла. Неизвестное → поток байт (не исполняется)."
  def safe_content_type(type) when is_binary(type) do
    normalized = type |> String.split(";") |> hd() |> String.trim() |> String.downcase()
    if normalized in @safe_content_types, do: normalized, else: "application/octet-stream"
  end

  def safe_content_type(_), do: "application/octet-stream"

  defp sha256(content), do: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

  # Принимаем и atom-, и string-ключи (форма LiveView vs прямой вызов).
  defp normalize(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end
end
