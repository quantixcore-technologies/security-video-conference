defmodule SvcWeb.MeetingLive.Show do
  @moduledoc "Детали встречи + таблица посещаемости (RBAC-scoped, E2 UI)."
  use SvcWeb, :live_view

  alias Svc.{Meetings, Attendance, Authz, Audit}
  alias Svc.Meetings.Meeting

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    actor = socket.assigns.current_user

    meeting =
      actor.org_id |> Meetings.get_meeting!(id) |> Svc.Repo.preload([:started_by, :ended_by])

    # D-016: чужую встречу (не свою и куда не назначен) видеть нельзя — даже super_admin.
    unless Meetings.can_view_meeting?(actor, meeting),
      do: raise(Ecto.NoResultsError, queryable: Svc.Meetings.Meeting)

    Audit.log_action(actor, :journal_view, resource_type: :meeting, resource_id: meeting.id)

    visible = MapSet.new(Authz.visible_user_ids(actor))

    records =
      meeting.id
      |> Attendance.list_attendance()
      |> Enum.filter(&MapSet.member?(visible, &1.user_id))

    {:noreply,
     socket
     |> assign(:page_title, meeting.title)
     |> assign(:meeting, meeting)
     |> assign(:can_organize, Meetings.can_organize?(actor))
     |> assign(:can_open, Meetings.can_control?(actor, meeting))
     |> assign(:can_close, Meetings.can_close?(actor, meeting))
     |> assign(:closing, false)
     |> assign(:records, records)
     |> assign(:summary, Enum.frequencies_by(records, & &1.status))
     |> assign(:roster, Attendance.list_invitees_with_users(meeting.id))
     |> assign(:pending_ids, pending_ids(meeting, actor))
     |> assign(:my_invitee, Attendance.get_invitee(meeting.id, actor.id))
     |> assign_form(socket.assigns.live_action, meeting)}
  rescue
    Ecto.NoResultsError ->
      {:noreply,
       socket
       |> put_flash(:error, gettext("Встреча не найдена."))
       |> push_navigate(to: ~p"/admin/meetings")}
  end

  defp assign_form(socket, :edit, meeting),
    do: assign(socket, :form, to_form(Meetings.change_meeting(meeting)))

  defp assign_form(socket, :assign_task, meeting) do
    actor = socket.assigns.current_user

    if Meetings.can_organize?(actor) do
      socket
      |> assign(:assignees, Svc.Accounts.list_users(actor.org_id))
      |> assign(
        :form,
        to_form(%{"title" => "", "priority" => "normal", "assignee_id" => ""}, as: :task)
      )
    else
      socket
      |> put_flash(:error, gettext("Недостаточно прав для постановки поручений."))
      |> push_navigate(to: ~p"/admin/meetings/#{meeting.id}")
    end
  end

  defp assign_form(socket, _action, _meeting), do: assign(socket, :form, nil)

  @impl true
  def handle_event("save", %{"meeting" => params}, socket) do
    actor = socket.assigns.current_user

    case Meetings.update_meeting(socket.assigns.meeting, params) do
      {:ok, updated} ->
        Audit.log_action(actor, :meeting_update, resource_type: :meeting, resource_id: updated.id)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Встреча обновлена."))
         |> push_navigate(to: ~p"/admin/meetings/#{updated.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  # S43. Встречу ОТКРЫВАЕТ человек — фиксируем, кто и во сколько.
  def handle_event("open_meeting", _params, socket) do
    actor = socket.assigns.current_user

    case Meetings.open_meeting(actor, socket.assigns.meeting) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign_meeting(
           Svc.Repo.preload(updated, [:started_by, :ended_by], force: true),
           actor
         )
         |> put_flash(:info, gettext("Встреча открыта."))}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("Открыть встречу может только организатор."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Встреча уже открыта или завершена."))}
    end
  end

  def handle_event("show_close", _params, socket), do: {:noreply, assign(socket, :closing, true)}

  def handle_event("cancel_close", _params, socket),
    do: {:noreply, assign(socket, :closing, false)}

  # Закрывает тот, кто открыл (или организатор, если открывший отвалился).
  def handle_event("close_meeting", params, socket) do
    actor = socket.assigns.current_user
    attrs = %{summary: params["summary"]}

    case Meetings.close_meeting(actor, socket.assigns.meeting, attrs) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign_meeting(
           Svc.Repo.preload(updated, [:started_by, :ended_by], force: true),
           actor
         )
         |> assign(:closing, false)
         |> put_flash(:info, gettext("Встреча завершена."))}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Завершить встречу может тот, кто её открыл, или организатор.")
         )}

      {:error, :not_live} ->
        {:noreply, put_flash(socket, :error, gettext("Встреча не идёт."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Не удалось завершить встречу."))}
    end
  end

  def handle_event("rsvp", %{"status" => status}, socket) do
    actor = socket.assigns.current_user
    meeting = socket.assigns.meeting
    status_atom = String.to_existing_atom(status)

    case Attendance.set_rsvp(meeting.id, actor.id, status_atom) do
      {:ok, _} ->
        Audit.log_action(actor, :rsvp,
          resource_type: :meeting,
          resource_id: meeting.id,
          metadata: %{status: status}
        )

        notify_organizer_rsvp(meeting, actor, status_atom)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Ваш ответ записан."))
         |> assign(:my_invitee, Attendance.get_invitee(meeting.id, actor.id))
         |> assign(:roster, Attendance.list_invitees_with_users(meeting.id))}

      {:error, :not_invited} ->
        {:noreply, put_flash(socket, :error, gettext("Вы не в списке приглашённых."))}
    end
  end

  # S44. «Позвать на встречу»: уведомление тем, кто ещё не зашёл в звонок.
  def handle_event("call_all", _params, socket), do: call(socket, nil)

  def handle_event("call_one", %{"user-id" => uid}, socket), do: call(socket, [uid])

  def handle_event("create_task", %{"task" => params}, socket) do
    actor = socket.assigns.current_user
    meeting = socket.assigns.meeting

    attrs =
      params
      |> Map.put("meeting_id", meeting.id)
      |> drop_blank_assignee()

    case Svc.Tasks.create_task(actor, attrs) do
      {:ok, task} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("Поручение «%{title}» создано по итогам встречи.", title: task.title)
         )
         |> push_navigate(to: ~p"/admin/tasks")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply,
         put_flash(socket, :error, gettext("Не удалось создать поручение — проверьте название."))}
    end
  end

  defp drop_blank_assignee(%{"assignee_id" => ""} = params), do: Map.delete(params, "assignee_id")
  defp drop_blank_assignee(params), do: params

  defp call(socket, ids) do
    actor = socket.assigns.current_user
    meeting = socket.assigns.meeting

    case Meetings.call_participants(actor, meeting, user_ids: ids) do
      {:ok, called} ->
        {:noreply,
         socket
         |> assign(:pending_ids, pending_ids(meeting, actor))
         |> put_flash(
           :info,
           gettext("Приглашение отправлено: %{count}", count: length(called))
         )}

      {:error, :nobody_to_call} ->
        {:noreply, put_flash(socket, :error, gettext("Все приглашённые уже в звонке."))}

      {:error, :too_soon} ->
        {:noreply,
         put_flash(socket, :error, gettext("Приглашение уже отправлено — подождите минуту."))}

      {:error, :already_ended} ->
        {:noreply, put_flash(socket, :error, gettext("Встреча завершена."))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("Недостаточно прав."))}
    end
  end

  # Кого ещё можно позвать — по id, чтобы решать это прямо в списке ростера.
  defp pending_ids(meeting, actor) do
    if meeting.status == :ended do
      MapSet.new()
    else
      meeting |> Meetings.callable_participants(actor) |> MapSet.new(& &1.id)
    end
  end

  defp assign_meeting(socket, meeting, actor) do
    socket
    |> assign(:meeting, meeting)
    |> assign(:can_open, Meetings.can_control?(actor, meeting))
    |> assign(:can_close, Meetings.can_close?(actor, meeting))
    |> assign(:pending_ids, pending_ids(meeting, actor))
  end

  defp notify_organizer_rsvp(meeting, actor, status) do
    organizer = Svc.Accounts.get_user!(meeting.org_id, meeting.organizer_id)

    if organizer.id != actor.id do
      Svc.Notifications.notify(
        organizer,
        :update,
        "#{actor.full_name}: #{rsvp_label(status)}",
        body: gettext("Встреча: %{title}", title: meeting.title),
        meeting_id: meeting.id
      )
    end
  rescue
    _ -> :ok
  end

  defp policy_options,
    do: [
      {gettext("Нет"), :off},
      {gettext("Опционально"), :optional},
      {gettext("Обязательно"), :required}
    ]

  defp reaction_options,
    do: [
      {gettext("Ничего"), :none},
      {gettext("Предупредить"), :warn},
      {gettext("Выгнать"), :eject}
    ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      active="meetings"
      current_user={@current_user}
      unread_count={@unread_count}
    >
      <.link
        navigate={~p"/admin/meetings"}
        class="inline-flex items-center gap-1.5 text-sm text-base-content/55 hover:text-base-content transition mb-5"
      >
        <.icon name="hero-arrow-left" class="size-4" /> {gettext("Все встречи")}
      </.link>

      <div class="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <div class="flex items-center gap-3 flex-wrap">
            <h1 class="text-2xl font-semibold tracking-tight">{@meeting.title}</h1>
            <span class={"inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-medium #{mst_class(@meeting.status)}"}>
              <span class={"size-1.5 rounded-full #{mst_dot(@meeting.status)}"}></span>
              {mst_label(@meeting.status)}
            </span>
          </div>
          <div class="flex items-center gap-3 mt-2 text-sm text-base-content/55">
            <span class="inline-flex items-center gap-1.5">
              <.icon name="hero-calendar" class="size-4" />
              <span class="tabular">
                {if @meeting.scheduled_start, do: fmt(@meeting.scheduled_start), else: "Ad-hoc"}
              </span>
            </span>
            <span class="inline-flex items-center gap-1.5">
              <.icon
                name={
                  if @meeting.recording_policy == :off,
                    do: "hero-no-symbol",
                    else: "hero-video-camera"
                }
                class="size-4"
              /> {gettext("запись:")} {if @meeting.recording_policy == :off,
                do: gettext("нет"),
                else: gettext("да")}
            </span>
          </div>
        </div>
        <div :if={@live_action == :show} class="flex items-center gap-2 shrink-0">
          <.link
            href={~p"/admin/meetings/#{@meeting.id}/ics"}
            class="btn btn-ghost btn-sm gap-1.5"
            title={gettext("Экспорт в календарь (.ics)")}
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> .ics
          </.link>
          <.link
            :if={@can_organize}
            navigate={~p"/admin/meetings/#{@meeting.id}/assign-task"}
            class="btn btn-ghost btn-sm gap-1.5"
            title={gettext("Поставить поручение по итогам встречи")}
          >
            <.icon name="hero-clipboard-document-list" class="size-4" /> {gettext("Поручение")}
          </.link>
          <.link
            :if={@can_organize}
            navigate={~p"/admin/meetings/#{@meeting.id}/edit"}
            class="btn btn-ghost btn-sm gap-1.5"
          >
            <.icon name="hero-pencil-square" class="size-4" /> {gettext("Изменить")}
          </.link>
          <button
            :if={@can_open and @meeting.status == :planned}
            phx-click="open_meeting"
            class="btn btn-success btn-sm gap-1.5"
            title={gettext("Открыть встречу — будет записано, кто и когда её начал")}
          >
            <.icon name="hero-play-circle" class="size-4" /> {gettext("Начать встречу")}
          </button>
          <button
            :if={@can_close and @meeting.status == :live}
            phx-click="show_close"
            class="btn btn-ghost btn-sm gap-1.5 text-error"
          >
            <.icon name="hero-stop-circle" class="size-4" /> {gettext("Завершить встречу")}
          </button>
          <.link href={~p"/admin/meetings/#{@meeting.id}/call"} class="btn btn-primary btn-sm gap-2">
            <.icon name="hero-video-camera" class="size-4" /> {gettext("Войти в звонок")}
          </.link>
        </div>
      </div>
      
    <!-- S43: форма завершения — итог встречи попадает в историю -->
      <form
        :if={@closing and @meeting.status == :live}
        phx-submit="close_meeting"
        class="rounded-xl border border-error/30 bg-error/5 p-5 mt-6"
      >
        <h3 class="font-medium mb-1 flex items-center gap-2">
          <.icon name="hero-stop-circle" class="size-4 text-error" /> {gettext("Завершение встречи")}
        </h3>
        <p class="text-sm text-base-content/55 mb-3">
          {gettext("Итог останется в истории встречи. Поле можно оставить пустым.")}
        </p>
        <textarea
          name="summary"
          rows="3"
          class="textarea textarea-bordered w-full"
          placeholder={gettext("Что решили по итогам встречи")}
        ></textarea>
        <div class="flex items-center gap-2 mt-3">
          <button type="submit" class="btn btn-error btn-sm gap-1.5">
            <.icon name="hero-check" class="size-4" /> {gettext("Завершить встречу")}
          </button>
          <button type="button" phx-click="cancel_close" class="btn btn-ghost btn-sm">
            {gettext("Отмена")}
          </button>
        </div>
      </form>
      
    <!-- S43: фактическая история — когда реально шла, кто открыл/закрыл, зачем -->
      <div
        :if={@live_action == :show and (@meeting.started_at || @meeting.purpose)}
        class="rounded-xl border border-base-300 bg-base-100/50 p-5 mt-6"
      >
        <h3 class="font-medium mb-4 flex items-center gap-2">
          <.icon name="hero-clock" class="size-4 text-primary" /> {gettext("История встречи")}
        </h3>
        <dl class="grid gap-x-6 gap-y-3 sm:grid-cols-2">
          <div :if={@meeting.started_at}>
            <dt class="text-xs uppercase tracking-wide text-base-content/45">
              {gettext("Фактически шла")}
            </dt>
            <dd class="tabular mt-0.5">
              {fmt_local(@meeting.started_at)} — {if @meeting.ended_at,
                do: Calendar.strftime(local(@meeting.ended_at), "%H:%M"),
                else: gettext("идёт")}
              <span :if={Meeting.duration_seconds(@meeting)} class="text-base-content/50">
                ({dur(Meeting.duration_seconds(@meeting))})
              </span>
            </dd>
          </div>
          <div :if={@meeting.started_by}>
            <dt class="text-xs uppercase tracking-wide text-base-content/45">
              {gettext("Открыл встречу")}
            </dt>
            <dd class="mt-0.5">{@meeting.started_by.full_name}</dd>
          </div>
          <div :if={@meeting.ended_by}>
            <dt class="text-xs uppercase tracking-wide text-base-content/45">
              {gettext("Завершил встречу")}
            </dt>
            <dd class="mt-0.5">{@meeting.ended_by.full_name}</dd>
          </div>
          <div :if={@meeting.purpose} class="sm:col-span-2">
            <dt class="text-xs uppercase tracking-wide text-base-content/45">
              {gettext("Повод для встречи")}
            </dt>
            <dd class="mt-0.5 whitespace-pre-line">{@meeting.purpose}</dd>
          </div>
          <div :if={@meeting.summary} class="sm:col-span-2">
            <dt class="text-xs uppercase tracking-wide text-base-content/45">
              {gettext("Итог")}
            </dt>
            <dd class="mt-0.5 whitespace-pre-line">{@meeting.summary}</dd>
          </div>
        </dl>
      </div>

      <div
        :if={@live_action == :edit}
        class="rounded-xl border border-base-300 bg-base-100/50 p-5 mt-6"
      >
        <h3 class="font-medium mb-4 flex items-center gap-2">
          <.icon name="hero-pencil-square" class="size-4 text-primary" /> {gettext(
            "Редактирование встречи"
          )}
        </h3>
        <.form for={@form} phx-submit="save" class="space-y-3">
          <.input field={@form[:title]} type="text" label={gettext("Название")} required />
          <.input
            field={@form[:purpose]}
            type="textarea"
            rows="2"
            label={gettext("Повод для встречи")}
            placeholder={gettext("Зачем собираемся — останется в истории встречи")}
          />
          <div class="grid grid-cols-2 gap-3">
            <.input field={@form[:scheduled_start]} type="datetime-local" label={gettext("Начало")} />
            <.input field={@form[:scheduled_end]} type="datetime-local" label={gettext("Конец")} />
          </div>
          <.input
            field={@form[:recording_policy]}
            type="select"
            label={gettext("Запись")}
            options={policy_options()}
          />
          <div class="grid grid-cols-2 gap-3">
            <.input
              field={@form[:watermark_enabled]}
              type="checkbox"
              label={gettext("Водяной знак (watermark)")}
            />
            <.input
              field={@form[:capture_reaction]}
              type="select"
              label={gettext("Реакция на захват")}
              options={reaction_options()}
            />
          </div>
          <.input
            field={@form[:late_threshold_seconds]}
            type="number"
            label={gettext("Порог опоздания (сек)")}
          />
          <div class="flex gap-2 pt-2">
            <.button type="submit" phx-disable-with={gettext("Сохраняем...")}>
              {gettext("Сохранить")}
            </.button>
            <.link navigate={~p"/admin/meetings/#{@meeting.id}"} class="btn btn-ghost">
              {gettext("Отмена")}
            </.link>
          </div>
        </.form>
      </div>

      <div
        :if={@live_action == :assign_task}
        class="rounded-xl border border-base-300 bg-base-100/50 p-5 mt-6"
      >
        <h3 class="font-medium mb-1 flex items-center gap-2">
          <.icon name="hero-clipboard-document-list" class="size-4 text-primary" />
          {gettext("Поручение по итогам встречи")}
        </h3>
        <p class="text-sm text-base-content/55 mb-4">
          {gettext("Будет привязано к «%{title}» и появится на Kanban-доске.", title: @meeting.title)}
        </p>
        <.form for={@form} phx-submit="create_task" class="space-y-3">
          <.input field={@form[:title]} type="text" label={gettext("Что нужно сделать")} required />
          <.input
            field={@form[:description]}
            type="textarea"
            label={gettext("Описание (необязательно)")}
            rows="2"
          />
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <.input
              field={@form[:assignee_id]}
              type="select"
              label={gettext("Исполнитель")}
              prompt={gettext("Не назначено")}
              options={Enum.map(@assignees, &{&1.full_name, &1.id})}
            />
            <.input
              field={@form[:priority]}
              type="select"
              label={gettext("Приоритет")}
              options={[
                {gettext("Низкий"), "low"},
                {gettext("Обычный"), "normal"},
                {gettext("Высокий"), "high"},
                {gettext("Срочный"), "urgent"}
              ]}
            />
            <.input field={@form[:due_at]} type="datetime-local" label={gettext("Срок")} />
          </div>
          <div class="flex gap-2 pt-2">
            <.button type="submit" phx-disable-with={gettext("Создаём...")}>
              {gettext("Создать поручение")}
            </.button>
            <.link navigate={~p"/admin/meetings/#{@meeting.id}"} class="btn btn-ghost">
              {gettext("Отмена")}
            </.link>
          </div>
        </.form>
      </div>

      <div
        :if={@my_invitee && @live_action == :show}
        class="mt-6 rounded-xl border border-base-300 bg-base-100/50 p-4 flex items-center justify-between gap-4 flex-wrap"
      >
        <div class="flex items-center gap-2 text-sm">
          <.icon name="hero-envelope" class="size-4 text-base-content/50" />
          {gettext("Вы приглашены · ваш ответ:")}
          <span class={"px-2 py-0.5 rounded-full text-xs font-medium #{rsvp_class(@my_invitee.rsvp_status)}"}>
            {rsvp_label(@my_invitee.rsvp_status)}
          </span>
        </div>
        <div class="flex items-center gap-1.5">
          <button
            phx-click="rsvp"
            phx-value-status="accepted"
            class={[
              "btn btn-sm gap-1.5",
              @my_invitee.rsvp_status == :accepted && "btn-success",
              @my_invitee.rsvp_status != :accepted && "btn-ghost"
            ]}
          >
            <.icon name="hero-check" class="size-4" /> {gettext("Приду")}
          </button>
          <button
            phx-click="rsvp"
            phx-value-status="tentative"
            class={[
              "btn btn-sm gap-1.5",
              @my_invitee.rsvp_status == :tentative && "btn-warning",
              @my_invitee.rsvp_status != :tentative && "btn-ghost"
            ]}
          >
            <.icon name="hero-question-mark-circle" class="size-4" /> {gettext("Возможно")}
          </button>
          <button
            phx-click="rsvp"
            phx-value-status="declined"
            class={[
              "btn btn-sm gap-1.5",
              @my_invitee.rsvp_status == :declined && "btn-error",
              @my_invitee.rsvp_status != :declined && "btn-ghost"
            ]}
          >
            <.icon name="hero-x-mark" class="size-4" /> {gettext("Не приду")}
          </button>
        </div>
      </div>

      <div :if={@live_action == :show} class="flex flex-wrap gap-2 mt-6">
        <.stat label={gettext("Присутствовали")} value={@summary[:present] || 0} tone="success" />
        <.stat label={gettext("Опоздали")} value={@summary[:late] || 0} tone="warning" />
        <.stat label={gettext("Ушли раньше")} value={@summary[:left_early] || 0} tone="info" />
        <.stat label={gettext("Отсутствовали")} value={@summary[:absent] || 0} tone="error" />
      </div>

      <div
        :if={@live_action == :show}
        class="mt-6 rounded-xl border border-base-300 bg-base-100/50 overflow-hidden"
      >
        <div class="px-5 py-3 border-b border-base-300 flex items-center gap-2">
          <.icon name="hero-clipboard-document-check" class="size-4 text-base-content/45" />
          <span class="text-sm font-medium">{gettext("Журнал посещаемости")}</span>
        </div>

        <div :if={@records == []} class="px-5 py-10 text-center text-sm text-base-content/40">
          <.icon name="hero-inbox" class="size-8 mx-auto mb-2 opacity-40" /> {gettext(
            "Записей пока нет"
          )}
        </div>

        <table :if={@records != []} class="w-full text-sm">
          <thead>
            <tr class="text-left text-xs uppercase tracking-wider text-base-content/40 border-b border-base-300">
              <th class="font-medium px-5 py-2.5">{gettext("Сотрудник")}</th>
              <th class="font-medium px-5 py-2.5">{gettext("Статус")}</th>
              <th class="font-medium px-5 py-2.5 tabular">{gettext("Вход")}</th>
              <th class="font-medium px-5 py-2.5 tabular">{gettext("Выход")}</th>
              <th class="font-medium px-5 py-2.5">{gettext("Длит.")}</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-base-300/50">
            <tr :for={r <- @records} class="hover:bg-base-200/40 transition">
              <td class="px-5 py-3 font-medium">{r.user.full_name}</td>
              <td class="px-5 py-3"><.badge status={r.status} /></td>
              <td class="px-5 py-3 tabular text-base-content/70">{fmt(r.joined_at)}</td>
              <td class="px-5 py-3 tabular text-base-content/70">{fmt(r.left_at)}</td>
              <td class="px-5 py-3 tabular text-base-content/70">{dur(r.total_seconds)}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div
        :if={@live_action == :show and @can_organize and @roster != []}
        class="mt-6 rounded-xl border border-base-300 bg-base-100/50 overflow-hidden"
      >
        <div class="px-5 py-3 border-b border-base-300 flex items-center gap-2 flex-wrap">
          <.icon name="hero-user-group" class="size-4 text-base-content/45" />
          <span class="text-sm font-medium">{gettext("Приглашённые · ответы (RSVP)")}</span>
          <span class="flex-1"></span>
          <button
            :if={@can_close and MapSet.size(@pending_ids) > 0}
            phx-click="call_all"
            class="btn btn-primary btn-xs gap-1.5"
            title={gettext("Отправить уведомление всем, кто ещё не в звонке")}
          >
            <.icon name="hero-bell-alert" class="size-3.5" />
            {gettext("Позвать всех")} ({MapSet.size(@pending_ids)})
          </button>
        </div>
        <ul class="divide-y divide-base-300/50 text-sm">
          <li
            :for={inv <- @roster}
            class="px-5 py-2.5 flex items-center justify-between gap-3 hover:bg-base-200/40 transition"
          >
            <span class="font-medium">{inv.user.full_name}</span>
            <span class="flex items-center gap-2">
              <span
                :if={not MapSet.member?(@pending_ids, inv.user_id) and @meeting.status != :planned}
                class="text-xs text-success inline-flex items-center gap-1"
              >
                <.icon name="hero-check-circle" class="size-3.5" /> {gettext("в звонке")}
              </span>
              <button
                :if={@can_close and MapSet.member?(@pending_ids, inv.user_id)}
                phx-click="call_one"
                phx-value-user-id={inv.user_id}
                class="btn btn-ghost btn-xs gap-1"
                title={gettext("Позвать на встречу")}
              >
                <.icon name="hero-bell-alert" class="size-3.5" /> {gettext("Позвать")}
              </button>
              <span class={"px-2.5 py-0.5 rounded-full text-xs font-medium #{rsvp_class(inv.rsvp_status)}"}>
                {rsvp_label(inv.rsvp_status)}
              </span>
            </span>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :tone, :string, required: true

  defp stat(assigns) do
    ~H"""
    <div class={"inline-flex items-center gap-2 rounded-lg border px-3 py-1.5 text-sm #{tone_border(@tone)}"}>
      <span class={"size-2 rounded-full #{tone_dot(@tone)}"}></span>
      <span class="text-base-content/65">{@label}</span>
      <span class="tabular font-semibold">{@value}</span>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp badge(assigns) do
    ~H"""
    <span class={"inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-medium #{st_class(@status)}"}>
      <span class={"size-1.5 rounded-full #{tone_dot(st_tone(@status))}"}></span>
      {st_label(@status)}
    </span>
    """
  end

  defp st_tone(:present), do: "success"
  defp st_tone(:late), do: "warning"
  defp st_tone(:left_early), do: "info"
  defp st_tone(:absent), do: "error"

  defp st_class(:present), do: "bg-success/10 text-success"
  defp st_class(:late), do: "bg-warning/10 text-warning"
  defp st_class(:left_early), do: "bg-info/10 text-info"
  defp st_class(:absent), do: "bg-error/10 text-error"

  defp st_label(:present), do: gettext("Присутствовал")
  defp st_label(:late), do: gettext("Опоздал")
  defp st_label(:left_early), do: gettext("Ушёл раньше")
  defp st_label(:absent), do: gettext("Отсутствовал")

  defp tone_border("success"), do: "border-success/25"
  defp tone_border("warning"), do: "border-warning/25"
  defp tone_border("info"), do: "border-info/25"
  defp tone_border("error"), do: "border-error/25"

  defp tone_dot("success"), do: "bg-success"
  defp tone_dot("warning"), do: "bg-warning"
  defp tone_dot("info"), do: "bg-info"
  defp tone_dot("error"), do: "bg-error"

  defp fmt(nil), do: "—"
  defp fmt(dt), do: Calendar.strftime(dt, "%d.%m %H:%M")

  # UTC+5 (Asia/Tashkent, без перехода на летнее время).
  defp local(dt), do: DateTime.add(dt, 5 * 3600, :second)
  defp fmt_local(nil), do: "—"
  defp fmt_local(dt), do: dt |> local() |> Calendar.strftime("%d.%m %H:%M")

  defp dur(0), do: "—"
  defp dur(s) when s < 60, do: gettext("%{count} сек", count: s)

  defp dur(s) when s < 3600, do: gettext("%{count} мин", count: div(s, 60))

  defp dur(s),
    do: gettext("%{h} ч %{m} мин", h: div(s, 3600), m: div(rem(s, 3600), 60))

  defp mst_label(:planned), do: gettext("Запланирована")
  defp mst_label(:live), do: gettext("Идёт")
  defp mst_label(:ended), do: gettext("Завершена")

  defp mst_class(:planned), do: "bg-base-200 text-base-content/70"
  defp mst_class(:live), do: "bg-success/10 text-success"
  defp mst_class(:ended), do: "bg-base-200 text-base-content/50"

  defp mst_dot(:planned), do: "bg-base-content/40"
  defp mst_dot(:live), do: "bg-success animate-pulse"
  defp mst_dot(:ended), do: "bg-base-content/30"

  defp rsvp_label(:accepted), do: gettext("Приду")
  defp rsvp_label(:declined), do: gettext("Не приду")
  defp rsvp_label(:tentative), do: gettext("Возможно")
  defp rsvp_label(:pending), do: gettext("Без ответа")

  defp rsvp_class(:accepted), do: "bg-success/10 text-success"
  defp rsvp_class(:declined), do: "bg-error/10 text-error"
  defp rsvp_class(:tentative), do: "bg-warning/10 text-warning"
  defp rsvp_class(:pending), do: "bg-base-200 text-base-content/50"
end
