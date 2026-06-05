defmodule Svc.Notifications do
  @moduledoc """
  In-app уведомления (E3). Внутренний канал — без внешних сервисов
  (email/SMS/Telegram отложены до решения заказчика по гос-каналам).
  Всё scoped по org_id + user_id (D-005).
  """
  import Ecto.Query
  alias Svc.Repo
  alias Svc.Notifications.Notification
  alias Svc.Accounts.User

  @doc """
  Создаёт уведомление пользователю.
  `kind` ∈ invite|reminder|update|cancel|task. opts: :body, :meeting_id.
  """
  def notify(%User{} = user, kind, title, opts \\ []) do
    %Notification{}
    |> Notification.changeset(%{
      org_id: user.org_id,
      user_id: user.id,
      kind: kind,
      title: title,
      body: opts[:body],
      meeting_id: opts[:meeting_id]
    })
    |> Repo.insert()
  end

  @doc "Массовая рассылка одного уведомления списку пользователей."
  def notify_many(users, kind, title, opts \\ []) do
    Enum.each(users, &notify(&1, kind, title, opts))
  end

  @doc "Лента уведомлений пользователя (свежие сверху)."
  def list_for_user(user_id, opts \\ []) do
    limit = opts[:limit] || 20

    Repo.all(
      from n in Notification,
        where: n.user_id == ^user_id,
        order_by: [desc: n.inserted_at, desc: n.id],
        limit: ^limit
    )
  end

  @doc "Число непрочитанных уведомлений."
  def unread_count(user_id) do
    Repo.aggregate(
      from(n in Notification, where: n.user_id == ^user_id and is_nil(n.read_at)),
      :count
    )
  end

  @doc "Отметить одно уведомление прочитанным (scoped по user_id)."
  def mark_read(user_id, id) do
    {count, _} =
      from(n in Notification, where: n.id == ^id and n.user_id == ^user_id and is_nil(n.read_at))
      |> Repo.update_all(set: [read_at: DateTime.utc_now()])

    count
  end

  @doc "Отметить все уведомления пользователя прочитанными."
  def mark_all_read(user_id) do
    {count, _} =
      from(n in Notification, where: n.user_id == ^user_id and is_nil(n.read_at))
      |> Repo.update_all(set: [read_at: DateTime.utc_now()])

    count
  end
end
