defmodule SvcWeb.AssistantWidgetTest do
  @moduledoc """
  S37: помощник живёт в общем лейауте, значит присутствует на всех страницах
  админки. Тест закрепляет именно это — виджет легко потерять при правке
  лейаута, и пропажа никак иначе не проявится.
  """
  use SvcWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Svc.{Accounts, Orgs}

  setup do
    {:ok, org} = Orgs.create_organization(%{name: "Орг", slug: "org-widget"})

    {:ok, user} =
      Accounts.create_user(%{
        org_id: org.id,
        username: "emp",
        full_name: "Сотрудник Сотов",
        password: "SecurePass123!",
        role: :employee
      })

    %{org: org, user: user}
  end

  defp login(conn, user), do: init_test_session(conn, %{user_id: user.id, org_id: user.org_id})

  test "виджет есть на каждой странице админки", %{conn: conn, user: user} do
    for path <- ["/admin", "/admin/meetings", "/admin/calendar", "/admin/notifications"] do
      {:ok, _lv, html} = conn |> login(user) |> live(path)

      assert html =~ ~s(id="svc-assistant"), "#{path}: виджет не отрендерился"
      assert html =~ ~s(phx-hook="Assistant"), "#{path}: не подключён JS-хук"
    end
  end

  test "переписка не затирается патчами LiveView" do
    # phx-update="ignore" — без него LiveView перерисовывает виджет на каждом
    # патче страницы и стирает уже показанные ответы.
    conn = build_conn()
    {:ok, org} = Orgs.create_organization(%{name: "Орг2", slug: "org-widget2"})

    {:ok, user} =
      Accounts.create_user(%{
        org_id: org.id,
        username: "emp2",
        full_name: "Второй",
        password: "SecurePass123!",
        role: :employee
      })

    {:ok, _lv, html} = conn |> login(user) |> live("/admin")
    assert html =~ ~s(phx-update="ignore")
  end

  test "панель по умолчанию скрыта", %{conn: conn, user: user} do
    {:ok, _lv, html} = conn |> login(user) |> live("/admin")
    assert html =~ ~s(id="svc-assistant-panel")
    assert html =~ "hidden"
  end
end
