defmodule Svc.Recordings do
  @moduledoc """
  Контекст серверной записи встреч (E2, D-009). Запись опциональна по политике встречи;
  по умолчанию выключена. Шифрование at-rest (D-010), доступ по RBAC + аудит.

  Реальный запуск LiveKit Egress — TODO (требует LiveKit running). Здесь — управление
  жизненным циклом записи; egress_id/storage_path приходят из вебхуков egress_*.
  """
  import Ecto.Query
  alias Svc.Repo
  alias Svc.Recordings.Recording
  alias Svc.Meetings.Meeting
  alias Svc.Accounts.User

  @doc "Разрешена ли запись политикой встречи (D-009)."
  def recording_enabled?(%Meeting{recording_policy: policy}), do: policy in [:optional, :required]

  @doc """
  Начинает запись, если политика разрешает. Фиксирует намерение (status: :starting).
  Возвращает {:ok, recording} | {:error, :recording_disabled}.
  """
  def start_recording(%Meeting{} = meeting, %User{} = requester) do
    if recording_enabled?(meeting) do
      %Recording{}
      |> Recording.changeset(%{
        org_id: meeting.org_id,
        meeting_id: meeting.id,
        requested_by: requester.id,
        status: :starting,
        encrypted: true,
        started_at: DateTime.utc_now()
      })
      |> Repo.insert()
    else
      {:error, :recording_disabled}
    end
  end

  @doc "Egress запущен (webhook egress_started): фиксируем egress_id."
  def mark_active(%Recording{} = rec, egress_id) do
    rec |> Recording.changeset(%{egress_id: egress_id, status: :active}) |> Repo.update()
  end

  @doc "Egress завершён (webhook egress_ended): путь к файлу + статус."
  def mark_completed(%Recording{} = rec, storage_path) do
    rec
    |> Recording.changeset(%{
      status: :completed,
      storage_path: storage_path,
      ended_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  def list_recordings(meeting_id) do
    Repo.all(
      from r in Recording, where: r.meeting_id == ^meeting_id, order_by: [desc: r.inserted_at]
    )
  end

  @doc "Доступ к записи — только org-wide роли той же организации (RBAC, D-007). Аудит — у вызывающего."
  def can_access?(%User{} = user, %Recording{org_id: org_id}) do
    user.org_id == org_id and user.role in [:super_admin, :admin_hr, :security_officer]
  end
end
