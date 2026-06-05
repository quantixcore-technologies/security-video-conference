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
     |> assign(:records, records)
     |> assign(:summary, Enum.frequencies_by(records, & &1.status))}
  rescue
    Ecto.NoResultsError ->
      {:noreply,
       socket
       |> put_flash(:error, "Встреча не найдена.")
       |> push_navigate(to: ~p"/admin/meetings")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="meetings" current_user={@current_user}>
      <.link
        navigate={~p"/admin/meetings"}
        class="inline-flex items-center gap-1.5 text-sm text-base-content/55 hover:text-base-content transition mb-5"
      >
        <.icon name="hero-arrow-left" class="size-4" /> Все встречи
      </.link>

      <div class="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight">{@meeting.title}</h1>
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
        <.link
          href={~p"/admin/meetings/#{@meeting.id}/call"}
          class="btn btn-primary gap-2"
        >
          <.icon name="hero-video-camera" class="size-4" /> Войти в звонок
        </.link>
      </div>

      <div class="flex flex-wrap gap-2 mt-6">
        <.stat label="Присутствовали" value={@summary[:present] || 0} tone="success" />
        <.stat label="Опоздали" value={@summary[:late] || 0} tone="warning" />
        <.stat label="Ушли раньше" value={@summary[:left_early] || 0} tone="info" />
        <.stat label="Отсутствовали" value={@summary[:absent] || 0} tone="error" />
      </div>

      <div class="mt-6 rounded-xl border border-base-300 bg-base-100/50 overflow-hidden">
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
end
