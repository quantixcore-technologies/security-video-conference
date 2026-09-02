defmodule SvcWeb.API.ProfileController do
  @moduledoc "JSON API нативных клиентов: профиль и коллеги по отделу."
  use SvcWeb, :controller

  alias Svc.{Accounts, Repo}

  def me(conn, _params) do
    user = Repo.preload(conn.assigns.current_user, [:department, :organization])

    json(conn, %{
      user: %{
        id: user.id,
        username: user.username,
        full_name: user.full_name,
        role: user.role,
        phone: user.phone,
        status: user.status,
        department: assoc_json(user.department),
        organization: assoc_json(user.organization)
      }
    })
  end

  @doc false
  # Коллеги: свой отдел; без отдела — все сотрудники организации.
  def colleagues(conn, _params) do
    user = conn.assigns.current_user

    users =
      user.org_id
      |> Accounts.list_users()
      |> Enum.filter(fn u ->
        is_nil(user.department_id) or u.department_id == user.department_id
      end)
      |> Enum.map(fn u ->
        %{
          id: u.id,
          username: u.username,
          full_name: u.full_name,
          role: u.role,
          phone: u.phone,
          status: u.status
        }
      end)

    json(conn, %{users: users})
  end

  defp assoc_json(nil), do: nil
  defp assoc_json(%{id: id, name: name}), do: %{id: id, name: name}
end
