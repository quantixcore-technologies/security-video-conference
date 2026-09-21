defmodule SvcWeb.API.MeetingController do
  @moduledoc "JSON API для Tauri-клиента (E1): получить токен входа в встречу."
  use SvcWeb, :controller

  alias Svc.{Meetings, LiveKit, Audit, Geo, Authz, Attendance, Notifications}

  def index(conn, _params) do
    user = conn.assigns.current_user

    meetings =
      for m <- Meetings.list_active_meetings(user) do
        m
        |> meeting_json(user)
        |> Map.merge(%{
          type: m.type,
          scheduled_end: m.scheduled_end,
          # Кого ещё можно позвать — чтобы клиент показал кнопку с числом.
          pending_count:
            if(m.status != :ended and Meetings.can_close?(user, m),
              do: length(Meetings.callable_participants(m, user)),
              else: 0
            )
        })
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
        purpose: trim_or_nil(params["purpose"]),
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

          Audit.log_action(user, :meeting_create,
            resource_type: :meeting,
            resource_id: meeting.id
          )

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
      {:ok, dt, _} ->
        dt

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

  @doc """
  Майлисни очиш (S43): статус `live` бўлади, ким ва қачон очгани ёзилади.

  Веб-хук автоматик очишидан фарқи — бу ерда аниқ ОДАМ бор, шунинг учун
  `started_by` тўлади: майлисни ёпишга биринчи навбатда ўша одам ҳақли.
  """
  def open(conn, %{"id" => id}) do
    control(conn, id, &Meetings.open_meeting(&1, &2))
  end

  @doc "Майлисни якунлаш: очган одам ёпади, натижа (`summary`) тарихга ёзилади."
  def close(conn, %{"id" => id} = params) do
    attrs = %{summary: trim_or_nil(params["summary"])}
    control(conn, id, &Meetings.close_meeting(&1, &2, attrs))
  end

  # Очиш/ёпиш учун умумий қобиқ: кўринмайдиган майлис — 404 (мавжудлигини
  # ошкор қилмаймиз, join'даги қоиданинг ўзи), ҳуқуқ йўқ бўлса — 403.
  defp control(conn, id, fun) do
    user = conn.assigns.current_user

    with meeting when not is_nil(meeting) <- fetch_meeting(user.org_id, id),
         true <- Meetings.can_view_meeting?(user, meeting) do
      case fun.(user, meeting) do
        {:ok, updated} ->
          json(conn, meeting_json(updated, user))

        {:error, :unauthorized} ->
          conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

        {:error, %Ecto.Changeset{} = cs} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "invalid", details: changeset_errors(cs)})

        {:error, reason} ->
          conn |> put_status(:conflict) |> json(%{error: to_string(reason)})
      end
    else
      _ -> conn |> put_status(:not_found) |> json(%{error: "meeting_not_found"})
    end
  end

  @doc """
  «Позвать на встречу» (S44) — уведомление тем, кто ещё не зашёл в звонок.

  `user_ids` (необязательно) — позвать конкретных людей; без него зовём всех
  неявившихся. Повторный вызов в течение минуты → 429 (защита от спама).
  """
  def nudge(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user
    ids = params["user_ids"]

    with meeting when not is_nil(meeting) <- fetch_meeting(user.org_id, id),
         true <- Meetings.can_view_meeting?(user, meeting) do
      case Meetings.call_participants(user, meeting, user_ids: ids) do
        {:ok, called} ->
          json(conn, %{
            called: length(called),
            users: Enum.map(called, &%{id: &1.id, full_name: &1.full_name})
          })

        {:error, :unauthorized} ->
          conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

        {:error, :too_soon} ->
          conn |> put_status(:too_many_requests) |> json(%{error: "too_soon"})

        {:error, reason} ->
          conn |> put_status(:conflict) |> json(%{error: to_string(reason)})
      end
    else
      _ -> conn |> put_status(:not_found) |> json(%{error: "meeting_not_found"})
    end
  end

  @doc "Тугаган майлислар тарихи: қачондан қачонгача, нима учун, ким очиб ким ёпган."
  def history(conn, params) do
    user = conn.assigns.current_user
    limit = params["limit"] |> parse_limit()

    items =
      for m <- Meetings.history(user, limit: limit) do
        m
        |> meeting_json(user)
        |> Map.merge(%{
          organizer_name: name_of(m.organizer),
          started_by_name: name_of(m.started_by),
          ended_by_name: name_of(m.ended_by)
        })
      end

    json(conn, %{meetings: items})
  end

  defp parse_limit(nil), do: 50

  defp parse_limit(v) do
    case Integer.parse(to_string(v)) do
      {n, _} when n > 0 -> min(n, 200)
      _ -> 50
    end
  end

  defp name_of(%Svc.Accounts.User{full_name: name}), do: name
  defp name_of(_), do: nil

  # Клиентлар (Android/iOS/Tauri) учун майлиснинг ягона кўриниши.
  defp meeting_json(m, user) do
    %{
      id: m.id,
      title: m.title,
      status: m.status,
      purpose: m.purpose,
      summary: m.summary,
      scheduled_start: m.scheduled_start,
      started_at: m.started_at,
      ended_at: m.ended_at,
      duration_seconds: Svc.Meetings.Meeting.duration_seconds(m),
      can_open: m.status == :planned and Meetings.can_control?(user, m),
      can_close: m.status == :live and Meetings.can_close?(user, m)
    }
  end

  defp trim_or_nil(nil), do: nil

  defp trim_or_nil(s) when is_binary(s) do
    case String.trim(s) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trim_or_nil(_), do: nil

  def join(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user

    # Право на звонок = та же видимость, что и в списке (D-016): организатор или
    # приглашённый. Одного org-scoping мало: id встреч последовательны, и участник
    # той же организации мог бы подобрать чужую закрытую встречу и получить
    # LiveKit-токен, хотя в списке её не видит (нарушение конфиденциальности встречи).
    # Не-видимую отдаём как 404 — не раскрываем сам факт её существования.
    with meeting when not is_nil(meeting) <- fetch_meeting(user.org_id, id),
         true <- Meetings.can_view_meeting?(user, meeting) do
      # S45: вышел из звонка второй раз — обратно не пускаем (см. Meetings.join_guard/2).
      case Meetings.join_guard(user, meeting) do
        {:blocked, reason} ->
          conn
          |> put_status(:forbidden)
          |> json(%{
            error: to_string(reason),
            message:
              "Siz majlisdan ikkinchi marta chiqib ketdingiz. Qayta kirish yopildi — " <>
                "tashkilotchiga xabar berildi."
          })

        guard ->
          join_after_guard(conn, user, meeting, params, guard)
      end
    else
      _ -> conn |> put_status(:not_found) |> json(%{error: "meeting_not_found"})
    end
  end

  defp join_after_guard(conn, user, meeting, params, guard) do
    warning =
      case guard do
        {:warn, :last_attempt} ->
          "Diqqat: bu majlisga oxirgi kirishingiz. Yana chiqib ketsangiz, qayta kira olmaysiz."

        _ ->
          nil
      end

    # E7 pre-join gate: классификация IP + запись GPS (нативный клиент).
    # MVP без MMDB: gate возвращает только :allow/:flag (никогда :block — см. Svc.Geo).
    # flag = пометка для ручной проверки, НЕ отказ → в звонок пускаем. Когда подключим
    # MaxMind MMDB (locus) и появится :block — компилятор потребует ветку отказа (D-012).
    case Geo.gate(user.org_id, remote_ip(conn), gate_opts(user, meeting, params)) do
      {:allow, _reason} -> issue_token(conn, user, meeting, warning)
      {:flag, _reason} -> issue_token(conn, user, meeting, warning)
    end
  end

  defp issue_token(conn, user, meeting, warning) do
    case LiveKit.join_token(user, meeting) do
      {:ok, token} ->
        Audit.log_action(user, :meeting_join,
          resource_type: :meeting,
          resource_id: meeting.id
        )

        json(conn, %{
          url: LiveKit.url(),
          token: token,
          room: meeting.livekit_room_name,
          warning: warning
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
