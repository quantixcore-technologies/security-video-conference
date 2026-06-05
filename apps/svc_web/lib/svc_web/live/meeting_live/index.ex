defmodule SvcWeb.MeetingLive.Index do
  @moduledoc "Список встреч + создание с ростером (E1/E2 UI)."
  use SvcWeb, :live_view

  import Ecto.Query
  alias Svc.{Meetings, Accounts, Attendance, Repo}
  alias Svc.Meetings.Meeting

  @per_page 10

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:filters, parse_filters(params))
     |> apply_action(socket.assigns.live_action)}
  end

  defp parse_filters(params) do
    %{q: params["q"] || "", status: params["status"] || "", page: parse_page(params["page"])}
  end

  defp parse_page(p) do
    case Integer.parse(to_string(p)) do
      {n, _} when n > 0 -> n
      _ -> 1
    end
  end

  defp apply_action(socket, :index) do
    actor = socket.assigns.current_user

    socket
    |> assign(:page_title, "Встречи")
    |> assign(:can_organize, Meetings.can_organize?(actor))
    |> assign(:roster, [])
    |> assign(:form, nil)
    |> load_meetings()
  end

  defp apply_action(socket, :new) do
    actor = socket.assigns.current_user

    if Meetings.can_organize?(actor) do
      socket
      |> assign(:page_title, "Новая встреча")
      |> assign(:can_organize, true)
      |> assign(:roster, Accounts.list_users(actor.org_id))
      |> assign(:form, to_form(%{"title" => "", "recording_policy" => "off"}, as: :meeting))
      |> load_meetings()
    else
      socket
      |> put_flash(:error, "Недостаточно прав для создания встреч.")
      |> push_navigate(to: ~p"/admin/meetings")
    end
  end

  @impl true
  def handle_event("save", %{"meeting" => params}, socket) do
    actor = socket.assigns.current_user

    attrs = %{
      title: params["title"],
      recording_policy: params["recording_policy"] || "off",
      scheduled_start: parse_dt(params["scheduled_start"]),
      scheduled_end: parse_dt(params["scheduled_end"])
    }

    case Meetings.create_meeting(actor, attrs) do
      {:ok, meeting} ->
        add_roster(meeting, params["invitee_ids"])
        notify_invitees(meeting, params["invitee_ids"], actor)

        {:noreply,
         socket
         |> put_flash(:info, "Встреча «#{meeting.title}» создана.")
         |> push_navigate(to: ~p"/admin/meetings/#{meeting.id}")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, :form, to_form(Map.put(cs, :action, :insert)))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Недостаточно прав.")}
    end
  end

  defp add_roster(_meeting, nil), do: :ok

  defp add_roster(meeting, ids) when is_list(ids) do
    users = Accounts.list_users(meeting.org_id)

    Enum.each(ids, fn id ->
      with %{} = user <- Enum.find(users, &(to_string(&1.id) == id)) do
        Attendance.add_invitee(meeting, user)
      end
    end)
  end

  defp add_roster(_, _), do: :ok

  defp notify_invitees(_meeting, nil, _actor), do: :ok

  defp notify_invitees(meeting, ids, actor) when is_list(ids) do
    invited =
      meeting.org_id
      |> Accounts.list_users()
      |> Enum.filter(&(to_string(&1.id) in ids))

    Svc.Notifications.notify_many(
      invited,
      :invite,
      "Приглашение на встречу: #{meeting.title}",
      body: "Организатор: #{actor.full_name}",
      meeting_id: meeting.id
    )
  end

  defp notify_invitees(_, _, _), do: :ok

  def handle_event("filter", %{"q" => q, "status" => status}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/meetings?#{filter_params(q, status)}")}
  end

  defp filter_params(q, status) do
    %{page: 1} |> put_if(:q, q) |> put_if(:status, status)
  end

  defp put_if(map, _key, ""), do: map
  defp put_if(map, key, val), do: Map.put(map, key, val)

  defp page_path(f, page) do
    params = %{page: page} |> put_if(:q, f.q) |> put_if(:status, f.status)
    ~p"/admin/meetings?#{params}"
  end

  defp load_meetings(socket) do
    f = socket.assigns.filters
    org_id = socket.assigns.current_user.org_id

    base =
      from(m in Meeting, where: m.org_id == ^org_id)
      |> filter_search(f.q)
      |> filter_status(f.status)

    total = Repo.aggregate(base, :count)
    pages = max(1, ceil(total / @per_page))
    page = min(f.page, pages)

    meetings =
      base
      |> order_by([m], desc: m.inserted_at)
      |> limit(^@per_page)
      |> offset(^((page - 1) * @per_page))
      |> Repo.all()

    assign(socket, meetings: meetings, total: total, pages: pages, page: page)
  end

  defp filter_search(query, ""), do: query
  defp filter_search(query, term), do: where(query, [m], ilike(m.title, ^"%#{term}%"))

  defp filter_status(query, ""), do: query
  defp filter_status(query, status), do: where(query, [m], m.status == ^String.to_existing_atom(status))

  defp parse_dt(nil), do: nil
  defp parse_dt(""), do: nil

  defp parse_dt(str) do
    case NaiveDateTime.from_iso8601(str <> ":00") do
      {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
      _ -> nil
    end
  end

  defp policy_options, do: [{"Без записи", "off"}, {"Опционально", "optional"}, {"Обязательно", "required"}]

  defp status_label(:planned), do: "Запланирована"
  defp status_label(:live), do: "Идёт"
  defp status_label(:ended), do: "Завершена"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="meetings" current_user={@current_user} unread_count={@unread_count}>
      <div class="flex items-start justify-between gap-4 mb-6">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight">Встречи</h1>
          <p class="text-sm text-base-content/55 mt-1">Видеоконференции организации</p>
        </div>
        <.link
          :if={@can_organize and @live_action == :index}
          navigate={~p"/admin/meetings/new"}
          class="btn btn-primary gap-2"
        >
          <.icon name="hero-plus" class="size-4" /> Встреча
        </.link>
      </div>

      <div :if={@live_action == :new} class="rounded-xl border border-base-300 bg-base-100/50 p-5 mb-5">
        <h3 class="font-medium mb-4 flex items-center gap-2">
          <.icon name="hero-video-camera" class="size-4 text-primary" /> Новая встреча
        </h3>
        <.form for={@form} phx-submit="save" class="space-y-3">
          <.input field={@form[:title]} type="text" label="Название" required />
          <div class="grid grid-cols-2 gap-3">
            <.input field={@form[:scheduled_start]} type="datetime-local" label="Начало" />
            <.input field={@form[:scheduled_end]} type="datetime-local" label="Конец" />
          </div>
          <.input
            field={@form[:recording_policy]}
            type="select"
            label="Запись"
            options={policy_options()}
          />

          <fieldset class="border border-base-300 rounded p-3">
            <legend class="text-sm font-medium px-1">Ростер (ожидаемые участники)</legend>
            <div class="grid grid-cols-2 gap-1 max-h-48 overflow-y-auto">
              <label :for={u <- @roster} class="flex items-center gap-2 text-sm">
                <input type="checkbox" name="meeting[invitee_ids][]" value={u.id} class="checkbox checkbox-sm" />
                {u.full_name}
              </label>
            </div>
          </fieldset>

          <div class="flex gap-2 pt-2">
            <.button type="submit" phx-disable-with="Создаём...">Создать</.button>
            <.link navigate={~p"/admin/meetings"} class="btn btn-ghost">Отмена</.link>
          </div>
        </.form>
      </div>

      <div :if={@live_action == :index} class="flex flex-wrap items-center gap-2 mb-4">
        <form phx-change="filter" phx-submit="filter" class="flex flex-wrap items-center gap-2 flex-1">
          <div class="relative flex-1 min-w-52">
            <.icon name="hero-magnifying-glass" class="size-4 absolute left-3 top-1/2 -translate-y-1/2 text-base-content/40" />
            <input
              type="text"
              name="q"
              value={@filters.q}
              placeholder="Поиск по названию"
              phx-debounce="300"
              class="input input-sm input-bordered w-full pl-9 bg-base-100"
            />
          </div>
          <select name="status" class="select select-sm select-bordered bg-base-100">
            <option value="">Любой статус</option>
            <option value="planned" selected={@filters.status == "planned"}>Запланирована</option>
            <option value="live" selected={@filters.status == "live"}>Идёт</option>
            <option value="ended" selected={@filters.status == "ended"}>Завершена</option>
          </select>
        </form>
      </div>

      <div class="rounded-xl border border-base-300 bg-base-100/50 overflow-hidden">
        <div :if={@meetings == []} class="px-5 py-10 text-center text-sm text-base-content/40">
          <.icon name="hero-video-camera-slash" class="size-8 mx-auto mb-2 opacity-40" /> Ничего не найдено
        </div>
        <table :if={@meetings != []} class="w-full text-sm">
          <thead>
            <tr class="text-left text-xs uppercase tracking-wider text-base-content/40 border-b border-base-300">
              <th class="font-medium px-5 py-2.5">Название</th>
              <th class="font-medium px-5 py-2.5">Тип</th>
              <th class="font-medium px-5 py-2.5">Статус</th>
              <th class="font-medium px-5 py-2.5">Запись</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-base-300/50">
            <tr :for={m <- @meetings} class="hover:bg-base-200/40 transition">
              <td class="px-5 py-3">
                <.link navigate={~p"/admin/meetings/#{m.id}"} class="font-medium hover:text-primary transition inline-flex items-center gap-2">
                  <.icon name="hero-video-camera" class="size-4 text-base-content/35" />
                  {m.title}
                </.link>
              </td>
              <td class="px-5 py-3 text-base-content/60">{if m.type == :ad_hoc, do: "Ad-hoc", else: "План"}</td>
              <td class="px-5 py-3">
                <span class={"inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-medium #{status_class(m.status)}"}>
                  <span class={"size-1.5 rounded-full #{status_dot(m.status)}"}></span>
                  {status_label(m.status)}
                </span>
              </td>
              <td class="px-5 py-3">
                <.icon :if={m.recording_policy != :off} name="hero-check-circle" class="size-4 text-success" />
                <span :if={m.recording_policy == :off} class="text-base-content/30">—</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={@live_action == :index and @pages > 1} class="flex items-center justify-between mt-4 text-sm">
        <span class="text-base-content/55 tabular">{@total} встреч · стр. {@page} из {@pages}</span>
        <div class="flex items-center gap-1">
          <.link
            patch={page_path(@filters, @page - 1)}
            class={["btn btn-sm btn-ghost btn-square", @page <= 1 && "pointer-events-none opacity-30"]}
          >
            <.icon name="hero-chevron-left" class="size-4" />
          </.link>
          <.link
            patch={page_path(@filters, @page + 1)}
            class={["btn btn-sm btn-ghost btn-square", @page >= @pages && "pointer-events-none opacity-30"]}
          >
            <.icon name="hero-chevron-right" class="size-4" />
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp status_class(:planned), do: "bg-base-200 text-base-content/70"
  defp status_class(:live), do: "bg-success/10 text-success"
  defp status_class(:ended), do: "bg-base-200 text-base-content/50"

  defp status_dot(:planned), do: "bg-base-content/40"
  defp status_dot(:live), do: "bg-success animate-pulse"
  defp status_dot(:ended), do: "bg-base-content/30"
end
