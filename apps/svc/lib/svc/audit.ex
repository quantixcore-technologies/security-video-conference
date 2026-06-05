defmodule Svc.Audit do
  @moduledoc """
  Сквозной audit-log (D-014, foundation overkill).
  Append-only: записи не обновляются и не удаляются.

  Логируем чувствительные действия: входы, CRUD пользователей/отделов,
  смену ролей, просмотр журналов посещаемости (E2), доступ к записям (E2).
  """
  import Ecto.Query
  alias Svc.Repo
  alias Svc.Audit.Log
  alias Svc.Accounts.User

  @doc """
  Записывает audit-событие. `action` — атом/строка (напр. `:login_success`).
  opts: :org_id, :actor_id, :resource_type, :resource_id, :metadata, :ip, :user_agent.
  """
  def log(action, opts \\ []) do
    %Log{}
    |> Log.changeset(%{
      action: to_string(action),
      org_id: opts[:org_id],
      actor_user_id: opts[:actor_id],
      resource_type: opts[:resource_type] && to_string(opts[:resource_type]),
      resource_id: opts[:resource_id] && to_string(opts[:resource_id]),
      metadata: opts[:metadata] || %{},
      ip: opts[:ip],
      user_agent: opts[:user_agent]
    })
    |> Repo.insert()
  end

  @doc "Удобная форма от имени актора — подставляет org_id и actor_id."
  def log_action(%User{} = actor, action, opts \\ []) do
    log(action, Keyword.merge([org_id: actor.org_id, actor_id: actor.id], opts))
  end

  @doc "Лента аудита организации (свежие сверху)."
  def list_logs(org_id, opts \\ []) do
    limit = opts[:limit] || 100

    Repo.all(
      from l in Log,
        where: l.org_id == ^org_id,
        order_by: [desc: l.inserted_at, desc: l.id],
        limit: ^limit
    )
  end
end
