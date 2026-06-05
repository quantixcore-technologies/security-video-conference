defmodule SvcWeb.SecurityLive do
  @moduledoc "Журнал событий захвата контента — для security-офицера/админа (E5)."
  use SvcWeb, :live_view

  alias Svc.AntiCapture

  @viewers [:super_admin, :security_officer]

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if user.role in @viewers do
      {:ok,
       assign(socket,
         page_title: "Безопасность",
         events: AntiCapture.list_events(user.org_id, limit: 100),
         critical: AntiCapture.critical_count(user.org_id)
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "Недостаточно прав для просмотра журнала захвата.")
       |> push_navigate(to: ~p"/admin")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="security" current_user={@current_user} unread_count={@unread_count}>
      <div class="flex items-start justify-between gap-4 mb-6">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight">Безопасность</h1>
          <p class="text-sm text-base-content/55 mt-1">Журнал попыток захвата контента (E5)</p>
        </div>
        <div
          :if={@critical > 0}
          class="inline-flex items-center gap-2 rounded-lg border border-error/25 bg-error/10 px-3 py-1.5 text-sm text-error"
        >
          <.icon name="hero-exclamation-triangle" class="size-4" /> Критических: {@critical}
        </div>
      </div>

      <div
        :if={@events == []}
        class="rounded-xl border border-base-300 bg-base-100/50 px-5 py-14 text-center text-sm text-base-content/40"
      >
        <.icon name="hero-shield-check" class="size-10 mx-auto mb-3 opacity-40 text-success" />
        Событий захвата не зафиксировано
        <div class="text-xs text-base-content/35 mt-2">
          Детекты приходят от нативного клиента (Tauri/mobile). Web-слой защищён watermark.
        </div>
      </div>

      <div :if={@events != []} class="rounded-xl border border-base-300 bg-base-100/50 overflow-hidden">
        <table class="w-full text-sm">
          <thead>
            <tr class="text-left text-xs uppercase tracking-wider text-base-content/40 border-b border-base-300">
              <th class="font-medium px-5 py-2.5">Событие</th>
              <th class="font-medium px-5 py-2.5">Платформа</th>
              <th class="font-medium px-5 py-2.5">Важность</th>
              <th class="font-medium px-5 py-2.5 tabular">Время</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-base-300/50">
            <tr :for={e <- @events} class="hover:bg-base-200/40 transition">
              <td class="px-5 py-3">
                <span class="inline-flex items-center gap-2">
                  <.icon name={kind_icon(e.kind)} class={["size-4", sev_text(e.severity)]} />
                  {kind_label(e.kind)}
                </span>
              </td>
              <td class="px-5 py-3 text-base-content/65">{e.platform || "—"}</td>
              <td class="px-5 py-3">
                <span class={"inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-medium #{sev_class(e.severity)}"}>
                  <span class={"size-1.5 rounded-full #{sev_dot(e.severity)}"}></span>
                  {sev_label(e.severity)}
                </span>
              </td>
              <td class="px-5 py-3 tabular text-base-content/60">
                {Calendar.strftime(e.occurred_at, "%d.%m.%Y %H:%M")}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end

  defp kind_icon(:screenshot_detected), do: "hero-camera"
  defp kind_icon(:recorder_detected), do: "hero-film"
  defp kind_icon(:screen_record_detected), do: "hero-video-camera"
  defp kind_icon(:protection_failed), do: "hero-shield-exclamation"

  defp kind_label(:screenshot_detected), do: "Скриншот"
  defp kind_label(:recorder_detected), do: "Обнаружен рекордер"
  defp kind_label(:screen_record_detected), do: "Запись экрана"
  defp kind_label(:protection_failed), do: "Сбой защиты"

  defp sev_label(:info), do: "Инфо"
  defp sev_label(:warning), do: "Предупреждение"
  defp sev_label(:critical), do: "Критично"

  defp sev_class(:info), do: "bg-base-200 text-base-content/60"
  defp sev_class(:warning), do: "bg-warning/10 text-warning"
  defp sev_class(:critical), do: "bg-error/10 text-error"

  defp sev_dot(:info), do: "bg-base-content/40"
  defp sev_dot(:warning), do: "bg-warning"
  defp sev_dot(:critical), do: "bg-error"

  defp sev_text(:info), do: "text-base-content/50"
  defp sev_text(:warning), do: "text-warning"
  defp sev_text(:critical), do: "text-error"
end
