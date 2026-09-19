defmodule SvcWeb.DocumentLive.Index do
  @moduledoc """
  Обмен документами (S40): загрузка, список, отзыв, версии.

  Содержимое файла НЕ отдаётся через LiveView: скачивание идёт отдельным
  аутентифицированным контроллером (`SvcWeb.DocumentController`), как и `.ics`.
  """
  use SvcWeb, :live_view

  alias Svc.{Authz, Documents}

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, gettext("Документы"))
     |> assign(:can_send, Documents.can_send?(actor))
     |> assign(:colleagues, colleagues(actor))
     |> assign(:form_error, nil)
     |> assign(:uploading, false)
     |> allow_upload(:file,
       accept: :any,
       max_entries: 1,
       max_file_size: Documents.max_bytes()
     )
     |> load_documents()}
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, assign(socket, :form_error, nil)}

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :file, ref)}
  end

  def handle_event("send", %{"document" => params}, socket) do
    actor = socket.assigns.current_user

    case consume_file(socket) do
      {:ok, filename, content_type, content} ->
        attrs = %{
          "title" => params["title"],
          "filename" => filename,
          "content_type" => content_type,
          "action" => params["action"] || "information",
          "note" => params["note"],
          "due_at" => parse_expiry(params["due_at"]),
          "expires_at" => parse_expiry(params["expires_at"]),
          "recipient_ids" => params["recipient_ids"] || []
        }

        case Documents.upload(actor, attrs, content) do
          {:ok, _document} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Документ отправлен."))
             |> assign(:form_error, nil)
             |> load_documents()}

          {:error, reason} ->
            {:noreply, assign(socket, :form_error, error_message(reason))}
        end

      :error ->
        {:noreply, assign(socket, :form_error, gettext("Выберите файл."))}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    case Documents.revoke(socket.assigns.current_user, id) do
      {:ok, _document} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Доступ к документу отозван."))
         |> load_documents()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Не удалось отозвать документ."))}
    end
  end

  defp load_documents(socket) do
    assign(socket, :documents, Documents.list_visible(socket.assigns.current_user))
  end

  # Получатели — тот же список, что и исполнители поручений (D-016): равные и
  # нижестоящие по рангу, super_admin — вся организация. Отключённых не шлём.
  defp colleagues(actor) do
    actor
    |> Authz.assignable_users()
    |> Enum.reject(&(&1.id == actor.id or &1.status != :active))
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp consume_file(socket) do
    socket
    |> consume_uploaded_entries(:file, fn %{path: tmp}, entry ->
      {:ok, {Path.basename(entry.client_name), entry.client_type, File.read!(tmp)}}
    end)
    |> case do
      [{filename, content_type, content}] -> {:ok, filename, content_type, content}
      _ -> :error
    end
  end

  defp parse_expiry(nil), do: nil
  defp parse_expiry(""), do: nil

  defp parse_expiry(value) do
    case DateTime.from_iso8601(value <> ":00Z") do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end

  defp error_message(:unauthorized), do: gettext("Недостаточно прав для отправки документов.")
  defp error_message(:too_large), do: gettext("Файл слишком большой.")
  defp error_message(:empty_file), do: gettext("Файл пустой.")
  defp error_message(:not_found), do: gettext("Документ не найден.")

  defp error_message(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _} -> msg end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end

  defp error_message(_), do: gettext("Не удалось отправить документ.")

  defp status(document) do
    cond do
      document.revoked_at -> {:revoked, gettext("отозван")}
      expired?(document) -> {:expired, gettext("истёк")}
      true -> {:active, gettext("активен")}
    end
  end

  defp expired?(%{expires_at: nil}), do: false

  defp expired?(%{expires_at: expires}),
    do: DateTime.compare(expires, DateTime.utc_now()) != :gt

  defp human_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp human_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp human_size(bytes), do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"

  defp short_datetime(nil), do: "—"
  defp short_datetime(dt), do: Calendar.strftime(dt, "%d.%m.%Y %H:%M")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      active="documents"
      current_user={@current_user}
      unread_count={@unread_count}
    >
      <div class="space-y-6">
        <div>
          <h1 class="text-xl font-semibold tracking-tight">{gettext("Документы")}</h1>
          <p class="text-sm text-base-content/55 mt-1">
            {gettext("Файлы хранятся в зашифрованном виде. Доступ — только у получателей.")}
          </p>
        </div>

        <div :if={@can_send} class="rounded-xl border border-base-300 bg-base-100 p-5">
          <h2 class="text-sm font-medium mb-4">{gettext("Отправить документ")}</h2>

          <form phx-submit="send" phx-change="validate" class="space-y-4">
            <div class="grid gap-4 md:grid-cols-2">
              <label class="block">
                <span class="text-xs text-base-content/60">{gettext("Название")}</span>
                <input
                  type="text"
                  name="document[title]"
                  required
                  minlength="2"
                  class="input input-sm input-bordered w-full mt-1"
                  placeholder={gettext("Протокол совещания")}
                />
              </label>

              <label class="block">
                <span class="text-xs text-base-content/60">
                  {gettext("Доступ до (необязательно)")}
                </span>
                <input
                  type="datetime-local"
                  name="document[expires_at]"
                  class="input input-sm input-bordered w-full mt-1"
                />
              </label>

              <label class="block">
                <span class="text-xs text-base-content/60">{gettext("Резолюция")}</span>
                <select name="document[action]" class="select select-sm select-bordered w-full mt-1">
                  <option :for={action <- Svc.Documents.Document.actions()} value={action}>
                    {Svc.Documents.action_label(action)}
                  </option>
                </select>
              </label>

              <label class="block">
                <span class="text-xs text-base-content/60">{gettext("Срок исполнения")}</span>
                <input
                  type="datetime-local"
                  name="document[due_at]"
                  class="input input-sm input-bordered w-full mt-1"
                />
              </label>
            </div>

            <label class="block">
              <span class="text-xs text-base-content/60">
                {gettext("Что сделать (необязательно)")}
              </span>
              <textarea
                name="document[note]"
                rows="2"
                maxlength="2000"
                class="textarea textarea-sm textarea-bordered w-full mt-1"
                placeholder={gettext("Ознакомиться и подписать до пятницы")}
              ></textarea>
            </label>

            <div>
              <span class="text-xs text-base-content/60">{gettext("Получатели")}</span>
              <div class="mt-1 max-h-40 overflow-y-auto rounded-lg border border-base-300 p-2 grid gap-1 sm:grid-cols-2">
                <label :for={user <- @colleagues} class="flex items-center gap-2 text-sm px-1 py-0.5">
                  <input
                    type="checkbox"
                    name="document[recipient_ids][]"
                    value={user.id}
                    class="checkbox checkbox-xs"
                  />
                  <span>{user.full_name}</span>
                </label>
                <p :if={@colleagues == []} class="text-xs text-base-content/50 p-1">
                  {gettext("Нет доступных получателей.")}
                </p>
              </div>
            </div>

            <div>
              <span class="text-xs text-base-content/60">{gettext("Файл")}</span>
              <.live_file_input
                upload={@uploads.file}
                class="file-input file-input-sm file-input-bordered w-full mt-1"
              />
              <div :for={entry <- @uploads.file.entries} class="mt-2 flex items-center gap-3 text-xs">
                <span class="truncate">{entry.client_name}</span>
                <span class="text-base-content/50">{entry.progress}%</span>
                <button
                  type="button"
                  phx-click="cancel-upload"
                  phx-value-ref={entry.ref}
                  class="btn btn-ghost btn-xs"
                >
                  {gettext("Убрать")}
                </button>
              </div>
              <p
                :for={err <- upload_errors(@uploads.file)}
                class="text-xs text-error mt-1"
              >
                {upload_error_to_string(err)}
              </p>
            </div>

            <p :if={@form_error} class="text-sm text-error">{@form_error}</p>

            <button type="submit" class="btn btn-primary btn-sm">
              <.icon name="hero-paper-airplane" class="size-4" /> {gettext("Отправить")}
            </button>
          </form>
        </div>

        <div class="rounded-xl border border-base-300 bg-base-100 overflow-hidden">
          <table class="w-full text-sm">
            <thead class="bg-base-200/60 text-xs text-base-content/60">
              <tr>
                <th class="text-left font-medium px-4 py-2">{gettext("Название")}</th>
                <th class="text-left font-medium px-4 py-2">{gettext("Отправитель")}</th>
                <th class="text-left font-medium px-4 py-2">{gettext("Получатели")}</th>
                <th class="text-left font-medium px-4 py-2">{gettext("Размер")}</th>
                <th class="text-left font-medium px-4 py-2">{gettext("Статус")}</th>
                <th class="text-left font-medium px-4 py-2">{gettext("Дата")}</th>
                <th class="px-4 py-2"></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={document <- @documents} class="border-t border-base-300">
                <td class="px-4 py-2">
                  <div class="font-medium">{document.title}</div>
                  <div class="text-xs text-base-content/50">
                    {document.filename}
                    <span :if={document.version > 1}>· v{document.version}</span>
                  </div>
                  <div class="mt-1 flex flex-wrap items-center gap-1.5">
                    <span class="badge badge-xs badge-outline">
                      {Svc.Documents.action_label(document.action)}
                    </span>
                    <span :if={document.due_at} class="text-[11px] text-warning">
                      {gettext("до")} {short_datetime(document.due_at)}
                    </span>
                  </div>
                  <div :if={document.note} class="text-xs text-base-content/60 mt-1">
                    {document.note}
                  </div>
                </td>
                <td class="px-4 py-2">{document.owner.full_name}</td>
                <td class="px-4 py-2 text-xs text-base-content/70">
                  {Enum.map_join(document.recipients, ", ", & &1.user.full_name)}
                </td>
                <td class="px-4 py-2 whitespace-nowrap">{human_size(document.byte_size)}</td>
                <td class="px-4 py-2">
                  <% {kind, label} = status(document) %>
                  <span class={[
                    "badge badge-sm",
                    kind == :active && "badge-success",
                    kind == :revoked && "badge-error",
                    kind == :expired && "badge-ghost"
                  ]}>
                    {label}
                  </span>
                </td>
                <td class="px-4 py-2 whitespace-nowrap text-xs text-base-content/60">
                  {short_datetime(document.inserted_at)}
                </td>
                <td class="px-4 py-2 text-right whitespace-nowrap">
                  <.link
                    :if={elem(status(document), 0) == :active}
                    href={~p"/admin/documents/#{document.id}/download"}
                    class="btn btn-ghost btn-xs"
                  >
                    <.icon name="hero-arrow-down-tray" class="size-4" /> {gettext("Скачать")}
                  </.link>
                  <button
                    :if={document.owner_id == @current_user.id && is_nil(document.revoked_at)}
                    phx-click="revoke"
                    phx-value-id={document.id}
                    data-confirm={gettext("Отозвать доступ к документу?")}
                    class="btn btn-ghost btn-xs text-error"
                  >
                    {gettext("Отозвать")}
                  </button>
                </td>
              </tr>
              <tr :if={@documents == []}>
                <td colspan="7" class="px-4 py-10 text-center text-sm text-base-content/50">
                  {gettext("Документов пока нет.")}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp upload_error_to_string(:too_large), do: gettext("Файл слишком большой.")
  defp upload_error_to_string(:too_many_files), do: gettext("Можно загрузить только один файл.")
  defp upload_error_to_string(_), do: gettext("Ошибка загрузки файла.")
end
