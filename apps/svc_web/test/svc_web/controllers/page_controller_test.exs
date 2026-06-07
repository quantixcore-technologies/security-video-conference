defmodule SvcWeb.PageControllerTest do
  use SvcWeb.ConnCase

  test "GET / редиректит в админку (оттуда — на логин, если не залогинен)", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/admin"
  end
end
