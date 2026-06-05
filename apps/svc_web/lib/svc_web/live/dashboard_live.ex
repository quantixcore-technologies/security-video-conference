defmodule SvcWeb.DashboardLive do
  @moduledoc "Панель управления админки (E0)."
  use SvcWeb, :live_view

  alias Svc.{Authz, Audit, Meetings}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    recent_audit = if Authz.org_wide?(user), do: Audit.list_logs(user.org_id, limit: 8), else: []

    {:ok,
     assign(socket,
       page_title: "Панель управления",
       visible_users: length(Authz.visible_user_ids(user)),
       meetings_count: length(Meetings.list_meetings(user.org_id)),
       recent_audit: recent_audit
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="dashboard" current_user={@current_user}>
      <h1 class="text-2xl font-semibold tracking-tight">Здравствуйте, {first_name(@current_user.full_name)}</h1>
      <p class="text-sm text-base-content/55 mt-1 mb-6">Обзор организации и активности</p>

      <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <.metric icon="hero-users" label="Сотрудники" value={@visible_users} hint="видимых по вашей роли" />
        <.metric icon="hero-video-camera" label="Встречи" value={@meetings_count} hint="всего в организации" />
        <.link
          navigate={~p"/admin/meetings"}
          class="group rounded-xl border border-primary/20 bg-primary/[0.07] p-5 flex flex-col justify-between hover:bg-primary/10 transition"
        >
          <.icon name="hero-plus-circle" class="size-5 text-primary" />
          <span class="mt-3 text-sm font-medium text-primary flex items-center gap-1">
            К встречам
            <.icon name="hero-arrow-right" class="size-4 group-hover:translate-x-0.5 transition" />
          </span>
        </.link>
      </div>

      <div :if={@recent_audit != []} class="mt-8 rounded-xl border border-base-300 bg-base-100/50 overflow-hidden">
        <div class="px-5 py-3 border-b border-base-300 flex items-center gap-2">
          <.icon name="hero-clock" class="size-4 text-base-content/45" />
          <span class="text-sm font-medium">Журнал аудита</span>
          <span class="text-xs text-base-content/40">· последние события</span>
        </div>
        <ul class="divide-y divide-base-300/50">
          <li
            :for={log <- @recent_audit}
            class="px-5 py-2.5 flex items-center justify-between text-sm hover:bg-base-200/40 transition"
          >
            <span class="flex items-center gap-2.5 min-w-0">
              <span class="size-1.5 rounded-full bg-primary/60 shrink-0"></span>
              <span class="tabular text-base-content/80 truncate">{log.action}</span>
            </span>
            <span class="tabular text-xs text-base-content/40 shrink-0 ml-3">
              {Calendar.strftime(log.inserted_at, "%d.%m %H:%M")}
            </span>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :hint, :string, required: true

  defp metric(assigns) do
    ~H"""
    <div class="rounded-xl border border-base-300 bg-base-100/50 p-5">
      <div class="flex items-center justify-between">
        <span class="text-xs uppercase tracking-wider text-base-content/45">{@label}</span>
        <.icon name={@icon} class="size-4 text-base-content/35" />
      </div>
      <div class="mt-2 text-3xl font-semibold tabular">{@value}</div>
      <div class="text-xs text-base-content/45 mt-1">{@hint}</div>
    </div>
    """
  end

  defp first_name(full_name) do
    case String.split(full_name) do
      [_last, first | _] -> first
      [single] -> single
      _ -> full_name
    end
  end
end
