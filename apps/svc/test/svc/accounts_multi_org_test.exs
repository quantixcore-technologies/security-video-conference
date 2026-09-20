defmodule Svc.AccountsMultiOrgTest do
  @moduledoc """
  Вход при нескольких организациях на одном сервере (S42).

  Раньше логин шёл только в `Orgs.default_organization/0` — вторая организация
  войти не могла вообще. Здесь проверяем, что вход находит СВОЮ организацию и
  что тёзки из разных организаций не мешают друг другу.
  """
  use Svc.DataCase, async: true

  alias Svc.{Accounts, Orgs}

  setup do
    {:ok, org_a} = Orgs.create_organization(%{name: "Идора A", slug: "org-a"})
    {:ok, org_b} = Orgs.create_organization(%{name: "Идора B", slug: "org-b"})
    %{org_a: org_a, org_b: org_b}
  end

  defp mk(org, username, password, role \\ :manager) do
    Accounts.create_user(%{
      org_id: org.id,
      username: username,
      full_name: "User #{username} #{org.slug}",
      password: password,
      role: role
    })
  end

  test "пользователь второй организации может войти", %{org_b: org_b} do
    {:ok, user} = mk(org_b, "rais", "SecurePass123!")

    assert {:ok, logged} = Accounts.authenticate("rais", "SecurePass123!")
    assert logged.id == user.id
    assert logged.org_id == org_b.id
  end

  test "тёзки в разных организациях попадают каждый к себе", ctx do
    %{org_a: org_a, org_b: org_b} = ctx
    {:ok, a} = mk(org_a, "admin", "PasswordOrgA1!")
    {:ok, b} = mk(org_b, "admin", "PasswordOrgB2!")

    assert {:ok, first} = Accounts.authenticate("admin", "PasswordOrgA1!")
    assert first.id == a.id and first.org_id == org_a.id

    assert {:ok, second} = Accounts.authenticate("admin", "PasswordOrgB2!")
    assert second.id == b.id and second.org_id == org_b.id
  end

  test "неверный пароль и несуществующий логин дают одинаковый ответ", %{org_a: org_a} do
    {:ok, _} = mk(org_a, "boss", "SecurePass123!")

    assert {:error, :invalid_credentials} = Accounts.authenticate("boss", "WrongPassword1!")
    assert {:error, :invalid_credentials} = Accounts.authenticate("net-takogo", "WrongPassword1!")
  end

  test "отключённый сотрудник не входит", %{org_a: org_a} do
    {:ok, user} = mk(org_a, "uvolen", "SecurePass123!")
    {:ok, _} = Accounts.set_status(user, :disabled)

    assert {:error, :disabled} = Accounts.authenticate("uvolen", "SecurePass123!")
  end

  test "регистр логина не важен", %{org_a: org_a} do
    {:ok, _} = mk(org_a, "rahbar", "SecurePass123!")
    assert {:ok, _} = Accounts.authenticate("RAHBAR", "SecurePass123!")
  end

  test "блокировка после 5 неудач работает и в мультиорг-режиме", %{org_a: org_a} do
    {:ok, _} = mk(org_a, "target", "SecurePass123!")

    for _ <- 1..5 do
      assert {:error, :invalid_credentials} = Accounts.authenticate("target", "Wrong1234567!")
    end

    # Даже с верным паролем — пока блокировка не истечёт.
    assert {:error, :locked} = Accounts.authenticate("target", "SecurePass123!")
  end
end
