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
      {:ok, %{totp_enabled: true} = user} ->
        # Пароль верный, но включена 2FA: выдаём промежуточный токен (5 мин),
        # клиент обменивает его на bearer после ввода TOTP-кода (POST /api/login/totp).
        json(conn, %{totp_required: true, totp_token: UserAuth.sign_totp_token(user)})

      {:ok, user} ->
        Audit.log(:login_success, org_id: user.org_id, actor_id: user.id, ip: remote_ip(conn))
        json(conn, token_payload(user))

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

  @doc """
  Второй шаг 2FA для нативного клиента: обмен промежуточного totp_token + TOTP-кода
  на постоянный bearer-токен.
  """
  def verify_totp(conn, %{"totp_token" => totp_token, "code" => code}) do
    with {:ok, %{user_id: uid, org_id: oid}} <- UserAuth.verify_totp_token(totp_token),
         user <- Accounts.get_user!(oid, uid),
         :ok <- Accounts.verify_totp(user, code) do
      Audit.log(:login_success, org_id: user.org_id, actor_id: user.id, ip: remote_ip(conn))
      json(conn, token_payload(user))
    else
      {:error, reason} when reason in [:invalid_code, :totp_not_enabled] ->
        conn |> put_status(:unauthorized) |> json(%{error: to_string(reason)})

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "totp_token_invalid"})
    end
  end

  def verify_totp(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "totp_token_and_code_required"})
  end

  defp token_payload(user) do
    %{
      token: UserAuth.sign_api_token(user),
      user: %{
        id: user.id,
        username: user.username,
        full_name: user.full_name,
        role: user.role
      }
    }
  end

  defp remote_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
