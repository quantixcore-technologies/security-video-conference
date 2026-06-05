defmodule SvcWeb.MeetingLive.Show do
  @moduledoc "Детали встречи + таблица посещаемости (RBAC-scoped, E2 UI)."
  use SvcWeb, :live_view

  alias Svc.{Meetings, Attendance, Authz, Audit}

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    actor = socket.assigns.current_user
    meeting = Meetings.get_meeting!(actor.org_id, id)

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
     |> assign(:records, records)
     |> assign(:summary, Enum.frequencies_by(records, & &1.status))
     |> assign(:roster, Attendance.list_invitees_with_users(meeting.id))
     |> assign(:my_invitee, Attendance.get_invitee(meeting.id, actor.id))
     |> assign_form(socket.assigns.live_action, meeting)}
  rescue
    Ecto.NoResultsError ->
      {:noreply,
       socket
       |> put_flash(:error, "Встреча не найдена.")
       |> push_navigate(to: ~p"/admin/meetings")}
  end

  defp assign_form(socket, :edit, meeting),
    do: assign(socket, :form, to_form(Meetings.change_meeting(meeting)))

  defp assign_form(socket, _action, _meeting), do: assign(socket, :form, nil)

  @impl true
  def handle_event("save", %{"meeting" => params}, socket) do
    actor = socket.assigns.current_user

    case Meetings.update_meeting(socket.assigns.meeting, params) do
      {:ok, updated} ->
        Audit.log_action(actor, :meeting_update, resource_type: :meeting, resource_id: updated.id)

        {:noreply,
         socket
         |> put_flash(:info, "Встреча обновлена.")
         |> push_navigate(to: ~p"/admin/meetings/#{updated.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("end_meeting", _params, socket) do
    actor = socket.assigns.current_user
    {:ok, updated} = Meetings.end_meeting(socket.assigns.meeting)
    Audit.log_action(actor, :meeting_end, resource_type: :meeting, resource_id: updated.id)
    {:noreply, socket |> assign(:meeting, updated) |> put_flash(:info, "Встреча завершена.")}
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
         |> put_flash(:info, "Ваш ответ записан.")
         |> assign(:my_invitee, Attendance.get_invitee(meeting.id, actor.id))
         |> assign(:roster, Attendance.list_invitees_with_users(meeting.id))}

      {:error, :not_invited} ->
        {:noreply, put_flash(socket, :error, "Вы не в списке приглашённых.")}
    end
  end

  defp notify_organizer_rsvp(meeting, actor, status) do
    organizer = Svc.Accounts.get_user!(meeting.org_id, meeting.organizer_id)

    if organizer.id != actor.id do
      Svc.Notifications.notify(
        organizer,
        :update,
        "#{actor.full_name}: #{rsvp_label(status)}",
        body: "Встреча: #{meeting.title}",
        meeting_id: meeting.id
      )
    end
  rescue
    _ -> :ok
  end

  defp policy_options,
    do: [{"Нет", :off}, {"Опционально", :optional}, {"Обязательно", :required}]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="meetings" current_user={@current_user} unread_count={@unread_count}>
      <.link
        navigate={~p"/admin/meetings"}
        class="inline-flex items-center gap-1.5 text-sm text-base-content/55 hover:text-base-content transition mb-5"
      >
        <.icon name="hero-arrow-left" class="size-4" /> Все встречи
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
              <.icon name={if @meeting.recording_policy == :off, do: "hero-no-symbol", else: "hero-video-camera"} class="size-4" />
              запись: {if @meeting.recording_policy == :off, do: "нет", else: "да"}
            </span>
          </div>
        </div>
        <div :if={@live_action == :show} class="flex items-center gap-2 shrink-0">
          <.link
            href={~p"/admin/meetings/#{@meeting.id}/ics"}
            class="btn btn-ghost btn-sm gap-1.5"
            title="Экспорт в календарь (.ics)"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> .ics
          </.link>
          <.link
            :if={@can_organize}
            navigate={~p"/admin/meetings/#{@meeting.id}/edit"}
            class="btn btn-ghost btn-sm gap-1.5"
          >
            <.icon name="hero-pencil-square" class="size-4" /> Изменить
          </.link>
          <button
            :if={@can_organize and @meeting.status != :ended}
            phx-click="end_meeting"
            data-confirm="Завершить встречу? Будет рассчитана посещаемость."
            class="btn btn-ghost btn-sm gap-1.5 text-error"
          >
            <.icon name="hero-stop-circle" class="size-4" /> Завершить
          </button>
          <.link href={~p"/admin/meetings/#{@meeting.id}/call"} class="btn btn-primary btn-sm gap-2">
            <.icon name="hero-video-camera" class="size-4" /> Войти в звонок
          </.link>
        </div>
      </div>

      <div :if={@live_action == :edit} class="rounded-xl border border-base-300 bg-base-100/50 p-5 mt-6">
        <h3 class="font-medium mb-4 flex items-center gap-2">
          <.icon name="hero-pencil-square" class="size-4 text-primary" /> Редактирование встречи
        </h3>
        <.form for={@form} phx-submit="save" class="space-y-3">
          <.input field={@form[:title]} type="text" label="Название" required />
          <div class="grid grid-cols-2 gap-3">
            <.input field={@form[:scheduled_start]} type="datetime-local" label="Начало" />
            <.input field={@form[:scheduled_end]} type="datetime-local" label="Конец" />
          </div>
          <.input field={@form[:recording_policy]} type="select" label="Запись" options={policy_options()} />
          <.input field={@form[:late_threshold_seconds]} type="number" label="Порог опоздания (сек)" />
          <div class="flex gap-2 pt-2">
            <.button type="submit" phx-disable-with="Сохраняем...">Сохранить</.button>
            <.link navigate={~p"/admin/meetings/#{@meeting.id}"} class="btn btn-ghost">Отмена</.link>
          </div>
        </.form>
      </div>

      <div
        :if={@my_invitee && @live_action == :show}
        class="mt-6 rounded-xl border border-base-300 bg-base-100/50 p-4 flex items-center justify-between gap-4 flex-wrap"
      >
        <div class="flex items-center gap-2 text-sm">
          <.icon name="hero-envelope" class="size-4 text-base-content/50" /> Вы приглашены · ваш ответ:
          <span class={"px-2 py-0.5 rounded-full text-xs font-medium #{rsvp_class(@my_invitee.rsvp_status)}"}>
            {rsvp_label(@my_invitee.rsvp_status)}
          </span>
        </div>
        <div class="flex items-center gap-1.5">
          <button
            phx-click="rsvp"
            phx-value-status="accepted"
            class={["btn btn-sm gap-1.5", @my_invitee.rsvp_status == :accepted && "btn-success", @my_invitee.rsvp_status != :accepted && "btn-ghost"]}
          >
            <.icon name="hero-check" class="size-4" /> Приду
          </button>
          <button
            phx-click="rsvp"
            phx-value-status="tentative"
            class={["btn btn-sm gap-1.5", @my_invitee.rsvp_status == :tentative && "btn-warning", @my_invitee.rsvp_status != :tentative && "btn-ghost"]}
          >
            <.icon name="hero-question-mark-circle" class="size-4" /> Возможно
          </button>
          <button
            phx-click="rsvp"
            phx-value-status="declined"
            class={["btn btn-sm gap-1.5", @my_invitee.rsvp_status == :declined && "btn-error", @my_invitee.rsvp_status != :declined && "btn-ghost"]}
          >
            <.icon name="hero-x-mark" class="size-4" /> Не приду
          </button>
        </div>
      </div>

      <div :if={@live_action == :show} class="flex flex-wrap gap-2 mt-6">
        <.stat label="Присутствовали" value={@summary[:present] || 0} tone="success" />
        <.stat label="Опоздали" value={@summary[:late] || 0} tone="warning" />
        <.stat label="Ушли раньше" value={@summary[:left_early] || 0} tone="info" />
        <.stat label="Отсутствовали" value={@summary[:absent] || 0} tone="error" />
      </div>

      <div :if={@live_action == :show} class="mt-6 rounded-xl border border-base-300 bg-base-100/50 overflow-hidden">
        <div class="px-5 py-3 border-b border-base-300 flex items-center gap-2">
          <.icon name="hero-clipboard-document-check" class="size-4 text-base-content/45" />
          <span class="text-sm font-medium">Журнал посещаемости</span>
        </div>

        <div :if={@records == []} class="px-5 py-10 text-center text-sm text-base-content/40">
          <.icon name="hero-inbox" class="size-8 mx-auto mb-2 opacity-40" /> Записей пока нет
        </div>

        <table :if={@records != []} class="w-full text-sm">
          <thead>
            <tr class="text-left text-xs uppercase tracking-wider text-base-content/40 border-b border-base-300">
              <th class="font-medium px-5 py-2.5">Сотрудник</th>
              <th class="font-medium px-5 py-2.5">Статус</th>
              <th class="font-medium px-5 py-2.5 tabular">Вход</th>
              <th class="font-medium px-5 py-2.5 tabular">Выход</th>
              <th class="font-medium px-5 py-2.5">Длит.</th>
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
        <div class="px-5 py-3 border-b border-base-300 flex items-center gap-2">
          <.icon name="hero-user-group" class="size-4 text-base-content/45" />
          <span class="text-sm font-medium">Приглашённые · ответы (RSVP)</span>
        </div>
        <ul class="divide-y divide-base-300/50 text-sm">
          <li
            :for={inv <- @roster}
            class="px-5 py-2.5 flex items-center justify-between hover:bg-base-200/40 transition"
          >
            <span class="font-medium">{inv.user.full_name}</span>
            <span class={"px-2.5 py-0.5 rounded-full text-xs font-medium #{rsvp_class(inv.rsvp_status)}"}>
              {rsvp_label(inv.rsvp_status)}
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

  defp st_label(:present), do: "Присутствовал"
  defp st_label(:late), do: "Опоздал"
  defp st_label(:left_early), do: "Ушёл раньше"
  defp st_label(:absent), do: "Отсутствовал"

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

  defp dur(0), do: "—"
  defp dur(s), do: "#{div(s, 60)} мин"

  defp mst_label(:planned), do: "Запланирована"
  defp mst_label(:live), do: "Идёт"
  defp mst_label(:ended), do: "Завершена"

  defp mst_class(:planned), do: "bg-base-200 text-base-content/70"
  defp mst_class(:live), do: "bg-success/10 text-success"
  defp mst_class(:ended), do: "bg-base-200 text-base-content/50"

  defp mst_dot(:planned), do: "bg-base-content/40"
  defp mst_dot(:live), do: "bg-success animate-pulse"
  defp mst_dot(:ended), do: "bg-base-content/30"

  defp rsvp_label(:accepted), do: "Приду"
  defp rsvp_label(:declined), do: "Не приду"
  defp rsvp_label(:tentative), do: "Возможно"
  defp rsvp_label(:pending), do: "Без ответа"

  defp rsvp_class(:accepted), do: "bg-success/10 text-success"
  defp rsvp_class(:declined), do: "bg-error/10 text-error"
  defp rsvp_class(:tentative), do: "bg-warning/10 text-warning"
  defp rsvp_class(:pending), do: "bg-base-200 text-base-content/50"
end
