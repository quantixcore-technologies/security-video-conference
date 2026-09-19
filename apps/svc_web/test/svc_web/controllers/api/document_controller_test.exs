defmodule SvcWeb.API.DocumentControllerTest do
  @moduledoc """
  S41 — API документов для мобильных клиентов. Контракт (поля «от кого», «что
  делать», срок) ломать нельзя: на него опираются Android и iOS. Отдельно
  проверяем, что границы доступа те же, что и в вебе, — API мимо них не ходит.
  """
  use SvcWeb.ConnCase, async: true

  alias Svc.{Accounts, Documents, Orgs}

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Орг", slug: "doc-api"})
    {:ok, boss} = mk(org, "boss", :manager)
    {:ok, emp} = mk(org, "emp", :employee)
    {:ok, other} = mk(org, "other", :employee)
    %{org: org, boss: boss, emp: emp, other: other}
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

  defp upload(actor, recipients, attrs \\ %{}) do
    Documents.upload(
      actor,
      Map.merge(
        %{
          "title" => "Приказ №14",
          "filename" => "prikaz.pdf",
          "content_type" => "application/pdf",
          "action" => "signature",
          "note" => "Ознакомиться и подписать",
          "recipient_ids" => Enum.map(recipients, & &1.id)
        },
        attrs
      ),
      "тело приказа"
    )
  end

  test "401 без аутентификации", %{conn: conn} do
    assert json_response(get(conn, ~p"/api/documents"), 401)
  end

  test "список содержит отправителя, резолюцию и срок", %{conn: conn, boss: boss, emp: emp} do
    due = DateTime.add(DateTime.utc_now(), 3 * 86_400, :second)
    {:ok, _document} = upload(boss, [emp], %{"due_at" => due})

    body = conn |> login(emp) |> get(~p"/api/documents") |> json_response(200)

    assert [document] = body["documents"]
    assert document["title"] == "Приказ №14"
    assert document["from"]["full_name"] == "User boss"
    assert document["action"] == "signature"
    assert document["action_label"] == "На подпись"
    assert document["note"] == "Ознакомиться и подписать"
    assert document["due_at"]
    refute document["mine"]
    refute document["acknowledged_at"]
  end

  test "посторонний из той же организации не видит документ", ctx do
    %{conn: conn, boss: boss, emp: emp, other: other} = ctx
    {:ok, document} = upload(boss, [emp])

    assert %{"documents" => []} =
             conn |> login(other) |> get(~p"/api/documents") |> json_response(200)

    assert %{"error" => "document_not_found"} =
             conn |> login(other) |> get(~p"/api/documents/#{document.id}") |> json_response(404)
  end

  describe "скачивание" do
    test "получатель скачивает файл", %{conn: conn, boss: boss, emp: emp} do
      {:ok, document} = upload(boss, [emp])

      conn = conn |> login(emp) |> get(~p"/api/documents/#{document.id}/download")

      assert response(conn, 200) == "тело приказа"
      assert ["application/octet-stream; charset=utf-8"] = get_resp_header(conn, "content-type")
      assert ["nosniff"] = get_resp_header(conn, "x-content-type-options")
    end

    test "посторонний по прямой ссылке получает 404", ctx do
      %{conn: conn, boss: boss, emp: emp, other: other} = ctx
      {:ok, document} = upload(boss, [emp])

      conn = conn |> login(other) |> get(~p"/api/documents/#{document.id}/download")
      assert json_response(conn, 404)["error"] == "document_not_found"
    end
  end

  test "отметка «ознакомился» проставляется один раз", %{conn: conn, boss: boss, emp: emp} do
    {:ok, document} = upload(boss, [emp])

    assert %{"ok" => true, "changed" => true} =
             conn
             |> login(emp)
             |> post(~p"/api/documents/#{document.id}/ack")
             |> json_response(200)

    assert %{"changed" => false} =
             conn
             |> login(emp)
             |> post(~p"/api/documents/#{document.id}/ack")
             |> json_response(200)

    # Отправитель видит, что получатель ознакомился.
    body = conn |> login(boss) |> get(~p"/api/documents/#{document.id}") |> json_response(200)
    assert [recipient] = body["document"]["recipients"]
    assert recipient["acknowledged_at"]
  end

  test "получатель узнаёт о документе через уведомления", %{boss: boss, emp: emp} do
    {:ok, _document} = upload(boss, [emp])

    assert [notification] = Svc.Notifications.list_for_user(emp.id, limit: 5)
    assert notification.kind == :document
    assert notification.title =~ "На подпись"
    assert notification.body =~ "User boss"
  end
end
