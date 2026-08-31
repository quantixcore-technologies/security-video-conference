defmodule Svc.AntiCapture do
  @moduledoc """
  Анти-захват (E5). Журнал событий захвата контента — append-only, scoped по org_id (D-005).

  ⚠️ Честная рамка (D-013): web-слой не блокирует захват (это невозможно в браузере),
  а трассирует (watermark) + журналирует детекты, присылаемые нативным клиентом (Tauri/mobile).
  Enforce скриншота/записи — только Win (setContentProtected) / Android (FLAG_SECURE).
  """
  import Ecto.Query
  alias Svc.Repo
  alias Svc.AntiCapture.CaptureEvent

  @doc "Регистрирует событие захвата (от нативного клиента или server-side детекта)."
  def log_event(attrs) do
    attrs = Map.put_new(attrs, :occurred_at, DateTime.utc_now())

    %CaptureEvent{}
    |> CaptureEvent.changeset(attrs)
    |> Repo.insert()
  end

  @doc "События захвата организации (свежие сверху)."
  def list_events(org_id, opts \\ []) do
    limit = opts[:limit] || 50

    Repo.all(
      from e in CaptureEvent,
        where: e.org_id == ^org_id,
        order_by: [desc: e.occurred_at, desc: e.id],
        limit: ^limit
    )
  end

  @doc "События захвата по конкретной встрече."
  def list_for_meeting(meeting_id) do
    Repo.all(
      from e in CaptureEvent,
        where: e.meeting_id == ^meeting_id,
        order_by: [desc: e.occurred_at, desc: e.id]
    )
  end

  @doc "Число критических событий захвата по организации."
  def critical_count(org_id) do
    Repo.aggregate(
      from(e in CaptureEvent, where: e.org_id == ^org_id and e.severity == :critical),
      :count
    )
  end

  @doc """
  E5-C: применяет пер-встречную анти-захват политику к событию.
  Читает `capture_reaction` встречи:
    :none → ничего · :warn → уведомление организатору + audit · :eject → удаление из LiveKit + audit.
  Возвращает применённую реакцию (:none | :warn | :eject).
  """
  def enforce_policy(%CaptureEvent{meeting_id: nil}), do: :none

  def enforce_policy(%CaptureEvent{} = event) do
    meeting = Svc.Meetings.get_meeting!(event.org_id, event.meeting_id)
    apply_reaction(meeting.capture_reaction, meeting, event)
  rescue
    Ecto.NoResultsError -> :none
  end

  defp apply_reaction(:none, _meeting, _event), do: :none

  defp apply_reaction(reaction, meeting, event) do
    Svc.Audit.log(:capture_reaction,
      org_id: event.org_id,
      actor_id: event.user_id,
      resource_type: :meeting,
      resource_id: meeting.id,
      metadata: %{"kind" => to_string(event.kind), "reaction" => to_string(reaction)}
    )

    do_reaction(reaction, meeting, event)
    reaction
  end

  defp do_reaction(:warn, meeting, event) do
    if meeting.organizer_id do
      organizer = Svc.Accounts.get_user!(meeting.org_id, meeting.organizer_id)

      Svc.Notifications.notify(
        organizer,
        :update,
        "Обнаружен захват экрана",
        body: "Встреча «#{meeting.title}»: #{event.kind}. Реакция: предупреждение.",
        meeting_id: meeting.id
      )
    end

    :ok
  end

  defp do_reaction(:eject, meeting, event) do
    Svc.LiveKit.remove_participant(meeting.livekit_room_name, "user-#{event.user_id}")
    :ok
  end
end
