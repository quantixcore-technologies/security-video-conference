defmodule Svc.AccountsTest do
  use Svc.DataCase, async: true

  alias Svc.{Accounts, Orgs}
  alias Svc.Accounts.User

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Ведомство", slug: "vedomstvo"})
    %{org: org}
  end

  defp user_attrs(org, attrs \\ %{}) do
    Enum.into(attrs, %{
      org_id: org.id,
      username: "ivanov",
      full_name: "Иванов Иван",
      password: "SecurePass123!",
      role: :employee
    })
  end

  describe "create_user/1" do
    test "создаёт пользователя и хеширует пароль (Argon2id)", %{org: org} do
      assert {:ok, %User{} = user} = Accounts.create_user(user_attrs(org))
      assert user.username == "ivanov"
      assert user.full_name == "Иванов Иван"
      assert user.role == :employee
      assert is_binary(user.hashed_password)
      assert String.starts_with?(user.hashed_password, "$argon2")
    end

    test "не хранит пароль в открытом виде", %{org: org} do
      {:ok, user} = Accounts.create_user(user_attrs(org))
      refute user.password
      refute user.hashed_password == "SecurePass123!"
    end

    test "нормализует username в lowercase", %{org: org} do
      {:ok, user} = Accounts.create_user(user_attrs(org, %{username: "Ivanov"}))
      assert user.username == "ivanov"
    end

    test "username уникален в рамках org", %{org: org} do
      {:ok, _} = Accounts.create_user(user_attrs(org))
      assert {:error, cs} = Accounts.create_user(user_attrs(org))
      assert errors_on(cs)[:username]
    end

    test "требует пароль не короче 12 символов", %{org: org} do
      assert {:error, cs} = Accounts.create_user(user_attrs(org, %{password: "short"}))
      assert errors_on(cs)[:password]
    end

    test "валидирует формат username", %{org: org} do
      assert {:error, cs} = Accounts.create_user(user_attrs(org, %{username: "Ivan Petrov!"}))
      assert errors_on(cs)[:username]
    end
  end

  describe "authenticate/3" do
    setup %{org: org} do
      {:ok, user} = Accounts.create_user(user_attrs(org))
      %{user: user}
    end

    test "успех с верным паролем + обновляет last_login_at", %{org: org} do
      assert {:ok, user} = Accounts.authenticate(org.id, "ivanov", "SecurePass123!")
      assert user.last_login_at
      assert user.failed_attempts == 0
    end

    test "ошибка с неверным паролем", %{org: org} do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate(org.id, "ivanov", "WrongPass1234")
    end

    test "ошибка для несуществующего юзера (постоянное время)", %{org: org} do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate(org.id, "nobody", "WhateverPass1")
    end

    test "блокировка после 5 неудачных попыток (даже с верным паролем)", %{org: org} do
      for _ <- 1..5, do: Accounts.authenticate(org.id, "ivanov", "WrongPass1234")
      assert {:error, :locked} = Accounts.authenticate(org.id, "ivanov", "SecurePass123!")
    end

    test "disabled пользователь не входит", %{org: org, user: user} do
      user |> Ecto.Changeset.change(status: :disabled) |> Repo.update!()
      assert {:error, :disabled} = Accounts.authenticate(org.id, "ivanov", "SecurePass123!")
    end

    test "org-изоляция: чужой org не аутентифицирует", %{user: _user} do
      {:ok, other} = Orgs.create_organization(%{name: "Другое", slug: "drugoe"})

      assert {:error, :invalid_credentials} =
               Accounts.authenticate(other.id, "ivanov", "SecurePass123!")
    end
  end

  describe "TOTP 2FA (D-006)" do
    setup %{org: org} do
      {:ok, user} = Accounts.create_user(user_attrs(org))
      %{user: user}
    end

    test "setup → confirm → verify полный цикл", %{user: user} do
      {user, secret, uri} = Accounts.setup_totp(user)
      assert is_binary(secret)
      assert uri =~ "otpauth://totp/"

      code = NimbleTOTP.verification_code(secret)
      assert {:ok, user} = Accounts.confirm_totp(user, code)
      assert user.totp_enabled

      assert :ok == Accounts.verify_totp(user, NimbleTOTP.verification_code(secret))
      assert {:error, :invalid_code} == Accounts.verify_totp(user, "000000")
    end

    test "confirm с неверным кодом не активирует", %{user: user} do
      {user, _secret, _uri} = Accounts.setup_totp(user)
      assert {:error, :invalid_code} = Accounts.confirm_totp(user, "000000")
    end

    test "verify_totp без включённой 2FA", %{user: user} do
      assert {:error, :totp_not_enabled} = Accounts.verify_totp(user, "123456")
    end

    test "totp_required? обязательна для админов/менеджеров, не для employee", %{user: user} do
      refute Accounts.totp_required?(user)
      assert Accounts.totp_required?(%User{role: :super_admin})
      assert Accounts.totp_required?(%User{role: :admin_hr})
      assert Accounts.totp_required?(%User{role: :manager})
      assert Accounts.totp_required?(%User{role: :security_officer})
    end
  end

  describe "управление сотрудником (P0)" do
    setup %{org: org} do
      {:ok, user} = Accounts.create_user(user_attrs(org))
      %{user: user}
    end

    test "update_user меняет роль/телефон", %{user: user} do
      assert {:ok, u} =
               Accounts.update_user(user, %{
                 "role" => "manager",
                 "phone" => "+998901112233",
                 "status" => "active"
               })

      assert u.role == :manager
      assert u.phone == "+998901112233"
    end

    test "update_user не трогает пароль и username", %{user: user} do
      hash = user.hashed_password

      {:ok, u} =
        Accounts.update_user(user, %{
          "full_name" => "Новое Имя",
          "role" => "employee",
          "status" => "active"
        })

      assert u.hashed_password == hash
      assert u.username == "ivanov"
    end

    test "set_status деактивирует и активирует", %{user: user} do
      assert {:ok, u} = Accounts.set_status(user, :disabled)
      assert u.status == :disabled
      assert {:ok, u} = Accounts.set_status(u, :active)
      assert u.status == :active
    end

    test "admin_reset_password меняет пароль (хеш и вход)", %{org: org, user: user} do
      old_hash = user.hashed_password
      assert {:ok, u} = Accounts.admin_reset_password(user, "BrandNewPass123")
      assert u.hashed_password != old_hash
      assert {:ok, _} = Accounts.authenticate(org.id, "ivanov", "BrandNewPass123")
    end

    test "admin_reset_password требует мин. 12 символов", %{user: user} do
      assert {:error, cs} = Accounts.admin_reset_password(user, "short")
      assert errors_on(cs)[:password]
    end

    test "update_password меняет при верном текущем", %{org: org, user: user} do
      assert {:ok, _} = Accounts.update_password(user, "SecurePass123!", "AnotherPass456")
      assert {:ok, _} = Accounts.authenticate(org.id, "ivanov", "AnotherPass456")
    end

    test "update_password отвергает неверный текущий пароль", %{user: user} do
      assert {:error, :invalid_current_password} =
               Accounts.update_password(user, "WrongCurrent1", "AnotherPass456")
    end
  end
end
