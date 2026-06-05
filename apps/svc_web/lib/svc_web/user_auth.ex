defmodule SvcWeb.UserAuth do
  @moduledoc "Session-аутентификация + LiveView on_mount хуки (E0, D-006)."
  use SvcWeb, :verified_routes

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
      |> put_flash(:error, "Требуется вход в систему.")
      |> redirect(to: ~p"/login")
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
        |> Phoenix.LiveView.put_flash(:error, "Требуется вход в систему.")
        |> Phoenix.LiveView.redirect(to: ~p"/login")

      {:halt, socket}
    end
  end

  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

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
