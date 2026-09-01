defmodule SvcWeb.SessionController do
  use SvcWeb, :controller

  alias Svc.{Accounts, Audit, Orgs}
  alias SvcWeb.UserAuth

  def new(conn, _params) do
    render(conn, :new, error_message: nil)
  end

  def create(conn, %{"user" => %{"username" => username, "password" => password}}) do
    org = Orgs.default_organization()

    case org && Accounts.authenticate(org.id, username, password) do
      {:ok, user} ->
        Audit.log(:login_success, org_id: user.org_id, actor_id: user.id, ip: remote_ip(conn))

        if user.totp_enabled do
          conn
          |> put_session(:pending_user_id, user.id)
          |> put_session(:pending_org_id, user.org_id)
          |> redirect(to: ~p"/login/totp")
        else
          UserAuth.log_in_user(conn, user)
        end

      {:error, reason} ->
        Audit.log(:login_failure,
          org_id: org && org.id,
          metadata: %{username: username, reason: reason},
          ip: remote_ip(conn)
        )

        render(conn, :new, error_message: error_text(reason))

      nil ->
        render(conn, :new, error_message: gettext("Система не инициализирована."))
    end
  end

  def totp_form(conn, _params) do
    if get_session(conn, :pending_user_id) do
      render(conn, :totp, error_message: nil)
    else
      redirect(conn, to: ~p"/login")
    end
  end

  def totp_verify(conn, %{"totp" => %{"code" => code}}) do
    uid = get_session(conn, :pending_user_id)
    oid = get_session(conn, :pending_org_id)

    with uid when is_integer(uid) <- uid,
         user <- Accounts.get_user!(oid, uid),
         :ok <- Accounts.verify_totp(user, code) do
      conn
      |> delete_session(:pending_user_id)
      |> delete_session(:pending_org_id)
      |> UserAuth.log_in_user(user)
    else
      _ -> render(conn, :totp, error_message: gettext("Неверный код 2FA."))
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, gettext("Вы вышли из системы."))
    |> UserAuth.log_out_user()
  end

  defp remote_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()

  defp error_text(:locked),
    do: gettext("Аккаунт временно заблокирован (превышены попытки входа).")

  defp error_text(:disabled), do: gettext("Аккаунт отключён.")
  defp error_text(_), do: gettext("Неверный логин или пароль.")
end
