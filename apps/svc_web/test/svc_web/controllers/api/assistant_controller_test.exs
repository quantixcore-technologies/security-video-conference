defmodule SvcWeb.API.AssistantControllerTest do
  @moduledoc """
  S37: HTTP-контракт помощника. На него опираются веб-панель, Android и Tauri,
  поэтому форма ответа (`status` + соответствующее поле) зафиксирована тестом.
  """
  use SvcWeb.ConnCase, async: true

  alias Svc.{Accounts, Orgs}

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Ведомство", slug: "ved-assist"})
    {:ok, admin} = mk(org, "boss", :super_admin)
    {:ok, worker} = mk(org, "worker", :employee)
    %{org: org, admin: admin, worker: worker}
  end

  defp mk(org, username, role) do
    Accounts.create_user(%{
      org_id: org.id,
      username: username,
      full_name: "User #{username}",
      password: "SecurePass123!",
      role: role
    })
  end

  defp login(conn, user), do: init_test_session(conn, %{user_id: user.id, org_id: user.org_id})

  test "ask → ok с ответом и языком запроса", %{conn: conn, worker: worker} do
    body =
      conn
      |> login(worker)
      |> post(~p"/api/assistant/ask", %{
        "question" => "как подключиться к звонку",
        "locale" => "ru"
      })
      |> json_response(200)

    assert body["status"] == "ok"
    assert body["locale"] == "ru"
    assert body["answer"]["id"] == "join_call"
    assert body["answer"]["answer"] =~ "Откройте карточку совещания"
    assert is_list(body["related"])
  end

  test "локаль из параметра меняет язык ответа", %{conn: conn, worker: worker} do
    for {locale, fragment} <- [{"uz", "Majlis kartochkasini"}, {"en", "Open the meeting card"}] do
      body =
        conn
        |> login(worker)
        |> post(~p"/api/assistant/ask", %{"question" => "join call", "locale" => locale})
        |> json_response(200)

      assert body["answer"]["answer"] =~ fragment
    end
  end

  test "неподдерживаемая локаль откатывается к дефолтной", %{conn: conn, worker: worker} do
    body =
      conn
      |> login(worker)
      |> post(~p"/api/assistant/ask", %{"question" => "join call", "locale" => "de"})
      |> json_response(200)

    assert body["locale"] == SvcWeb.Locale.default()
  end

  test "restricted: сотруднику объясняют, чья это роль", %{conn: conn, worker: worker} do
    body =
      conn
      |> login(worker)
      |> post(~p"/api/assistant/ask", %{"question" => "yangi xodim qo'shish", "locale" => "uz"})
      |> json_response(200)

    assert body["status"] == "restricted"

    # Клиент из этого списка строит фразу «обратитесь к ...».
    assert "super_admin" in body["allowed_roles"]
    assert is_binary(body["question"])

    # Подписи — на языке запроса, а не сырые атомы: их показывают все три клиента.
    assert "Superadmin" in body["allowed_role_labels"]
    refute Enum.any?(body["allowed_role_labels"], &String.contains?(&1, "_"))
  end

  test "restricted: подписи ролей следуют локали запроса", %{conn: conn, worker: worker} do
    body =
      conn
      |> login(worker)
      |> post(~p"/api/assistant/ask", %{"question" => "yangi xodim qo'shish", "locale" => "ru"})
      |> json_response(200)

    assert "Суперадмин" in body["allowed_role_labels"]
  end

  test "тот же вопрос от админа → полный ответ", %{conn: conn, admin: admin} do
    body =
      conn
      |> login(admin)
      |> post(~p"/api/assistant/ask", %{"question" => "yangi xodim qo'shish", "locale" => "uz"})
      |> json_response(200)

    assert body["status"] == "ok"
    assert body["answer"]["id"] == "manage_users"
  end

  test "вопрос не по теме → no_match с подсказками, а не выдуманный ответ", %{
    conn: conn,
    worker: worker
  } do
    body =
      conn
      |> login(worker)
      |> post(~p"/api/assistant/ask", %{"question" => "погода в Ташкенте завтра"})
      |> json_response(200)

    assert body["status"] == "no_match"
    assert body["suggestions"] != []
  end

  test "пустой вопрос не роняет запрос", %{conn: conn, worker: worker} do
    body = conn |> login(worker) |> post(~p"/api/assistant/ask", %{}) |> json_response(200)
    assert body["status"] == "no_match"
  end

  test "suggestions отфильтрованы по роли", %{conn: conn, worker: worker} do
    body =
      conn
      |> login(worker)
      |> get(~p"/api/assistant/suggestions?locale=uz")
      |> json_response(200)

    assert body["suggestions"] != []
    refute Enum.any?(body["suggestions"], &(&1["id"] == "manage_users"))
  end

  test "show по id уважает роль", %{conn: conn, admin: admin, worker: worker} do
    assert conn
           |> login(admin)
           |> get(~p"/api/assistant/manage_users")
           |> json_response(200)
           |> get_in(["answer", "id"]) == "manage_users"

    assert conn
           |> login(worker)
           |> get(~p"/api/assistant/manage_users")
           |> json_response(404)
  end

  test "401 без аутентификации", %{conn: conn} do
    assert conn
           |> post(~p"/api/assistant/ask", %{"question" => "test"})
           |> json_response(401)
  end
end
