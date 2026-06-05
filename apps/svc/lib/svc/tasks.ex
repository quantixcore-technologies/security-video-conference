defmodule Svc.Tasks do
  @moduledoc """
  Контекст поручений/задач (E4, D-015). «CRM» для гос = поручения руководства +
  задачи сотрудникам (Kanban). Всё scoped по org_id (D-005).
  """
  import Ecto.Query
  alias Svc.Repo
  alias Svc.Tasks.Task
  alias Svc.Accounts.User

  @doc "Создаёт поручение/задачу от имени автора (creator)."
  def create_task(%User{} = creator, attrs) do
    attrs
    |> normalize()
    |> Map.merge(%{"org_id" => creator.org_id, "creator_id" => creator.id})
    |> then(&Task.changeset(%Task{}, &1))
    |> Repo.insert()
  end

  def get_task!(org_id, id) do
    Task
    |> Repo.get_by!(id: id, org_id: org_id)
    |> Repo.preload([:creator, :assignee, :meeting])
  end

  def update_task(%Task{} = task, attrs), do: task |> Task.changeset(normalize(attrs)) |> Repo.update()

  @doc "Смена статуса (Kanban drag/drop)."
  def set_status(%Task{} = task, status) when is_atom(status) or is_binary(status) do
    task |> Task.changeset(%{"status" => to_string(status)}) |> Repo.update()
  end

  def change_task(%Task{} = task, attrs \\ %{}), do: Task.changeset(task, normalize(attrs))

  @doc "Список задач org. opts: :assignee_id — только задачи исполнителя."
  def list_tasks(org_id, opts \\ []) do
    Task
    |> where([t], t.org_id == ^org_id)
    |> maybe_assignee(opts[:assignee_id])
    |> order_by([t], desc: t.inserted_at)
    |> preload([:creator, :assignee])
    |> Repo.all()
  end

  @doc "Задачи, сгруппированные по статусу (для Kanban-доски)."
  def board(org_id, opts \\ []) do
    org_id |> list_tasks(opts) |> Enum.group_by(& &1.status)
  end

  @doc "Незавершённые задачи исполнителя (для дашборда/уведомлений)."
  def open_count_for(user_id) do
    Repo.aggregate(
      from(t in Task, where: t.assignee_id == ^user_id and t.status not in [:done, :cancelled]),
      :count
    )
  end

  defp maybe_assignee(query, nil), do: query
  defp maybe_assignee(query, id), do: where(query, [t], t.assignee_id == ^id)

  # Принимаем и atom-, и string-ключи (форма LiveView vs прямой вызов).
  defp normalize(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  end
end
