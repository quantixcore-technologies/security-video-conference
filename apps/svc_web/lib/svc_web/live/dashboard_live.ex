defmodule SvcWeb.DashboardLive do
  @moduledoc "Панель управления админки (E0)."
  use SvcWeb, :live_view

  alias Svc.{Authz, Audit}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    recent_audit =
      if Authz.org_wide?(user), do: Audit.list_logs(user.org_id, limit: 10), else: []

    {:ok,
     assign(socket,
       page_title: "Панель управления",
       visible_users: length(Authz.visible_user_ids(user)),
       recent_audit: recent_audit
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Панель управления
        <:subtitle>
          {@current_user.full_name} · {role_label(@current_user.role)}
        </:subtitle>
        <:actions>
          <.link href={~p"/logout"} method="delete" class="btn btn-ghost btn-sm">Выйти</.link>
        </:actions>
      </.header>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-6">
        <div class="card bg-base-200 p-5">
          <div class="text-sm opacity-60">Видимых сотрудников</div>
          <div class="text-3xl font-bold">{@visible_users}</div>
        </div>
        <div class="card bg-base-200 p-5 flex flex-col items-center justify-center gap-2">
          <.link navigate={~p"/admin/users"} class="btn btn-primary btn-sm w-full">
            Сотрудники <span aria-hidden="true">&rarr;</span>
          </.link>
          <.link navigate={~p"/admin/meetings"} class="btn btn-primary btn-sm w-full">
            Встречи <span aria-hidden="true">&rarr;</span>
          </.link>
        </div>
      </div>

      <div :if={@recent_audit != []} class="mt-8">
        <h3 class="font-semibold mb-2">Последние события (аудит)</h3>
        <ul class="text-sm space-y-1">
          <li
            :for={log <- @recent_audit}
            class="flex justify-between border-b border-base-300 py-1"
          >
            <span class="font-mono">{log.action}</span>
            <span class="opacity-50">{Calendar.strftime(log.inserted_at, "%d.%m %H:%M")}</span>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  defp role_label(:super_admin), do: "Суперадмин"
  defp role_label(:admin_hr), do: "Админ/HR"
  defp role_label(:manager), do: "Руководитель"
  defp role_label(:employee), do: "Сотрудник"
  defp role_label(:security_officer), do: "Офицер безопасности"
end
