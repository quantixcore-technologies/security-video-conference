defmodule Svc.Tasks do
  @moduledoc """
  Контекст поручений/задач (E4, D-015). «CRM» для гос = поручения руководства +
  задачи сотрудникам (Kanban). Всё scoped по org_id (D-005).
  """
  import Ecto.Query
  alias Svc.Repo
  alias Svc.Tasks.Task
  alias Svc.Accounts.User

  @doc "Кто вправе ставить поручения и двигать карточки (руководство). D-015."
  def can_manage?(%User{role: role}), do: role in [:super_admin, :admin_hr, :manager]

  @doc """
  Создаёт поручение/задачу от имени автора (creator). При назначении
  исполнителя (≠ автор) шлёт ему in-app уведомление (E4-C).
  """
  def create_task(%User{} = creator, attrs) do
    attrs
    |> normalize()
    |> Map.merge(%{"org_id" => creator.org_id, "creator_id" => creator.id})
    |> then(&Task.changeset(%Task{}, &1))
    |> Repo.insert()
    |> notify_assignee(creator)
  end

  # Уведомляем исполнителя о новом поручении (кроме случая «поставил сам себе»).
  defp notify_assignee({:ok, %Task{assignee_id: aid} = task}, %User{id: cid} = creator)
       when not is_nil(aid) and aid != cid do
    with %User{} = assignee <- Repo.get(User, aid) do
      Svc.Notifications.notify(
        assignee,
        :task,
        "Новое поручение: #{task.title}",
        body: "Поручил: #{creator.full_name}",
        meeting_id: task.meeting_id
      )
    end

    {:ok, task}
  end

  defp notify_assignee(result, _creator), do: result

  def get_task!(org_id, id) do
    Task
    |> Repo.get_by!(id: id, org_id: org_id)
    |> Repo.preload([:creator, :assignee, :meeting])
  end

  def update_task(%Task{} = task, attrs),
    do: task |> Task.changeset(normalize(attrs)) |> Repo.update()

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
    |> preload([:creator, :assignee, :meeting])
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

  @doc """
  Сводка по поручениям org (E4-D отчётность): счётчики по статусам,
  всего и просроченных. opts: :assignee_id — сузить до исполнителя.
  """
  def stats(org_id, opts \\ []) do
    by_status =
      from(t in Task, where: t.org_id == ^org_id)
      |> maybe_assignee(opts[:assignee_id])
      |> group_by([t], t.status)
      |> select([t], {t.status, count(t.id)})
      |> Repo.all()
      |> Map.new()

    %{
      total: by_status |> Map.values() |> Enum.sum(),
      todo: Map.get(by_status, :todo, 0),
      in_progress: Map.get(by_status, :in_progress, 0),
      review: Map.get(by_status, :review, 0),
      done: Map.get(by_status, :done, 0),
      cancelled: Map.get(by_status, :cancelled, 0),
      overdue: overdue_count(org_id, opts)
    }
  end

  @doc "Число просроченных (срок прошёл, не завершено и не отменено). opts: :assignee_id."
  def overdue_count(org_id, opts \\ []) do
    now = DateTime.utc_now()

    from(t in Task,
      where:
        t.org_id == ^org_id and not is_nil(t.due_at) and t.due_at < ^now and
          t.status not in [:done, :cancelled]
    )
    |> maybe_assignee(opts[:assignee_id])
    |> Repo.aggregate(:count)
  end

  @doc """
  Отчёт по исполнителям (E4-D): для каждого — открыто/выполнено/просрочено.
  Сортировка по числу открытых (desc). Только задачи с назначенным исполнителем.
  """
  def summary_by_assignee(org_id) do
    now = DateTime.utc_now()

    org_id
    |> list_tasks()
    |> Enum.filter(& &1.assignee)
    |> Enum.group_by(& &1.assignee)
    |> Enum.map(fn {assignee, ts} ->
      %{
        assignee: assignee,
        open: Enum.count(ts, &(&1.status not in [:done, :cancelled])),
        done: Enum.count(ts, &(&1.status == :done)),
        overdue: Enum.count(ts, &overdue?(&1, now))
      }
    end)
    |> Enum.sort_by(& &1.open, :desc)
  end

  defp overdue?(task, now) do
    task.due_at && task.status not in [:done, :cancelled] &&
      DateTime.compare(task.due_at, now) == :lt
  end

  defp maybe_assignee(query, nil), do: query
  defp maybe_assignee(query, id), do: where(query, [t], t.assignee_id == ^id)

  # Принимаем и atom-, и string-ключи (форма LiveView vs прямой вызов).
  defp normalize(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  end
end
