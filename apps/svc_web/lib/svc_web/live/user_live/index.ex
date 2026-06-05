defmodule SvcWeb.UserLive.Index do
  @moduledoc "Список сотрудников (RBAC-scoped) + создание (E0)."
  use SvcWeb, :live_view

  import Ecto.Query
  alias Svc.{Accounts, Authz, Audit, Orgs}

  @per_page 10

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     allow_upload(socket, :photo,
       accept: ~w(.jpg .jpeg .png),
       max_entries: 1,
       max_file_size: 5_000_000
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:filters, parse_filters(params))
     |> apply_action(socket.assigns.live_action)}
  end

  defp parse_filters(params) do
    %{
      q: params["q"] || "",
      role: params["role"] || "",
      status: params["status"] || "",
      page: parse_page(params["page"])
    }
  end

  defp parse_page(p) do
    case Integer.parse(to_string(p)) do
      {n, _} when n > 0 -> n
      _ -> 1
    end
  end

  defp apply_action(socket, :index) do
    actor = socket.assigns.current_user

    socket
    |> assign(:page_title, "Сотрудники")
    |> assign(:can_manage, can_manage?(actor))
    |> assign(:departments, [])
    |> assign(:form, nil)
    |> load_users()
  end

  defp apply_action(socket, :new) do
    actor = socket.assigns.current_user

    if can_manage?(actor) do
      socket
      |> assign(:page_title, "Новый сотрудник")
      |> assign(:can_manage, true)
      |> assign(:departments, Orgs.list_departments(actor.org_id))
      |> assign(:form, to_form(Accounts.change_user_creation()))
      |> load_users()
    else
      socket
      |> put_flash(:error, "Недостаточно прав для создания сотрудников.")
      |> push_navigate(to: ~p"/admin/users")
    end
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    form =
      params
      |> Accounts.change_user_creation()
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"user" => params}, socket) do
    actor = socket.assigns.current_user
    photo_path = consume_photo(socket, actor.org_id)

    params =
      params
      |> Map.put("org_id", actor.org_id)
      |> then(&if(photo_path, do: Map.put(&1, "photo_path", photo_path), else: &1))

    case Accounts.create_user(params) do
      {:ok, user} ->
        Audit.log_action(actor, :user_create, resource_type: :user, resource_id: user.id)

        {:noreply,
         socket
         |> put_flash(:info, "Сотрудник #{user.full_name} создан.")
         |> push_navigate(to: ~p"/admin/users")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("filter", %{"q" => q, "role" => role, "status" => status}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/users?#{filter_params(q, role, status)}")}
  end

  defp filter_params(q, role, status) do
    %{page: 1}
    |> put_if(:q, q)
    |> put_if(:role, role)
    |> put_if(:status, status)
  end

  defp put_if(map, _key, ""), do: map
  defp put_if(map, key, val), do: Map.put(map, key, val)

  defp load_users(socket) do
    f = socket.assigns.filters
    base = socket.assigns.current_user |> Authz.scope_users() |> apply_filters(f)
    total = Svc.Repo.aggregate(base, :count)
    pages = max(1, ceil(total / @per_page))
    page = min(f.page, pages)

    users =
      base
      |> order_by(:full_name)
      |> limit(^@per_page)
      |> offset(^((page - 1) * @per_page))
      |> Svc.Repo.all()

    assign(socket, users: users, total: total, pages: pages, page: page)
  end

  defp apply_filters(query, f) do
    query
    |> filter_search(f.q)
    |> filter_role(f.role)
    |> filter_status(f.status)
  end

  defp filter_search(query, ""), do: query

  defp filter_search(query, term) do
    like = "%#{term}%"
    where(query, [u], ilike(u.full_name, ^like) or ilike(u.username, ^like))
  end

  defp filter_role(query, ""), do: query
  defp filter_role(query, role), do: where(query, [u], u.role == ^String.to_existing_atom(role))

  defp filter_status(query, ""), do: query
  defp filter_status(query, status), do: where(query, [u], u.status == ^String.to_existing_atom(status))

  # Сохраняет загруженное фото в priv/static/uploads/photos, возвращает публичный путь.
  defp consume_photo(socket, org_id) do
    consume_uploaded_entries(socket, :photo, fn %{path: tmp}, entry ->
      dir = Path.join([:code.priv_dir(:svc_web), "static", "uploads", "photos"])
      File.mkdir_p!(dir)
      name = "#{org_id}_#{System.unique_integer([:positive])}#{Path.extname(entry.client_name)}"
      File.cp!(tmp, Path.join(dir, name))
      {:ok, "/uploads/photos/#{name}"}
    end)
    |> List.first()
  end

  defp can_manage?(%{role: role}), do: role in [:super_admin, :admin_hr]

  defp role_options, do: Enum.map(Accounts.User.roles(), &{role_label(&1), &1})
  defp dept_options(depts), do: Enum.map(depts, &{&1.name, &1.id})

  defp role_label(:super_admin), do: "Суперадмин"
  defp role_label(:admin_hr), do: "Админ/HR"
  defp role_label(:manager), do: "Руководитель"
  defp role_label(:employee), do: "Сотрудник"
  defp role_label(:security_officer), do: "Офицер безопасности"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="users" current_user={@current_user}>
      <div class="flex items-start justify-between gap-4 mb-6">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight">Сотрудники</h1>
          <p class="text-sm text-base-content/55 mt-1">Список ограничен вашей ролью · department-scoping</p>
        </div>
        <.link
          :if={@can_manage and @live_action == :index}
          navigate={~p"/admin/users/new"}
          class="btn btn-primary gap-2"
        >
          <.icon name="hero-plus" class="size-4" /> Сотрудник
        </.link>
      </div>

      <div :if={@live_action == :new} class="rounded-xl border border-base-300 bg-base-100/50 p-5 mb-5">
        <h3 class="font-medium mb-4 flex items-center gap-2">
          <.icon name="hero-user-plus" class="size-4 text-primary" /> Новый сотрудник
        </h3>
        <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-3">
          <.input field={@form[:full_name]} type="text" label="ФИО" required />
          <.input field={@form[:username]} type="text" label="Логин" required />
          <.input field={@form[:phone]} type="text" label="Телефон (Номер)" />
          <div>
            <label class="block text-sm font-medium mb-1">Фото (jpg/png, до 5 МБ)</label>
            <.live_file_input
              upload={@uploads.photo}
              class="file-input file-input-sm file-input-bordered w-full"
            />
            <div :for={entry <- @uploads.photo.entries} class="text-xs opacity-60 mt-1">
              {entry.client_name} · {entry.progress}%
            </div>
            <div :for={err <- upload_errors(@uploads.photo)} class="text-xs text-error mt-1">
              {inspect(err)}
            </div>
          </div>
          <.input
            field={@form[:password]}
            type="password"
            label="Временный пароль (мин. 12 символов)"
            required
          />
          <.input field={@form[:role]} type="select" label="Роль" options={role_options()} />
          <.input
            field={@form[:department_id]}
            type="select"
            label="Отдел"
            options={dept_options(@departments)}
            prompt="— не выбран —"
          />
          <div class="flex gap-2 pt-2">
            <.button type="submit" phx-disable-with="Создаём...">Создать</.button>
            <.link navigate={~p"/admin/users"} class="btn btn-ghost">Отмена</.link>
          </div>
        </.form>
      </div>

      <div :if={@live_action == :index} class="flex flex-wrap items-center gap-2 mb-4">
        <form phx-change="filter" phx-submit="filter" class="flex flex-wrap items-center gap-2 flex-1">
          <div class="relative flex-1 min-w-52">
            <.icon name="hero-magnifying-glass" class="size-4 absolute left-3 top-1/2 -translate-y-1/2 text-base-content/40" />
            <input
              type="text"
              name="q"
              value={@filters.q}
              placeholder="Поиск по ФИО или логину"
              phx-debounce="300"
              class="input input-sm input-bordered w-full pl-9 bg-base-100"
            />
          </div>
          <select name="role" class="select select-sm select-bordered bg-base-100">
            <option value="">Все роли</option>
            <option :for={{label, val} <- role_options()} value={val} selected={to_string(val) == @filters.role}>
              {label}
            </option>
          </select>
          <select name="status" class="select select-sm select-bordered bg-base-100">
            <option value="">Любой статус</option>
            <option value="active" selected={@filters.status == "active"}>Активен</option>
            <option value="disabled" selected={@filters.status == "disabled"}>Отключён</option>
          </select>
        </form>
      </div>

      <div class="rounded-xl border border-base-300 bg-base-100/50 overflow-hidden">
        <div :if={@users == []} class="px-5 py-10 text-center text-sm text-base-content/40">
          <.icon name="hero-magnifying-glass" class="size-8 mx-auto mb-2 opacity-40" /> Ничего не найдено
        </div>
        <table :if={@users != []} class="w-full text-sm">
          <thead>
            <tr class="text-left text-xs uppercase tracking-wider text-base-content/40 border-b border-base-300">
              <th class="font-medium px-5 py-2.5">Сотрудник</th>
              <th class="font-medium px-5 py-2.5">Логин</th>
              <th class="font-medium px-5 py-2.5">Роль</th>
              <th class="font-medium px-5 py-2.5">2FA</th>
              <th class="font-medium px-5 py-2.5">Статус</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-base-300/50">
            <tr :for={u <- @users} class="hover:bg-base-200/40 transition">
              <td class="px-5 py-3">
                <.link navigate={~p"/admin/users/#{u.id}"} class="flex items-center gap-3 group">
                  <.avatar user={u} />
                  <span class="font-medium group-hover:text-primary transition">{u.full_name}</span>
                </.link>
              </td>
              <td class="px-5 py-3 tabular text-base-content/65">{u.username}</td>
              <td class="px-5 py-3">
                <span class="text-xs px-2 py-0.5 rounded-full bg-base-200 text-base-content/75">
                  {role_label(u.role)}
                </span>
              </td>
              <td class="px-5 py-3">
                <span :if={u.totp_enabled} class="inline-flex items-center gap-1 text-xs text-success">
                  <.icon name="hero-shield-check" class="size-3.5" /> вкл
                </span>
                <span :if={!u.totp_enabled} class="text-xs text-base-content/30">—</span>
              </td>
              <td class="px-5 py-3">
                <span class={["text-xs", u.status == :active && "text-success", u.status != :active && "text-base-content/40"]}>
                  {u.status}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={@live_action == :index and @pages > 1} class="flex items-center justify-between mt-4 text-sm">
        <span class="text-base-content/55 tabular">{@total} сотрудников · стр. {@page} из {@pages}</span>
        <div class="flex items-center gap-1">
          <.link
            patch={page_path(@filters, @page - 1)}
            class={["btn btn-sm btn-ghost btn-square", @page <= 1 && "pointer-events-none opacity-30"]}
          >
            <.icon name="hero-chevron-left" class="size-4" />
          </.link>
          <.link
            patch={page_path(@filters, @page + 1)}
            class={["btn btn-sm btn-ghost btn-square", @page >= @pages && "pointer-events-none opacity-30"]}
          >
            <.icon name="hero-chevron-right" class="size-4" />
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp page_path(f, page) do
    params =
      %{page: page}
      |> put_if(:q, f.q)
      |> put_if(:role, f.role)
      |> put_if(:status, f.status)

    ~p"/admin/users?#{params}"
  end

  attr :user, :map, required: true

  defp avatar(assigns) do
    ~H"""
    <span class="grid place-items-center size-8 rounded-full bg-primary/15 text-primary text-xs font-medium ring-1 ring-primary/15 overflow-hidden shrink-0">
      <img :if={@user.photo_path} src={@user.photo_path} class="w-full h-full object-cover" alt="" />
      <span :if={!@user.photo_path}>{initials(@user.full_name)}</span>
    </span>
    """
  end

  defp initials(name) do
    name |> String.split() |> Enum.take(2) |> Enum.map_join(&String.first/1)
  end
end
