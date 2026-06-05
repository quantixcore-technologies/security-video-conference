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

    # Просмотр журнала посещаемости — чувствительное действие (D-014)
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
     |> assign(:records, records)
     |> assign(:summary, Enum.frequencies_by(records, & &1.status))}
  rescue
    Ecto.NoResultsError ->
      {:noreply,
       socket
       |> put_flash(:error, "Встреча не найдена.")
       |> push_navigate(to: ~p"/admin/meetings")}
  end

  defp fmt_time(nil), do: "—"
  defp fmt_time(dt), do: Calendar.strftime(dt, "%d.%m %H:%M")

  defp fmt_dur(0), do: "—"
  defp fmt_dur(s), do: "#{div(s, 60)} мин"

  defp st_badge(:present), do: "badge-success"
  defp st_badge(:late), do: "badge-warning"
  defp st_badge(:left_early), do: "badge-info"
  defp st_badge(:absent), do: "badge-error"

  defp st_label(:present), do: "Присутствовал"
  defp st_label(:late), do: "Опоздал"
  defp st_label(:left_early), do: "Ушёл раньше"
  defp st_label(:absent), do: "Отсутствовал"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@meeting.title}
        <:subtitle>
          {if @meeting.scheduled_start, do: fmt_time(@meeting.scheduled_start), else: "Ad-hoc"} ·
          запись: {if @meeting.recording_policy == :off, do: "нет", else: "да"}
        </:subtitle>
        <:actions>
          <.link navigate={~p"/admin/meetings"} class="btn btn-ghost btn-sm">← Встречи</.link>
        </:actions>
      </.header>

      <div class="flex gap-2 mt-4 text-sm">
        <span class="badge badge-success">Присутствовали: {@summary[:present] || 0}</span>
        <span class="badge badge-warning">Опоздали: {@summary[:late] || 0}</span>
        <span class="badge badge-info">Ушли раньше: {@summary[:left_early] || 0}</span>
        <span class="badge badge-error">Отсутствовали: {@summary[:absent] || 0}</span>
      </div>

      <h3 class="font-semibold mt-6 mb-2">Журнал посещаемости</h3>
      <.table id="attendance" rows={@records}>
        <:col :let={r} label="ФИО">{r.user.full_name}</:col>
        <:col :let={r} label="Статус">
          <span class={"badge #{st_badge(r.status)}"}>{st_label(r.status)}</span>
        </:col>
        <:col :let={r} label="Вход">{fmt_time(r.joined_at)}</:col>
        <:col :let={r} label="Выход">{fmt_time(r.left_at)}</:col>
        <:col :let={r} label="Длительность">{fmt_dur(r.total_seconds)}</:col>
      </.table>

      <p :if={@records == []} class="text-sm opacity-60 mt-2">
        Записей посещаемости пока нет.
      </p>
    </Layouts.app>
    """
  end
end
