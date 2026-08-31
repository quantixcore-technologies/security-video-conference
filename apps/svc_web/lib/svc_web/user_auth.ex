defmodule SvcWeb.UserAuth do
  @moduledoc "Session-аутентификация + LiveView on_mount хуки (E0, D-006)."
  use SvcWeb, :verified_routes
  use Gettext, backend: SvcWeb.Gettext

  import Plug.Conn
  import Phoenix.Controller

  alias Svc.Accounts

  @doc "Логинит пользователя: обновляет сессию, кладёт user_id/org_id."
  def log_in_user(conn, user) do
    conn
    |> renew_session()
    |> put_session(:user_id, user.id)
    |> put_session(:org_id, user.org_id)
    |> put_session(:live_socket_id, "users_socket:#{user.id}")
    |> redirect(to: ~p"/admin")
  end

  @doc "Разлогинивает."
  def log_out_user(conn) do
    conn
    |> renew_session()
    |> redirect(to: ~p"/login")
  end

  @doc "Plug: грузит current_user из сессии."
  def fetch_current_user(conn, _opts) do
    user = current_user_from_session(get_session(conn, :user_id), get_session(conn, :org_id))
    assign(conn, :current_user, user)
  end

  @doc "Plug: требует залогиненного пользователя."
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, gettext("Требуется вход в систему."))
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  @salt "api_user"
  # Срок жизни bearer-токена нативного клиента (mobile/Tauri): 7 суток.
  @api_token_max_age 60 * 60 * 24 * 7

  @doc "Подписывает stateless bearer-токен для нативного клиента (mobile/Tauri)."
  def sign_api_token(user) do
    Phoenix.Token.sign(SvcWeb.Endpoint, @salt, %{user_id: user.id, org_id: user.org_id})
  end

  @totp_salt "api_totp_pending"
  # Промежуточный токен 2FA для нативного клиента живёт 5 минут (только шаг ввода кода).
  @totp_token_max_age 60 * 5

  @doc """
  Подписывает короткоживущий промежуточный токен 2FA (mobile/Tauri).
  Выдаётся после верного пароля, обменивается на bearer-токен после верного TOTP-кода.
  """
  def sign_totp_token(user) do
    Phoenix.Token.sign(SvcWeb.Endpoint, @totp_salt, %{user_id: user.id, org_id: user.org_id})
  end

  @doc "Проверяет промежуточный токен 2FA. {:ok, %{user_id, org_id}} | {:error, reason}."
  def verify_totp_token(token) do
    Phoenix.Token.verify(SvcWeb.Endpoint, @totp_salt, token, max_age: @totp_token_max_age)
  end

  @doc """
  Plug для JSON API: если сессия не дала current_user, пробуем `Authorization: Bearer <token>`.
  Нативный клиент (Kotlin/mobile) аутентифицируется bearer-токеном, а не cookie.
  """
  def fetch_api_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      assign(conn, :current_user, user_from_bearer(conn))
    end
  end

  defp user_from_bearer(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, %{user_id: uid, org_id: oid}} <-
           Phoenix.Token.verify(SvcWeb.Endpoint, @salt, token, max_age: @api_token_max_age) do
      current_user_from_session(uid, oid)
    else
      _ -> nil
    end
  end

  @doc "Plug для JSON API: 401 вместо редиректа, если не аутентифицирован."
  def require_authenticated_api(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "unauthorized"})
      |> halt()
    end
  end

  @doc "Plug: редирект уже залогиненных со страницы логина."
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn |> redirect(to: ~p"/admin") |> halt()
    else
      conn
    end
  end

  ## LiveView on_mount

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, gettext("Требуется вход в систему."))
        |> Phoenix.LiveView.redirect(to: ~p"/login")

      {:halt, socket}
    end
  end

  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  def on_mount(:mount_notifications, _params, _session, socket) do
    user = socket.assigns[:current_user]
    {:cont, Phoenix.Component.assign_new(socket, :unread_count, fn -> unread(user) end)}
  end

  defp unread(nil), do: 0
  defp unread(user), do: Svc.Notifications.unread_count(user.id)

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      current_user_from_session(session["user_id"], session["org_id"])
    end)
  end

  defp current_user_from_session(nil, _), do: nil
  defp current_user_from_session(_, nil), do: nil

  defp current_user_from_session(user_id, org_id) do
    Accounts.get_user!(org_id, user_id)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
