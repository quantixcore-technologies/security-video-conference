defmodule SvcWeb.DashboardLive do
  @moduledoc "Панель управления админки (E0)."
  use SvcWeb, :live_view

  alias Svc.{Authz, Audit, Meetings, Orgs}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    recent_audit = if Authz.org_wide?(user), do: Audit.list_logs(user.org_id, limit: 8), else: []

    {:ok,
     assign(socket,
       page_title: "Панель управления",
       visible_users: length(Authz.visible_user_ids(user)),
       meetings_count: length(Meetings.list_meetings(user.org_id)),
       department: department_name(user),
       recent_audit: recent_audit
     )}
  end

  defp department_name(%{department_id: nil}), do: nil

  defp department_name(user) do
    Orgs.get_department!(user.org_id, user.department_id).name
  rescue
    _ -> nil
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="dashboard" current_user={@current_user}>
      <h1 class="text-2xl font-semibold tracking-tight">Панель управления</h1>
      <p class="text-sm text-base-content/55 mt-1 mb-6">Обзор организации и активности</p>

      <div class="rounded-xl border border-base-300 bg-base-100/50 p-5 mb-6 flex items-center gap-4">
        <span class="grid place-items-center size-14 rounded-full bg-primary/15 text-primary text-lg font-semibold ring-1 ring-primary/15 overflow-hidden shrink-0">
          <img :if={@current_user.photo_path} src={@current_user.photo_path} class="w-full h-full object-cover" alt="" />
          <span :if={!@current_user.photo_path}>{initials(@current_user.full_name)}</span>
        </span>
        <div class="flex-1 min-w-0">
          <div class="font-semibold">{@current_user.full_name}</div>
          <div class="text-sm text-base-content/55 flex items-center gap-3 flex-wrap mt-1">
            <span class="px-2 py-0.5 rounded-full bg-primary/10 text-primary text-xs font-medium">
              {role_label(@current_user.role)}
            </span>
            <span :if={@department} class="inline-flex items-center gap-1">
              <.icon name="hero-building-office-2" class="size-3.5" /> {@department}
            </span>
            <span class="inline-flex items-center gap-1">
              <.icon
                name={if @current_user.totp_enabled, do: "hero-shield-check", else: "hero-shield-exclamation"}
                class={["size-3.5", @current_user.totp_enabled && "text-success", !@current_user.totp_enabled && "text-warning"]}
              /> 2FA {if @current_user.totp_enabled, do: "включена", else: "выключена"}
            </span>
            <span :if={@current_user.last_login_at} class="inline-flex items-center gap-1 tabular text-xs text-base-content/40">
              <.icon name="hero-clock" class="size-3.5" />
              {Calendar.strftime(@current_user.last_login_at, "%d.%m %H:%M")}
            </span>
          </div>
        </div>
      </div>

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

  defp role_label(:super_admin), do: "Суперадмин"
  defp role_label(:admin_hr), do: "Админ/HR"
  defp role_label(:manager), do: "Руководитель"
  defp role_label(:employee), do: "Сотрудник"
  defp role_label(:security_officer), do: "Офицер безопасности"

  defp initials(name), do: name |> String.split() |> Enum.take(2) |> Enum.map_join(&String.first/1)
end
