defmodule SvcWeb.API.SessionController do
  @moduledoc """
  JSON API логина для нативного клиента (mobile/Tauri, E1).
  Возвращает stateless bearer-токен (Phoenix.Token) вместо session-cookie.
  """
  use SvcWeb, :controller

  alias Svc.{Accounts, Audit, Orgs}
  alias SvcWeb.UserAuth

  def create(conn, %{"username" => username, "password" => password}) do
    org = Orgs.default_organization()

    case org && Accounts.authenticate(org.id, username, password) do
      {:ok, user} ->
        cond do
          user.totp_enabled ->
            # 2FA через API пока не реализована (PoC) — D-006.
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "totp_required"})

          true ->
            Audit.log(:login_success, org_id: user.org_id, actor_id: user.id, ip: remote_ip(conn))

            json(conn, %{
              token: UserAuth.sign_api_token(user),
              user: %{
                id: user.id,
                username: user.username,
                full_name: user.full_name,
                role: user.role
              }
            })
        end

      {:error, reason} ->
        Audit.log(:login_failure,
          org_id: org && org.id,
          metadata: %{username: username, reason: reason},
          ip: remote_ip(conn)
        )

        conn |> put_status(:unauthorized) |> json(%{error: to_string(reason)})

      nil ->
        conn |> put_status(:service_unavailable) |> json(%{error: "not_initialized"})
    end
  end

  def create(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "username_password_required"})
  end

  defp remote_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
