defmodule SvcWeb.DocumentLiveTest do
  @moduledoc """
  S40 — веб-слой обмена документами. Проверяем то, что видит и может нажать
  пользователь: доступ к странице, отзыв, и главное — скачивание чужого
  документа через прямую ссылку (границу легко обойти, если её нет в контроллере).
  """
  use SvcWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Svc.{Accounts, Documents, Orgs}

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Орг", slug: "doc-web"})
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

  defp upload(actor, recipients) do
    Documents.upload(
      actor,
      %{
        "title" => "Протокол №14",
        "filename" => "protokol.pdf",
        "content_type" => "application/pdf",
        "recipient_ids" => Enum.map(recipients, & &1.id)
      },
      "тело документа"
    )
  end

  test "неаутентифицированный → /login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/admin/documents")
  end

  test "получатель видит документ в списке", %{conn: conn, boss: boss, emp: emp} do
    {:ok, _document} = upload(boss, [emp])

    {:ok, _lv, html} = conn |> login(emp) |> live(~p"/admin/documents")
    assert html =~ "Протокол №14"
  end

  test "посторонний из той же организации документа не видит", ctx do
    %{conn: conn, boss: boss, emp: emp, other: other} = ctx
    {:ok, _document} = upload(boss, [emp])

    {:ok, _lv, html} = conn |> login(other) |> live(~p"/admin/documents")
    refute html =~ "Протокол №14"
  end

  test "форма отправки видна руководителю и скрыта от сотрудника", ctx do
    %{conn: conn, boss: boss, emp: emp} = ctx

    {:ok, _lv, boss_html} = conn |> login(boss) |> live(~p"/admin/documents")
    assert boss_html =~ "Отправить документ"

    {:ok, _lv, emp_html} = conn |> login(emp) |> live(~p"/admin/documents")
    refute emp_html =~ "Отправить документ"
  end

  test "автор отзывает документ из списка", %{conn: conn, boss: boss, emp: emp} do
    {:ok, document} = upload(boss, [emp])

    {:ok, lv, _html} = conn |> login(boss) |> live(~p"/admin/documents")
    lv |> element("button[phx-value-id='#{document.id}']") |> render_click()

    assert {:ok, revoked} = Documents.fetch(boss, document.id)
    assert revoked.revoked_at
    assert Documents.list_visible(emp) == []
  end

  describe "скачивание" do
    test "получатель скачивает файл", %{conn: conn, boss: boss, emp: emp} do
      {:ok, document} = upload(boss, [emp])

      conn = conn |> login(emp) |> get(~p"/admin/documents/#{document.id}/download")

      assert response(conn, 200) == "тело документа"

      assert ["attachment; filename=\"protokol.pdf\""] =
               get_resp_header(conn, "content-disposition")

      assert ["no-store, private"] = get_resp_header(conn, "cache-control")
    end

    test "посторонний по прямой ссылке НЕ скачает", ctx do
      %{conn: conn, boss: boss, emp: emp, other: other} = ctx
      {:ok, document} = upload(boss, [emp])

      conn = conn |> login(other) |> get(~p"/admin/documents/#{document.id}/download")

      assert redirected_to(conn) == ~p"/admin/documents"
      refute conn.resp_body =~ "тело документа"
    end

    test "после отзыва получатель скачать не может", ctx do
      %{conn: conn, boss: boss, emp: emp} = ctx
      {:ok, document} = upload(boss, [emp])
      {:ok, _} = Documents.revoke(boss, document.id)

      conn = conn |> login(emp) |> get(~p"/admin/documents/#{document.id}/download")
      assert redirected_to(conn) == ~p"/admin/documents"
    end
  end
end
