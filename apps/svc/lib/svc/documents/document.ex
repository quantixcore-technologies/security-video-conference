defmodule Svc.Documents.Document do
  @moduledoc """
  Документ для обмена (S40): метаданные + ссылка на зашифрованный блоб.

  Доступ = `org_id` (D-005) + явный список получателей (`Svc.Documents.Recipient`).
  Срок действия (`expires_at`) и отзыв (`revoked_at`) снимают доступ у получателей,
  но НЕ удаляют запись: журнал обмена должен оставаться полным (D-014).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "documents" do
    field :title, :string
    field :filename, :string
    field :content_type, :string
    field :byte_size, :integer
    field :sha256, :string
    field :storage_key, :string

    field :version, :integer, default: 1
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    belongs_to :organization, Svc.Orgs.Organization, foreign_key: :org_id
    belongs_to :owner, Svc.Accounts.User, foreign_key: :owner_id
    belongs_to :revoked_by, Svc.Accounts.User, foreign_key: :revoked_by_id
    belongs_to :parent, __MODULE__, foreign_key: :parent_id

    has_many :recipients, Svc.Documents.Recipient

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Создание документа (все поля кроме получателей — их пишет контекст)."
  def create_changeset(%__MODULE__{} = document, attrs) do
    document
    |> cast(attrs, [
      :org_id,
      :owner_id,
      :title,
      :filename,
      :content_type,
      :byte_size,
      :sha256,
      :storage_key,
      :version,
      :parent_id,
      :expires_at
    ])
    |> validate_required([
      :org_id,
      :owner_id,
      :title,
      :filename,
      :byte_size,
      :sha256,
      :storage_key
    ])
    |> validate_length(:title, min: 2, max: 300)
    |> validate_length(:filename, min: 1, max: 300)
    |> validate_number(:byte_size, greater_than: 0)
    |> validate_expiry()
    |> unique_constraint(:storage_key)
    |> foreign_key_constraint(:org_id)
    |> foreign_key_constraint(:owner_id)
  end

  @doc "Отзыв: закрывает доступ получателям, файл и запись остаются (D-014)."
  def revoke_changeset(%__MODULE__{} = document, %{} = attrs) do
    document
    |> cast(attrs, [:revoked_by_id])
    |> put_change(:revoked_at, DateTime.utc_now())
    |> foreign_key_constraint(:revoked_by_id)
  end

  @doc "Активен ли документ сейчас: не отозван и срок не истёк."
  def active?(%__MODULE__{revoked_at: nil, expires_at: nil}), do: true
  def active?(%__MODULE__{revoked_at: %DateTime{}}), do: false

  def active?(%__MODULE__{expires_at: %DateTime{} = expires}),
    do: DateTime.compare(expires, DateTime.utc_now()) == :gt

  # Срок в прошлом — почти всегда опечатка в форме, а не намерение закрыть
  # доступ сразу же: для этого есть отзыв.
  defp validate_expiry(changeset) do
    case get_change(changeset, :expires_at) do
      nil ->
        changeset

      %DateTime{} = expires ->
        if DateTime.compare(expires, DateTime.utc_now()) == :gt,
          do: changeset,
          else: add_error(changeset, :expires_at, "должен быть в будущем")
    end
  end
end
