defmodule SvcWeb.CalendarLive do
  @moduledoc "Календарь встреч — месяц-вид, RBAC-scoped (E3)."
  use SvcWeb, :live_view

  alias Svc.Meetings

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(params, _uri, socket) do
    today = Date.utc_today()
    year = parse_int(params["year"], today.year)
    month = parse_int(params["month"], today.month)
    {:noreply, load(socket, year, month, today)}
  end

  defp load(socket, year, month, today) do
    first = Date.new!(year, month, 1)
    last = Date.end_of_month(first)
    grid_start = Date.beginning_of_week(first, :monday)
    grid_end = Date.end_of_week(last, :monday)
    days = Date.range(grid_start, grid_end) |> Enum.to_list()

    from_dt = DateTime.new!(grid_start, ~T[00:00:00], "Etc/UTC")
    to_dt = DateTime.new!(grid_end, ~T[23:59:59], "Etc/UTC")

    by_day =
      socket.assigns.current_user
      |> Meetings.list_in_range(from_dt, to_dt)
      |> Enum.group_by(&DateTime.to_date(&1.scheduled_start))

    {py, pm} = prev_month(year, month)
    {ny, nm} = next_month(year, month)

    assign(socket,
      page_title: gettext("Календарь"),
      year: year,
      month: month,
      today: today,
      weeks: Enum.chunk_every(days, 7),
      by_day: by_day,
      prev: %{year: py, month: pm},
      next: %{year: ny, month: nm}
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      active="calendar"
      current_user={@current_user}
      unread_count={@unread_count}
    >
      <div class="flex items-center justify-between gap-4 mb-6 flex-wrap">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight">
            {month_name(@month)} {@year}
          </h1>
          <p class="text-sm text-base-content/55 mt-1">{gettext("Календарь встреч организации")}</p>
        </div>
        <div class="flex items-center gap-1.5">
          <.link
            patch={~p"/admin/calendar?#{%{year: @prev.year, month: @prev.month}}"}
            class="btn btn-ghost btn-sm btn-square"
          >
            <.icon name="hero-chevron-left" class="size-4" />
          </.link>
          <.link patch={~p"/admin/calendar"} class="btn btn-ghost btn-sm">{gettext("Сегодня")}</.link>
          <.link
            patch={~p"/admin/calendar?#{%{year: @next.year, month: @next.month}}"}
            class="btn btn-ghost btn-sm btn-square"
          >
            <.icon name="hero-chevron-right" class="size-4" />
          </.link>
        </div>
      </div>

      <div class="grid grid-cols-7 gap-px bg-base-300 rounded-xl overflow-hidden border border-base-300">
        <div
          :for={wd <- weekdays()}
          class="bg-base-100 px-2 py-2.5 text-xs uppercase tracking-wider text-base-content/45 text-center font-medium"
        >
          {wd}
        </div>

        <%= for week <- @weeks, day <- week do %>
          <div class={[
            "bg-base-100 min-h-26 p-1.5 flex flex-col gap-1",
            day.month != @month && "bg-base-200/30"
          ]}>
            <div class={[
              "text-xs tabular w-6 h-6 grid place-items-center rounded-full",
              day == @today && "bg-primary text-primary-content font-semibold",
              day != @today && day.month == @month && "text-base-content/70",
              day != @today && day.month != @month && "text-base-content/30"
            ]}>
              {day.day}
            </div>

            <.link
              :for={m <- Map.get(@by_day, day, [])}
              navigate={~p"/admin/meetings/#{m.id}"}
              class={[
                "block text-[11px] px-1.5 py-0.5 rounded truncate leading-tight",
                chip_class(m.status)
              ]}
              title={m.title}
            >
              <span class="tabular">{Calendar.strftime(m.scheduled_start, "%H:%M")}</span> {m.title}
            </.link>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp chip_class(:live), do: "bg-success/15 text-success"
  defp chip_class(:ended), do: "bg-base-200 text-base-content/45"
  defp chip_class(_), do: "bg-primary/15 text-primary"

  defp weekdays do
    [
      gettext("Пн"),
      gettext("Вт"),
      gettext("Ср"),
      gettext("Чт"),
      gettext("Пт"),
      gettext("Сб"),
      gettext("Вс")
    ]
  end

  defp month_name(m), do: elem(month_names(), m)

  defp month_names do
    {
      "",
      gettext("Январь"),
      gettext("Февраль"),
      gettext("Март"),
      gettext("Апрель"),
      gettext("Май"),
      gettext("Июнь"),
      gettext("Июль"),
      gettext("Август"),
      gettext("Сентябрь"),
      gettext("Октябрь"),
      gettext("Ноябрь"),
      gettext("Декабрь")
    }
  end

  defp prev_month(y, 1), do: {y - 1, 12}
  defp prev_month(y, m), do: {y, m - 1}
  defp next_month(y, 12), do: {y + 1, 1}
  defp next_month(y, m), do: {y, m + 1}

  defp parse_int(nil, default), do: default

  defp parse_int(s, default) do
    case Integer.parse(to_string(s)) do
      {n, _} -> n
      _ -> default
    end
  end
end
