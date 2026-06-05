defmodule SvcWeb.TaskLive.Index do
  @moduledoc """
  Kanban-доска поручений/задач (E4-B, D-015). Руководство ставит поручения и
  двигает карточки между статусами (drag-drop). Сотрудник видит свои задачи
  read-only. Всё scoped по org_id (D-005).
  """
  use SvcWeb, :live_view

  alias Svc.{Tasks, Accounts}

  # Видимые колонки доски (cancelled не показываем в основном потоке).
  @columns [
    {:todo, "Новые"},
    {:in_progress, "В работе"},
    {:review, "Проверка"},
    {:done, "Выполнено"}
  ]
  @column_statuses Enum.map(@columns, fn {s, _} -> to_string(s) end)

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action)}
  end

  defp apply_action(socket, :index) do
    socket
    |> assign(:page_title, "Поручения")
    |> assign(:form, nil)
    |> load_board()
  end

  defp apply_action(socket, :new) do
    actor = socket.assigns.current_user

    if Tasks.can_manage?(actor) do
      socket
      |> assign(:page_title, "Новое поручение")
      |> assign(:assignees, Accounts.list_users(actor.org_id))
      |> assign(:form, to_form(%{"title" => "", "priority" => "normal", "assignee_id" => ""}, as: :task))
      |> load_board()
    else
      socket
      |> put_flash(:error, "Недостаточно прав для создания поручений.")
      |> push_navigate(to: ~p"/admin/tasks")
    end
  end

  @impl true
  def handle_event("save", %{"task" => params}, socket) do
    actor = socket.assigns.current_user

    if Tasks.can_manage?(actor) do
      case Tasks.create_task(actor, drop_blank_assignee(params)) do
        {:ok, task} ->
          {:noreply,
           socket
           |> put_flash(:info, "Поручение «#{task.title}» создано.")
           |> push_navigate(to: ~p"/admin/tasks")}

        {:error, %Ecto.Changeset{} = cs} ->
          {:noreply, assign(socket, :form, to_form(Map.put(cs, :action, :insert), as: :task))}
      end
    else
      {:noreply, put_flash(socket, :error, "Недостаточно прав.")}
    end
  end

  # Перемещение карточки drag-drop'ом. Двигать вправе только руководство.
  def handle_event("move_task", %{"id" => id, "status" => status}, socket) do
    actor = socket.assigns.current_user

    if Tasks.can_manage?(actor) and status in @column_statuses do
      actor.org_id
      |> Tasks.get_task!(id)
      |> Tasks.set_status(status)

      {:noreply, load_board(socket)}
    else
      {:noreply, socket}
    end
  end

  defp drop_blank_assignee(%{"assignee_id" => ""} = params), do: Map.delete(params, "assignee_id")
  defp drop_blank_assignee(params), do: params

  defp load_board(socket) do
    actor = socket.assigns.current_user
    manage? = Tasks.can_manage?(actor)
    # Руководитель видит всю доску org, сотрудник — только свои задачи.
    opts = if manage?, do: [], else: [assignee_id: actor.id]

    socket
    |> assign(:board, Tasks.board(actor.org_id, opts))
    |> assign(:can_manage, manage?)
    |> assign(:columns, @columns)
    |> assign_report(manage?, actor.org_id)
  end

  # Сводка и отчёт по исполнителям — только для руководства (E4-D).
  defp assign_report(socket, true, org_id) do
    socket
    |> assign(:stats, Tasks.stats(org_id))
    |> assign(:assignee_summary, Tasks.summary_by_assignee(org_id))
  end

  defp assign_report(socket, false, _org_id) do
    assign(socket, stats: nil, assignee_summary: [])
  end

  defp tasks_for(board, status), do: Map.get(board, status, [])

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="tasks" current_user={@current_user} unread_count={@unread_count}>
      <div class="flex items-start justify-between gap-4 mb-6">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight">Поручения</h1>
          <p class="text-sm text-base-content/55 mt-1">
            {if @can_manage, do: "Доска задач отдела — перетаскивайте карточки между колонками", else: "Мои задачи"}
          </p>
        </div>
        <.link
          :if={@can_manage and @live_action == :index}
          navigate={~p"/admin/tasks/new"}
          class="btn btn-primary gap-2"
        >
          <.icon name="hero-plus" class="size-4" /> Поручение
        </.link>
      </div>

      <div :if={@live_action == :new} class="rounded-xl border border-base-300 bg-base-100/50 p-5 mb-5">
        <h3 class="font-medium mb-4 flex items-center gap-2">
          <.icon name="hero-clipboard-document-list" class="size-4 text-primary" /> Новое поручение
        </h3>
        <.form for={@form} phx-submit="save" class="space-y-3">
          <.input field={@form[:title]} type="text" label="Что нужно сделать" required />
          <.input field={@form[:description]} type="textarea" label="Описание (необязательно)" rows="2" />
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <.input
              field={@form[:assignee_id]}
              type="select"
              label="Исполнитель"
              prompt="Не назначено"
              options={Enum.map(@assignees, &{&1.full_name, &1.id})}
            />
            <.input
              field={@form[:priority]}
              type="select"
              label="Приоритет"
              options={priority_options()}
            />
            <.input field={@form[:due_at]} type="datetime-local" label="Срок" />
          </div>
          <div class="flex gap-2 pt-2">
            <.button type="submit" phx-disable-with="Создаём...">Создать поручение</.button>
            <.link navigate={~p"/admin/tasks"} class="btn btn-ghost">Отмена</.link>
          </div>
        </.form>
      </div>

      <div :if={@can_manage and @stats} class="flex flex-wrap items-center gap-2 mb-5 text-sm">
        <span class="inline-flex items-center gap-1.5 rounded-lg border border-base-300 px-3 py-1.5">
          <span class="text-base-content/55">Всего</span>
          <span class="tabular font-semibold">{@stats.total}</span>
        </span>
        <span class="inline-flex items-center gap-1.5 rounded-lg border border-info/25 px-3 py-1.5">
          <span class="text-base-content/55">В работе</span>
          <span class="tabular font-semibold text-info">{@stats.in_progress}</span>
        </span>
        <span class="inline-flex items-center gap-1.5 rounded-lg border border-success/25 px-3 py-1.5">
          <span class="text-base-content/55">Выполнено</span>
          <span class="tabular font-semibold text-success">{@stats.done}</span>
        </span>
        <span
          :if={@stats.overdue > 0}
          class="inline-flex items-center gap-1.5 rounded-lg border border-error/25 bg-error/5 px-3 py-1.5"
        >
          <.icon name="hero-exclamation-triangle" class="size-3.5 text-error" />
          <span class="text-base-content/55">Просрочено</span>
          <span class="tabular font-semibold text-error">{@stats.overdue}</span>
        </span>
      </div>

      <div
        id="kanban-board"
        phx-hook="Kanban"
        class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-4 items-start"
      >
        <div
          :for={{status, title} <- @columns}
          data-status={status}
          class="rounded-xl border border-base-300 bg-base-200/30 flex flex-col min-h-40 transition"
        >
          <div class="flex items-center justify-between px-4 py-3 border-b border-base-300">
            <span class="flex items-center gap-2 text-sm font-medium">
              <span class={"size-2 rounded-full #{column_dot(status)}"}></span>
              {title}
            </span>
            <span class="text-xs text-base-content/40 tabular">{length(tasks_for(@board, status))}</span>
          </div>

          <div class="flex-1 p-2.5 space-y-2.5">
            <article
              :for={t <- tasks_for(@board, status)}
              data-task-id={t.id}
              draggable={to_string(@can_manage)}
              class={[
                "group rounded-lg border border-base-300 bg-base-100 p-3 shadow-sm transition",
                @can_manage && "cursor-grab hover:border-primary/40 hover:shadow-md active:cursor-grabbing"
              ]}
            >
              <div class="flex items-start justify-between gap-2">
                <p class="text-sm font-medium leading-snug">{t.title}</p>
                <span class={"shrink-0 inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-semibold #{priority_class(t.priority)}"}>
                  {priority_label(t.priority)}
                </span>
              </div>

              <p :if={t.description not in [nil, ""]} class="mt-1 text-xs text-base-content/50 line-clamp-2">
                {t.description}
              </p>

              <.link
                :if={t.meeting}
                navigate={~p"/admin/meetings/#{t.meeting_id}"}
                class="mt-2 inline-flex items-center gap-1 text-[11px] text-base-content/45 hover:text-primary transition"
                title="Поручение по итогам встречи"
              >
                <.icon name="hero-video-camera" class="size-3" /> {t.meeting.title}
              </.link>

              <div class="mt-2.5 flex items-center justify-between gap-2">
                <span :if={t.assignee} class="flex items-center gap-1.5 text-xs text-base-content/60">
                  <span class="grid place-items-center size-5 rounded-full bg-primary/15 text-primary text-[9px] font-semibold ring-1 ring-primary/15">
                    {initials(t.assignee.full_name)}
                  </span>
                  <span class="truncate max-w-24">{t.assignee.full_name}</span>
                </span>
                <span :if={is_nil(t.assignee)} class="text-xs text-base-content/30">Не назначено</span>

                <span
                  :if={t.due_at}
                  class={["inline-flex items-center gap-1 text-[11px] tabular", due_class(t)]}
                >
                  <.icon name="hero-clock" class="size-3" />
                  {format_due(t.due_at)}
                </span>
              </div>
            </article>

            <div
              :if={tasks_for(@board, status) == []}
              class="grid place-items-center py-6 text-xs text-base-content/25"
            >
              Пусто
            </div>
          </div>
        </div>
      </div>

      <div
        :if={@can_manage and @assignee_summary != []}
        class="mt-8 rounded-xl border border-base-300 bg-base-100/50 overflow-hidden"
      >
        <div class="px-5 py-3 border-b border-base-300 flex items-center gap-2">
          <.icon name="hero-chart-bar" class="size-4 text-base-content/45" />
          <span class="text-sm font-medium">Отчёт по исполнителям</span>
        </div>
        <table class="w-full text-sm">
          <thead>
            <tr class="text-left text-xs uppercase tracking-wider text-base-content/40 border-b border-base-300">
              <th class="font-medium px-5 py-2.5">Исполнитель</th>
              <th class="font-medium px-5 py-2.5 text-center">Открыто</th>
              <th class="font-medium px-5 py-2.5 text-center">Выполнено</th>
              <th class="font-medium px-5 py-2.5 text-center">Просрочено</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-base-300/50">
            <tr :for={row <- @assignee_summary} class="hover:bg-base-200/40 transition">
              <td class="px-5 py-3">
                <span class="flex items-center gap-2 font-medium">
                  <span class="grid place-items-center size-6 rounded-full bg-primary/15 text-primary text-[10px] font-semibold">
                    {initials(row.assignee.full_name)}
                  </span>
                  {row.assignee.full_name}
                </span>
              </td>
              <td class="px-5 py-3 text-center tabular font-semibold">{row.open}</td>
              <td class="px-5 py-3 text-center tabular text-success">{row.done}</td>
              <td class="px-5 py-3 text-center tabular">
                <span :if={row.overdue > 0} class="text-error font-semibold">{row.overdue}</span>
                <span :if={row.overdue == 0} class="text-base-content/30">—</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end

  defp priority_options,
    do: [{"Низкий", "low"}, {"Обычный", "normal"}, {"Высокий", "high"}, {"Срочный", "urgent"}]

  defp priority_label(:low), do: "Низкий"
  defp priority_label(:normal), do: "Обычный"
  defp priority_label(:high), do: "Высокий"
  defp priority_label(:urgent), do: "Срочный"

  defp priority_class(:urgent), do: "bg-error/10 text-error"
  defp priority_class(:high), do: "bg-warning/15 text-warning"
  defp priority_class(:normal), do: "bg-base-200 text-base-content/55"
  defp priority_class(:low), do: "bg-base-200 text-base-content/40"

  defp column_dot(:todo), do: "bg-base-content/30"
  defp column_dot(:in_progress), do: "bg-info"
  defp column_dot(:review), do: "bg-warning"
  defp column_dot(:done), do: "bg-success"

  defp initials(name), do: name |> String.split() |> Enum.take(2) |> Enum.map_join(&String.first/1)

  defp format_due(%DateTime{} = dt), do: Calendar.strftime(dt, "%d.%m %H:%M")

  # Просрочка — красным, если срок прошёл и задача не завершена.
  defp due_class(%{due_at: due, status: status}) do
    if status != :done and DateTime.compare(due, DateTime.utc_now()) == :lt do
      "text-error"
    else
      "text-base-content/40"
    end
  end
end
