defmodule Svc.OrgsTest do
  use Svc.DataCase, async: true

  alias Svc.Orgs

  describe "organizations" do
    test "create_organization/1 с валидными данными" do
      assert {:ok, org} = Orgs.create_organization(%{name: "Минцифры", slug: "mincifra"})
      assert org.name == "Минцифры"
      assert org.slug == "mincifra"
      assert org.status == :active
    end

    test "create_organization/1 нормализует slug в lowercase" do
      assert {:ok, org} = Orgs.create_organization(%{name: "Test", slug: "MyOrg"})
      assert org.slug == "myorg"
    end

    test "create_organization/1 требует name и slug" do
      assert {:error, cs} = Orgs.create_organization(%{})
      errors = errors_on(cs)
      assert errors[:name]
      assert errors[:slug]
    end

    test "create_organization/1 уникальность slug" do
      {:ok, _} = Orgs.create_organization(%{name: "Орг А", slug: "dup"})
      assert {:error, cs} = Orgs.create_organization(%{name: "Орг Б", slug: "dup"})
      assert errors_on(cs)[:slug]
    end
  end

  describe "departments — иерархия (D-007)" do
    setup do
      {:ok, org} = Orgs.create_organization(%{name: "Org", slug: "org"})
      %{org: org}
    end

    test "create_department/1 создаёт корневой отдел", %{org: org} do
      assert {:ok, dept} = Orgs.create_department(%{org_id: org.id, name: "Ведомство"})
      assert dept.name == "Ведомство"
      assert is_nil(dept.parent_id)
    end

    test "create_department/1 требует org_id и name" do
      assert {:error, cs} = Orgs.create_department(%{})
      assert errors_on(cs)[:name]
    end

    test "subtree_ids/2 возвращает отдел + всех потомков", %{org: org} do
      {:ok, root} = Orgs.create_department(%{org_id: org.id, name: "Ведомство"})
      {:ok, mid} = Orgs.create_department(%{org_id: org.id, parent_id: root.id, name: "Управление"})
      {:ok, leaf} = Orgs.create_department(%{org_id: org.id, parent_id: mid.id, name: "Отдел"})
      {:ok, _other} = Orgs.create_department(%{org_id: org.id, name: "Другое ведомство"})

      assert Enum.sort(Orgs.subtree_ids(org.id, root.id)) ==
               Enum.sort([root.id, mid.id, leaf.id])
    end

    test "subtree_ids/2 для листа возвращает только его", %{org: org} do
      {:ok, root} = Orgs.create_department(%{org_id: org.id, name: "Root"})
      {:ok, leaf} = Orgs.create_department(%{org_id: org.id, parent_id: root.id, name: "Leaf"})
      assert Orgs.subtree_ids(org.id, leaf.id) == [leaf.id]
    end

    test "subtree_ids/2 строго scoped по org_id — не пересекает тенанты (D-005)", %{org: org} do
      {:ok, other} = Orgs.create_organization(%{name: "Other", slug: "other"})
      {:ok, root} = Orgs.create_department(%{org_id: org.id, name: "Root"})
      {:ok, _foreign} = Orgs.create_department(%{org_id: other.id, name: "Foreign"})
      assert Orgs.subtree_ids(org.id, root.id) == [root.id]
    end
  end
end
