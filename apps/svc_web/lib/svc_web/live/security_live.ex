defmodule SvcWeb.SecurityLive do
  @moduledoc "Журнал событий захвата контента — для security-офицера/админа (E5)."
  use SvcWeb, :live_view

  alias Svc.{AntiCapture, Geo}

  @viewers [:super_admin, :security_officer]

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if user.role in @viewers do
      {:ok,
       assign(socket,
         page_title: "Безопасность",
         events: AntiCapture.list_events(user.org_id, limit: 100),
         critical: AntiCapture.critical_count(user.org_id),
         geo_checks: Geo.list_checks(user.org_id, limit: 50),
         flagged: Geo.flagged_count(user.org_id),
         policy: Geo.get_policy(user.org_id)
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "Недостаточно прав для просмотра журнала захвата.")
       |> push_navigate(to: ~p"/admin")}
    end
  end

  @impl true
  def handle_event("save_policy", %{"policy" => params}, socket) do
    user = socket.assigns.current_user

    params =
      params
      |> Map.update("allowed_countries", ["UZ"], &split_csv/1)
      |> Map.update("whitelist_ips", [], &split_csv/1)

    case Geo.upsert_policy(user.org_id, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Гео-политика сохранена.")
         |> assign(:policy, Geo.get_policy(user.org_id))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Не удалось сохранить политику.")}
    end
  end

  defp split_csv(str) when is_binary(str), do: String.split(str, ~r/[,\s]+/, trim: true)
  defp split_csv(list) when is_list(list), do: list

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      active="security"
      current_user={@current_user}
      unread_count={@unread_count}
    >
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

      <div class="rounded-xl border border-base-300 bg-base-100/50 p-5 mb-6">
        <h2 class="text-sm font-medium mb-4 flex items-center gap-2">
          <.icon name="hero-adjustments-horizontal" class="size-4 text-base-content/45" />
          Гео-политика (pre-join gate)
        </h2>
        <form phx-submit="save_policy" class="space-y-3">
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <label class="block">
              <span class="text-xs font-medium text-base-content/60 mb-1 block">Режим</span>
              <select name="policy[mode]" class="select select-sm select-bordered w-full bg-base-100">
                <option value="off" selected={@policy.mode == :off}>Выключен</option>
                <option value="flag_only" selected={@policy.mode == :flag_only}>Только флаг</option>
                <option value="enforce" selected={@policy.mode == :enforce}>Блокировка</option>
              </select>
            </label>
            <label class="block">
              <span class="text-xs font-medium text-base-content/60 mb-1 block">
                Разрешённые страны (ISO)
              </span>
              <input
                type="text"
                name="policy[allowed_countries]"
                value={Enum.join(@policy.allowed_countries, ", ")}
                class="input input-sm input-bordered w-full bg-base-100 tabular"
              />
            </label>
          </div>
          <label class="block">
            <span class="text-xs font-medium text-base-content/60 mb-1 block">
              Whitelist IP (через запятую)
            </span>
            <input
              type="text"
              name="policy[whitelist_ips]"
              value={Enum.join(@policy.whitelist_ips, ", ")}
              placeholder="напр. 195.158.1.1"
              class="input input-sm input-bordered w-full bg-base-100 tabular"
            />
          </label>
          <div class="flex items-center gap-4 flex-wrap">
            <label class="flex items-center gap-2 text-sm">
              <input type="hidden" name="policy[block_vpn]" value="false" />
              <input
                type="checkbox"
                name="policy[block_vpn]"
                value="true"
                checked={@policy.block_vpn}
                class="checkbox checkbox-sm"
              /> Блокировать VPN
            </label>
            <label class="flex items-center gap-2 text-sm">
              <input type="hidden" name="policy[block_proxy]" value="false" />
              <input
                type="checkbox"
                name="policy[block_proxy]"
                value="true"
                checked={@policy.block_proxy}
                class="checkbox checkbox-sm"
              /> Блокировать proxy
            </label>
            <button type="submit" class="btn btn-primary btn-sm ml-auto gap-1.5">
              <.icon name="hero-check" class="size-4" /> Сохранить
            </button>
          </div>
        </form>
      </div>

      <h2 class="text-sm font-medium mb-3 flex items-center gap-2">
        <.icon name="hero-film" class="size-4 text-base-content/45" /> Журнал захвата контента
      </h2>

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

      <div
        :if={@events != []}
        class="rounded-xl border border-base-300 bg-base-100/50 overflow-hidden"
      >
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

      <div class="flex items-center gap-2 mt-8 mb-3">
        <.icon name="hero-globe-alt" class="size-4 text-base-content/45" />
        <h2 class="text-sm font-medium">Сетевые / гео-проверки (pre-join)</h2>
        <span :if={@flagged > 0} class="text-xs text-warning">· флагнуто: {@flagged}</span>
      </div>

      <div
        :if={@geo_checks == []}
        class="rounded-xl border border-base-300 bg-base-100/50 px-5 py-8 text-center text-sm text-base-content/40"
      >
        Проверок ещё не было
      </div>

      <div
        :if={@geo_checks != []}
        class="rounded-xl border border-base-300 bg-base-100/50 overflow-hidden"
      >
        <table class="w-full text-sm">
          <thead>
            <tr class="text-left text-xs uppercase tracking-wider text-base-content/40 border-b border-base-300">
              <th class="font-medium px-5 py-2.5 tabular">IP</th>
              <th class="font-medium px-5 py-2.5">Страна</th>
              <th class="font-medium px-5 py-2.5">Решение</th>
              <th class="font-medium px-5 py-2.5 tabular">Время</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-base-300/50">
            <tr :for={c <- @geo_checks} class="hover:bg-base-200/40 transition">
              <td class="px-5 py-3 tabular text-base-content/70">{c.ip}</td>
              <td class="px-5 py-3 text-base-content/65">{c.ip_country || "—"}</td>
              <td class="px-5 py-3">
                <span class={"inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-medium #{dec_class(c.decision)}"}>
                  <span class={"size-1.5 rounded-full #{dec_dot(c.decision)}"}></span>
                  {dec_label(c.decision)}
                </span>
                <span
                  :if={c.spoofing}
                  title={c.spoofing_reason}
                  class="ml-1.5 inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-error/15 text-error"
                >
                  <.icon name="hero-map-pin" class="size-3" /> спуф
                </span>
              </td>
              <td class="px-5 py-3 tabular text-base-content/60">
                {Calendar.strftime(c.checked_at, "%d.%m %H:%M")}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end

  defp dec_label(:allow), do: "Разрешён"
  defp dec_label(:block), do: "Заблокирован"
  defp dec_label(:flag), do: "Флаг"

  defp dec_class(:allow), do: "bg-success/10 text-success"
  defp dec_class(:block), do: "bg-error/10 text-error"
  defp dec_class(:flag), do: "bg-warning/10 text-warning"

  defp dec_dot(:allow), do: "bg-success"
  defp dec_dot(:block), do: "bg-error"
  defp dec_dot(:flag), do: "bg-warning"

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
