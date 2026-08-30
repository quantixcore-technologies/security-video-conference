defmodule Svc.Accounts do
  @moduledoc """
  Контекст пользователей и аутентификации (E0).
  Пароль Argon2id + TOTP 2FA (D-006). Всё scoped по org_id (D-005).
  """
  import Ecto.Query
  alias Svc.Repo
  alias Svc.Accounts.User

  @max_failed 5
  @lock_minutes 15

  ## CRUD

  def create_user(attrs) do
    %User{} |> User.create_changeset(attrs) |> Repo.insert()
  end

  @doc "Changeset для формы создания пользователя (LiveView)."
  def change_user_creation(attrs \\ %{}) do
    User.create_changeset(%User{}, attrs)
  end

  def get_user!(org_id, id), do: Repo.get_by!(User, id: id, org_id: org_id)

  def get_user_by_username(org_id, username) when is_binary(username) do
    Repo.get_by(User, org_id: org_id, username: String.downcase(username))
  end

  def list_users(org_id) do
    Repo.all(from u in User, where: u.org_id == ^org_id, order_by: u.full_name)
  end

  @doc "Changeset для формы смены пароля (LiveView)."
  def change_password(attrs \\ %{}), do: User.password_changeset(%User{}, attrs)

  @doc "Changeset для формы редактирования сотрудника (LiveView)."
  def change_user(%User{} = user, attrs \\ %{}), do: User.update_changeset(user, attrs)

  @doc "Редактирование сотрудника админом (роль/отдел/телефон/фото/статус)."
  def update_user(%User{} = user, attrs) do
    user |> User.update_changeset(attrs) |> Repo.update()
  end

  @doc "Деактивация/активация сотрудника (status)."
  def set_status(%User{} = user, status) when status in [:active, :disabled] do
    user |> Ecto.Changeset.change(status: status) |> Repo.update()
  end

  @doc "Сброс пароля сотрудника админом (без проверки старого)."
  def admin_reset_password(%User{} = user, new_password) do
    user |> User.password_changeset(%{password: new_password}) |> Repo.update()
  end

  @doc """
  Смена пароля в профиле: проверяет текущий пароль, обновляет на новый.
  Возвращает {:ok, user} | {:error, :invalid_current_password | changeset}.
  """
  def update_password(%User{} = user, current_password, new_password) do
    if Argon2.verify_pass(current_password, user.hashed_password) do
      user |> User.password_changeset(%{password: new_password}) |> Repo.update()
    else
      {:error, :invalid_current_password}
    end
  end

  ## Аутентификация (D-006)

  @doc """
  Проверка пароля. Постоянное время (no_user_verify при отсутствии юзера).
  2FA (если включена) проверяется отдельно — verify_totp/2.
  Возвращает {:ok, user} | {:error, :invalid_credentials | :locked | :disabled}.
  """
  def authenticate(org_id, username, password) do
    user = get_user_by_username(org_id, username)

    cond do
      is_nil(user) ->
        Argon2.no_user_verify()
        {:error, :invalid_credentials}

      locked?(user) ->
        {:error, :locked}

      user.status == :disabled ->
        {:error, :disabled}

      Argon2.verify_pass(password, user.hashed_password) ->
        {:ok, reset_failed(user)}

      true ->
        register_failed(user)
        {:error, :invalid_credentials}
    end
  end

  def locked?(%User{locked_until: nil}), do: false
  def locked?(%User{locked_until: until}), do: DateTime.compare(until, DateTime.utc_now()) == :gt

  defp reset_failed(user) do
    {:ok, u} =
      user
      |> Ecto.Changeset.change(
        failed_attempts: 0,
        locked_until: nil,
        last_login_at: DateTime.utc_now()
      )
      |> Repo.update()

    u
  end

  defp register_failed(user) do
    attempts = user.failed_attempts + 1

    changes =
      if attempts >= @max_failed do
        [
          failed_attempts: attempts,
          locked_until: DateTime.add(DateTime.utc_now(), @lock_minutes * 60, :second)
        ]
      else
        [failed_attempts: attempts]
      end

    user |> Ecto.Changeset.change(changes) |> Repo.update()
  end

  ## TOTP 2FA (D-006) — TODO: app-level шифрование totp_secret (Cloak) в слое хардненинга

  @doc "Генерирует TOTP-секрет, сохраняет, возвращает {user, secret, otpauth_uri} для QR."
  def setup_totp(%User{} = user, issuer \\ "SVC") do
    secret = NimbleTOTP.secret()
    uri = NimbleTOTP.otpauth_uri("#{issuer}:#{user.username}", secret, issuer: issuer)
    {:ok, user} = user |> Ecto.Changeset.change(totp_secret: secret) |> Repo.update()
    {user, secret, uri}
  end

  @doc "Подтверждает TOTP-код и активирует 2FA."
  def confirm_totp(%User{totp_secret: secret} = user, code)
      when is_binary(secret) and is_binary(code) do
    if NimbleTOTP.valid?(secret, code) do
      user |> Ecto.Changeset.change(totp_enabled: true) |> Repo.update()
    else
      {:error, :invalid_code}
    end
  end

  @doc "Отключение 2FA (сброс секрета и флага)."
  def disable_totp(%User{} = user) do
    user |> Ecto.Changeset.change(totp_enabled: false, totp_secret: nil) |> Repo.update()
  end

  @doc "Проверяет TOTP-код при входе."
  def verify_totp(%User{totp_secret: secret, totp_enabled: true}, code)
      when is_binary(secret) and is_binary(code) do
    if NimbleTOTP.valid?(secret, code), do: :ok, else: {:error, :invalid_code}
  end

  def verify_totp(%User{}, _code), do: {:error, :totp_not_enabled}

  @doc "Обязательна ли 2FA для роли (D-006): админы/менеджеры/security_officer — да."
  def totp_required?(%User{role: role}),
    do: role in [:super_admin, :admin_hr, :manager, :security_officer]
end
