defmodule SvcWeb.DocumentController do
  @moduledoc """
  Скачивание документа (S40).

  Почему контроллер, а не LiveView: файл надо отдать телом HTTP-ответа —
  LiveView так не умеет. Тот же приём уже используется для `.ics` встречи.

  Права проверяет контекст: `Documents.download/2` вернёт `:not_found` и когда
  документа нет, и когда он есть, но не для этого пользователя.
  """
  use SvcWeb, :controller

  alias Svc.Documents

  def download(conn, %{"id" => id}) do
    case Documents.download(conn.assigns.current_user, id) do
      {:ok, document, content} ->
        conn
        # ВСЕГДА поток байт, а не заявленный при загрузке MIME. Тип приходил от
        # клиента, и вернуть его как есть означало бы хранимую XSS: `text/html`
        # или SVG со скриптом исполнились бы на нашем домене. Файл и так уходит
        # вложением, поэтому точный тип здесь ничего не даёт.
        |> put_resp_content_type("application/octet-stream")
        # Запрещаем браузеру угадывать тип по содержимому.
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_resp_header("content-disposition", disposition(document.filename))
        # Файл конфиденциальный: ни браузер, ни прокси не должны его кэшировать.
        |> put_resp_header("cache-control", "no-store, private")
        |> send_resp(200, content)

      {:error, :corrupted} ->
        conn
        |> put_flash(:error, gettext("Файл повреждён — обратитесь к отправителю."))
        |> redirect(to: ~p"/admin/documents")

      {:error, _reason} ->
        conn
        |> put_flash(:error, gettext("Документ не найден."))
        |> redirect(to: ~p"/admin/documents")
    end
  end

  # Имя файла приходит от загрузившего, поэтому кавычки и переводы строк из него
  # убираем — иначе можно подделать заголовок ответа (header injection).
  defp disposition(filename) do
    safe = filename |> Path.basename() |> String.replace(~r/[^\w .\-()]/u, "_")
    ~s(attachment; filename="#{safe}")
  end
end
