defmodule SvcWeb.NotificationLive do
  @moduledoc "Лента in-app уведомлений пользователя (E3)."
  use SvcWeb, :live_view

  alias Svc.Notifications

  @impl true
  def mount(_params, _session, socket), do: {:ok, load(socket)}

  defp load(socket) do
    user = socket.assigns.current_user

    assign(socket,
      page_title: "Уведомления",
      notifications: Notifications.list_for_user(user.id, limit: 50),
      unread_count: Notifications.unread_count(user.id)
    )
  end

  @impl true
  def handle_event("read", %{"id" => id}, socket) do
    Notifications.mark_read(socket.assigns.current_user.id, id)
    {:noreply, load(socket)}
  end

  def handle_event("read_all", _params, socket) do
    Notifications.mark_all_read(socket.assigns.current_user.id)
    {:noreply, load(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} unread_count={@unread_count}>
      <div class="flex items-start justify-between gap-4 mb-6">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight">Уведомления</h1>
          <p class="text-sm text-base-content/55 mt-1">
            {if @unread_count > 0, do: "Непрочитанных: #{@unread_count}", else: "Все прочитаны"}
          </p>
        </div>
        <button :if={@unread_count > 0} phx-click="read_all" class="btn btn-ghost btn-sm gap-1.5">
          <.icon name="hero-check" class="size-4" /> Прочитать все
        </button>
      </div>

      <div
        :if={@notifications == []}
        class="rounded-xl border border-base-300 bg-base-100/50 px-5 py-14 text-center text-sm text-base-content/40"
      >
        <.icon name="hero-bell-slash" class="size-10 mx-auto mb-3 opacity-40" /> Уведомлений пока нет
      </div>

      <div class="space-y-2">
        <div
          :for={n <- @notifications}
          class={[
            "rounded-xl border p-4 flex items-start gap-3.5 transition",
            is_nil(n.read_at) && "border-primary/25 bg-primary/[0.05]",
            n.read_at && "border-base-300 bg-base-100/50"
          ]}
        >
          <span class={[
            "grid place-items-center size-9 rounded-lg shrink-0",
            kind_tone(n.kind)
          ]}>
            <.icon name={kind_icon(n.kind)} class="size-4.5" />
          </span>

          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2">
              <span class="text-xs text-base-content/45">{kind_label(n.kind)}</span>
              <span :if={is_nil(n.read_at)} class="size-1.5 rounded-full bg-primary"></span>
            </div>
            <div class="font-medium mt-0.5">{n.title}</div>
            <div :if={n.body} class="text-sm text-base-content/60 mt-0.5">{n.body}</div>
            <div class="text-xs text-base-content/40 mt-1.5 tabular">
              {Calendar.strftime(n.inserted_at, "%d.%m.%Y %H:%M")}
            </div>
          </div>

          <div class="flex items-center gap-1 shrink-0">
            <.link
              :if={n.meeting_id}
              navigate={~p"/admin/meetings/#{n.meeting_id}"}
              class="btn btn-ghost btn-xs gap-1"
            >
              К встрече <.icon name="hero-arrow-right" class="size-3.5" />
            </.link>
            <button
              :if={is_nil(n.read_at)}
              phx-click="read"
              phx-value-id={n.id}
              class="btn btn-ghost btn-xs btn-square"
              aria-label="Отметить прочитанным"
            >
              <.icon name="hero-check" class="size-4" />
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp kind_icon(:invite), do: "hero-calendar-days"
  defp kind_icon(:reminder), do: "hero-clock"
  defp kind_icon(:update), do: "hero-pencil-square"
  defp kind_icon(:cancel), do: "hero-x-circle"
  defp kind_icon(_), do: "hero-bell"

  defp kind_label(:invite), do: "Приглашение"
  defp kind_label(:reminder), do: "Напоминание"
  defp kind_label(:update), do: "Изменение"
  defp kind_label(:cancel), do: "Отмена"
  defp kind_label(_), do: "Уведомление"

  defp kind_tone(:invite), do: "bg-primary/15 text-primary"
  defp kind_tone(:reminder), do: "bg-warning/15 text-warning"
  defp kind_tone(:update), do: "bg-info/15 text-info"
  defp kind_tone(:cancel), do: "bg-error/15 text-error"
  defp kind_tone(_), do: "bg-base-200 text-base-content/60"
end
