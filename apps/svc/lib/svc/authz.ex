defmodule Svc.Authz do
  @moduledoc """
  RBAC + department-scoping (D-007).

  Видимость данных по иерархии:
  - super_admin / admin_hr / security_officer → вся организация;
  - manager → свой отдел + всё поддерево (рекурсия) + сам;
  - employee → только сам.

  Всё строго в рамках org_id (D-005).
  """
  import Ecto.Query
  alias Svc.Repo
  alias Svc.Accounts.User
  alias Svc.Orgs
  alias Svc.Orgs.Department

  @org_wide_roles [:super_admin, :admin_hr, :security_officer]

  @doc "Видит ли роль всю организацию."
  def org_wide?(%User{role: role}), do: role in @org_wide_roles

  @doc "ID отделов, видимых актору."
  @spec visible_department_ids(User.t()) :: [integer()]
  def visible_department_ids(%User{role: role, org_id: org_id}) when role in @org_wide_roles do
    Repo.all(from d in Department, where: d.org_id == ^org_id, select: d.id)
  end

  def visible_department_ids(%User{role: :manager, org_id: org_id, department_id: dept_id})
      when not is_nil(dept_id) do
    Orgs.subtree_ids(org_id, dept_id)
  end

  def visible_department_ids(%User{}), do: []

  @doc "ID пользователей, видимых актору (для журналов посещаемости, админки)."
  @spec visible_user_ids(User.t()) :: [integer()]
  def visible_user_ids(%User{role: role, org_id: org_id}) when role in @org_wide_roles do
    Repo.all(from u in User, where: u.org_id == ^org_id, select: u.id)
  end

  def visible_user_ids(%User{role: :manager, org_id: org_id, department_id: dept_id, id: own_id})
      when not is_nil(dept_id) do
    dept_ids = Orgs.subtree_ids(org_id, dept_id)

    user_ids =
      Repo.all(
        from u in User,
          where: u.org_id == ^org_id and u.department_id in ^dept_ids,
          select: u.id
      )

    Enum.uniq([own_id | user_ids])
  end

  def visible_user_ids(%User{id: id}), do: [id]

  @doc "Видит ли актор данного пользователя?"
  def can_view_user?(%User{} = actor, target_user_id) do
    target_user_id in visible_user_ids(actor)
  end

  @doc "Ограничивает запрос users видимостью актора (для списков/журналов)."
  def scope_users(%User{} = actor, query \\ User) do
    ids = visible_user_ids(actor)
    from u in query, where: u.id in ^ids
  end
end
