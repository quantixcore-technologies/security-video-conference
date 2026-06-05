defmodule SvcWeb.MeetingLive.Index do
  @moduledoc "Список встреч + создание с ростером (E1/E2 UI)."
  use SvcWeb, :live_view

  alias Svc.{Meetings, Accounts, Attendance}

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action)}
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

  defp load_meetings(socket) do
    assign(socket, :meetings, Meetings.list_meetings(socket.assigns.current_user.org_id))
  end

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
    <Layouts.app flash={@flash} active="meetings">
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

      <div class="rounded-xl border border-base-300 bg-base-100/50 overflow-hidden">
        <div :if={@meetings == []} class="px-5 py-10 text-center text-sm text-base-content/40">
          <.icon name="hero-video-camera-slash" class="size-8 mx-auto mb-2 opacity-40" /> Встреч пока нет
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
