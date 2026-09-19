defmodule Svc.Documents.Recipient do
  @moduledoc """
  Получатель документа (S40). Отдельная таблица, а не массив id в документе:
  нужен факт «кто и когда открыл» (`opened_at`) и обычные FK-гарантии.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "document_recipients" do
    field :opened_at, :utc_datetime_usec

    belongs_to :organization, Svc.Orgs.Organization, foreign_key: :org_id
    belongs_to :document, Svc.Documents.Document
    belongs_to :user, Svc.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(%__MODULE__{} = recipient, attrs) do
    recipient
    |> cast(attrs, [:org_id, :document_id, :user_id, :opened_at])
    |> validate_required([:org_id, :document_id, :user_id])
    |> unique_constraint([:document_id, :user_id],
      name: :document_recipients_document_id_user_id_index,
      message: "уже является получателем"
    )
    |> foreign_key_constraint(:document_id)
    |> foreign_key_constraint(:user_id)
  end
end
