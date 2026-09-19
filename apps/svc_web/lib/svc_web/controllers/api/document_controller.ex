defmodule SvcWeb.API.DocumentController do
  @moduledoc """
  API обмена документами для нативных клиентов (S41).

  Права полностью в контексте `Svc.Documents`: контроллер ничего не решает сам,
  иначе правило пришлось бы поддерживать в двух местах (веб и API) и они
  разъехались бы — ровно так появляются дыры.
  """
  use SvcWeb, :controller

  alias Svc.Documents

  @doc "Список видимых документов: свои + присланные (активные)."
  def index(conn, _params) do
    actor = conn.assigns.current_user
    documents = Documents.list_visible(actor)

    json(conn, %{documents: Enum.map(documents, &render_document(&1, actor))})
  end

  @doc "Один документ (метаданные, без содержимого)."
  def show(conn, %{"id" => id}) do
    actor = conn.assigns.current_user

    case Documents.fetch(actor, id) do
      {:ok, document} -> json(conn, %{document: render_document(document, actor)})
      {:error, _} -> conn |> put_status(:not_found) |> json(%{error: "document_not_found"})
    end
  end

  @doc "Содержимое файла. Всегда octet-stream: заявленный при загрузке MIME не отдаём (XSS)."
  def download(conn, %{"id" => id}) do
    case Documents.download(conn.assigns.current_user, id) do
      {:ok, document, content} ->
        conn
        |> put_resp_content_type("application/octet-stream")
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_resp_header("content-disposition", disposition(document.filename))
        |> put_resp_header("cache-control", "no-store, private")
        |> send_resp(200, content)

      {:error, :corrupted} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "file_corrupted"})

      {:error, _} ->
        conn |> put_status(:not_found) |> json(%{error: "document_not_found"})
    end
  end

  @doc "Отметка «ознакомился / исполнил»."
  def acknowledge(conn, %{"id" => id}) do
    case Documents.acknowledge(conn.assigns.current_user, id) do
      {:ok, changed} -> json(conn, %{ok: true, changed: changed})
      {:error, _} -> conn |> put_status(:not_found) |> json(%{error: "document_not_found"})
    end
  end

  # Клиенту важно: от кого, что делать, к какому сроку и что он уже сделал.
  defp render_document(document, actor) do
    mine = document.owner_id == actor.id
    me = Enum.find(document.recipients, &(&1.user_id == actor.id))

    %{
      id: document.id,
      title: document.title,
      filename: document.filename,
      byte_size: document.byte_size,
      version: document.version,
      action: document.action,
      action_label: Documents.action_label(document.action),
      note: document.note,
      due_at: document.due_at,
      expires_at: document.expires_at,
      revoked: not is_nil(document.revoked_at),
      inserted_at: document.inserted_at,
      from: %{id: document.owner_id, full_name: document.owner.full_name},
      mine: mine,
      opened_at: me && me.opened_at,
      acknowledged_at: me && me.acknowledged_at,
      recipients:
        Enum.map(document.recipients, fn recipient ->
          %{
            id: recipient.user_id,
            full_name: recipient.user.full_name,
            opened_at: recipient.opened_at,
            acknowledged_at: recipient.acknowledged_at
          }
        end)
    }
  end

  # Имя пришло от загрузившего: кавычки и переводы строк убираем, иначе можно
  # подделать заголовок ответа.
  defp disposition(filename) do
    safe = filename |> Path.basename() |> String.replace(~r/[^\w .\-()]/u, "_")
    ~s(attachment; filename="#{safe}")
  end
end
