defmodule SvcWeb.API.NotificationController do
  @moduledoc "JSON API нативных клиентов: лента in-app уведомлений."
  use SvcWeb, :controller

  alias Svc.Notifications

  def index(conn, _params) do
    user = conn.assigns.current_user

    notifications =
      user.id
      |> Notifications.list_for_user(limit: 50)
      |> Enum.map(fn n ->
        %{
          id: n.id,
          kind: n.kind,
          title: n.title,
          body: n.body,
          meeting_id: n.meeting_id,
          read_at: n.read_at,
          inserted_at: n.inserted_at
        }
      end)

    json(conn, %{
      unread: Notifications.unread_count(user.id),
      notifications: notifications
    })
  end

  def mark_read(conn, %{"id" => id}) do
    count = Notifications.mark_read(conn.assigns.current_user.id, id)
    json(conn, %{ok: count})
  end

  def mark_all_read(conn, _params) do
    count = Notifications.mark_all_read(conn.assigns.current_user.id)
    json(conn, %{ok: count})
  end
end
