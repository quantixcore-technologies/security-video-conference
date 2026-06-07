defmodule SvcWeb.PageController do
  use SvcWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/admin")
  end
end
