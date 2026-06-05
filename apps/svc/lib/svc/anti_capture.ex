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
end
