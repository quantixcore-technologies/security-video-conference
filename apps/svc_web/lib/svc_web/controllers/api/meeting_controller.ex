defmodule SvcWeb.API.MeetingController do
  @moduledoc "JSON API для Tauri-клиента (E1): получить токен входа в встречу."
  use SvcWeb, :controller

  alias Svc.{Meetings, LiveKit, Audit, Geo, Authz, Attendance, Notifications}

  def index(conn, _params) do
    user = conn.assigns.current_user

    meetings =
      for m <- Meetings.list_visible_meetings(user) do
        %{
          id: m.id,
          title: m.title,
          status: m.status,
          type: m.type,
          scheduled_start: m.scheduled_start,
          scheduled_end: m.scheduled_end
        }
      end

    json(conn, %{meetings: meetings, can_organize: Meetings.can_organize?(user)})
  end

  @doc "Пользователи, которых актор вправе назначить на встречу (D-016)."
  def assignable(conn, _params) do
    users =
      for u <- Authz.assignable_users(conn.assigns.current_user) do
        %{id: u.id, full_name: u.full_name, username: u.username, role: u.role}
      end

    json(conn, %{users: users})
  end

  @doc "Создание встречи из нативного клиента (super_admin/manager). D-015/D-016."
  def create(conn, params) do
    user = conn.assigns.current_user

    if Meetings.can_organize?(user) do
      attrs = %{
        title: String.trim(params["title"] || ""),
        recording_policy: "off",
        scheduled_start: parse_dt(params["scheduled_start"])
      }

      case Meetings.create_meeting(user, attrs) do
        {:ok, meeting} ->
          # Назначаем только тех, кого актор вправе (assignable), — server-side guard.
          wanted = Enum.map(params["invitee_ids"] || [], &to_string/1)

          invited =
            Authz.assignable_users(user)
            |> Enum.filter(&(to_string(&1.id) in wanted))

          Enum.each(invited, &Attendance.add_invitee(meeting, &1))

          Notifications.notify_many(
            invited,
            :invite,
            "Uchrashuvga taklif: #{meeting.title}",
            body: "Tashkilotchi: #{user.full_name}",
            meeting_id: meeting.id
          )

          Audit.log_action(user, :meeting_create, resource_type: :meeting, resource_id: meeting.id)

          conn
          |> put_status(:created)
          |> json(%{id: meeting.id, title: meeting.title, status: meeting.status})

        {:error, %Ecto.Changeset{} = cs} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "invalid", details: changeset_errors(cs)})

        {:error, :unauthorized} ->
          conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
      end
    else
      conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
    end
  end

  defp parse_dt(nil), do: nil
  defp parse_dt(""), do: nil

  defp parse_dt(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> dt
      _ ->
        # datetime-local "2026-09-03T14:30" — секунды/зону добавляем сами
        case NaiveDateTime.from_iso8601(s <> ":00") do
          {:ok, ndt} -> DateTime.from_naive!(ndt, "Etc/UTC")
          _ -> nil
        end
    end
  end

  defp changeset_errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, _} -> msg end)
  end

  def join(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user

    case fetch_meeting(user.org_id, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "meeting_not_found"})

      meeting ->
        # E7 pre-join gate: классификация IP + запись GPS (нативный клиент).
        # MVP без MMDB: gate возвращает только :allow/:flag (никогда :block — см. Svc.Geo).
        # flag = пометка для ручной проверки, НЕ отказ → в звонок пускаем. Когда подключим
        # MaxMind MMDB (locus) и появится :block — компилятор потребует ветку отказа (D-012).
        case Geo.gate(user.org_id, remote_ip(conn), gate_opts(user, meeting, params)) do
          {:allow, _reason} -> issue_token(conn, user, meeting)
          {:flag, _reason} -> issue_token(conn, user, meeting)
        end
    end
  end

  defp issue_token(conn, user, meeting) do
    case LiveKit.join_token(user, meeting) do
      {:ok, token} ->
        Audit.log_action(user, :meeting_join,
          resource_type: :meeting,
          resource_id: meeting.id
        )

        json(conn, %{
          url: LiveKit.url(),
          token: token,
          room: meeting.livekit_room_name
        })

      {:error, reason} ->
        conn |> put_status(:service_unavailable) |> json(%{error: to_string(reason)})
    end
  end

  defp gate_opts(user, meeting, params) do
    [
      user_id: user.id,
      meeting_id: meeting.id,
      gps_lat: to_float(params["lat"]),
      gps_lon: to_float(params["lon"]),
      gps_accuracy: to_float(params["accuracy"])
    ]
  end

  defp to_float(nil), do: nil
  defp to_float(n) when is_number(n), do: n / 1

  defp to_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp remote_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()

  defp fetch_meeting(org_id, id) do
    Meetings.get_meeting!(org_id, id)
  rescue
    Ecto.NoResultsError -> nil
  end
end
