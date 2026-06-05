defmodule Svc.Orgs do
  @moduledoc """
  Контекст организаций и иерархии отделов (E0).
  Иерархия — основа department-scoping RBAC (D-007).
  """
  import Ecto.Query
  alias Svc.Repo
  alias Svc.Orgs.{Organization, Department}

  ## Organizations

  def create_organization(attrs) do
    %Organization{} |> Organization.changeset(attrs) |> Repo.insert()
  end

  def get_organization!(id), do: Repo.get!(Organization, id)

  def list_organizations, do: Repo.all(from o in Organization, order_by: o.name)

  @doc """
  Единственная организация (single-tenant, D-005). В multi-tenant
  заменится на разрешение org из контекста (subdomain/slug).
  """
  def default_organization, do: Repo.one(from o in Organization, order_by: o.id, limit: 1)

  ## Departments (всё scoped по org_id — D-005)

  def create_department(attrs) do
    %Department{} |> Department.changeset(attrs) |> Repo.insert()
  end

  def get_department!(org_id, id) do
    Repo.get_by!(Department, id: id, org_id: org_id)
  end

  def list_departments(org_id) do
    Repo.all(from d in Department, where: d.org_id == ^org_id, order_by: d.name)
  end

  @doc """
  ID поддерева отдела (сам + все потомки) через рекурсивный CTE.
  Используется в department-scoping (D-007): Manager видит свой отдел + поддерево.
  Строго scoped по `org_id` (D-005) — не пересекает тенанты.
  """
  @spec subtree_ids(integer(), integer()) :: [integer()]
  def subtree_ids(org_id, root_id) do
    base =
      from d in Department,
        where: d.org_id == ^org_id and d.id == ^root_id,
        select: %{id: d.id}

    recursion =
      from d in Department,
        join: s in "subtree",
        on: d.parent_id == s.id,
        where: d.org_id == ^org_id,
        select: %{id: d.id}

    subtree = union_all(base, ^recursion)

    from(s in "subtree", select: s.id)
    |> recursive_ctes(true)
    |> with_cte("subtree", as: ^subtree)
    |> Repo.all()
  end
end
