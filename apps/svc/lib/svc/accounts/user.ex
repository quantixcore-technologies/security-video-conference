defmodule Svc.Accounts.User do
  @moduledoc "Пользователь (сотрудник). Auth Argon2id + TOTP (D-006), RBAC-роль (D-007)."
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(super_admin admin_hr manager employee security_officer)a
  @statuses ~w(active disabled)a

  @type t :: %__MODULE__{}

  schema "users" do
    field :username, :string
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true

    # Профиль (ТЗ: Фото/ФИО/Номер)
    field :full_name, :string
    field :phone, :string
    field :photo_path, :string

    field :role, Ecto.Enum, values: @roles, default: :employee
    field :totp_secret, Svc.Encrypted.Binary, redact: true
    field :totp_enabled, :boolean, default: false
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :last_login_at, :utc_datetime_usec
    field :failed_attempts, :integer, default: 0
    field :locked_until, :utc_datetime_usec

    belongs_to :organization, Svc.Orgs.Organization, foreign_key: :org_id
    belongs_to :department, Svc.Orgs.Department, foreign_key: :department_id

    timestamps(type: :utc_datetime_usec)
  end

  def roles, do: @roles

  @doc "Создание пользователя админом (E0). Хеширует пароль Argon2id."
  def create_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :org_id, :department_id, :username, :full_name,
      :phone, :photo_path, :role, :status, :password
    ])
    |> validate_required([:org_id, :username, :full_name, :password])
    |> validate_length(:username, min: 3, max: 50)
    |> update_change(:username, &String.downcase/1)
    |> validate_format(:username, ~r/^[a-z0-9_.-]+$/, message: "строчные буквы, цифры, _ . -")
    |> validate_length(:full_name, min: 2, max: 200)
    |> validate_password()
    |> unique_constraint(:username, name: :users_org_id_username_index)
    |> foreign_key_constraint(:org_id)
    |> foreign_key_constraint(:department_id)
  end

  # Политика пароля (foundation overkill, D-014). Точные требования — у заказчика (комплаенс).
  defp validate_password(changeset) do
    changeset
    |> validate_length(:password, min: 12, max: 72)
    |> put_password_hash()
  end

  defp put_password_hash(%{valid?: true, changes: %{password: pass}} = cs) do
    cs
    |> put_change(:hashed_password, Argon2.hash_pwd_salt(pass))
    |> delete_change(:password)
  end

  defp put_password_hash(cs), do: cs
end
